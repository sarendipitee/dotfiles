#!/usr/bin/env bash

set -Eeo pipefail

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
DOTFILES_DIR=$(realpath "${SCRIPT_DIR}/..")
OS=$(uname -s)
LOGIN_USER="${SUDO_USER:-$(id -un)}"
SUDO_KEEPALIVE_PID=
REBOOT_REQUIRED=false
RELOGIN_REQUIRED=false

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

fatal() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

cleanup() {
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	fi
}

keep_sudo_alive() {
	sudo -v
	(
		while kill -0 "$$" 2>/dev/null; do
			sleep 50
			sudo -n true || exit
		done
	) 2>/dev/null &
	SUDO_KEEPALIVE_PID=$!
}

has_nvidia_gpu() {
	local device vendor class
	for device in /sys/bus/pci/devices/*; do
		if [ ! -r "$device/vendor" ] || [ ! -r "$device/class" ]; then
			continue
		fi
		read -r vendor < "$device/vendor"
		read -r class < "$device/class"
		[ "$vendor" = 0x10de ] && [[ "$class" == 0x03* ]] && return 0
	done
	return 1
}

set_ssh_permissions() {
	local ssh_dir="$HOME/.ssh"
	mkdir -p "$ssh_dir"
	chmod 700 "$ssh_dir"
	find "$ssh_dir" -type d -exec chmod 700 {} +
	find "$ssh_dir" -type f -exec chmod 600 {} +
	find "$ssh_dir" -type f \( -name '*.pub' -o -name known_hosts -o -name known_hosts.old \) -exec chmod 644 {} +
}

setup_user_state() {
	mkdir -p \
		"$XDG_CACHE_HOME/zsh" \
		"$XDG_CONFIG_HOME" \
		"$XDG_DATA_HOME" \
		"$XDG_STATE_HOME/zsh"
	touch "$XDG_STATE_HOME/zsh/history"
	set_ssh_permissions
}

setup_process_compose() {
	local launcher="$HOME/.local/bin/dotfiles-process-compose"
	[ -x "$launcher" ] || fatal "Process Compose launcher is missing or not executable: $launcher"
	"$launcher" --check

	case "$OS" in
		Darwin)
			local domain
			local label=io.sarendipitee.process-compose
			local plist="$HOME/Library/LaunchAgents/${label}.plist"
			domain="gui/$(id -u)"
			launchctl enable "$domain/$label"
			launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
			launchctl bootstrap "$domain" "$plist"
			;;
		Linux)
			local login_uid
			local legacy_unit
			local legacy_unit_path
			local legacy_unit_target
			local user_systemctl=(systemctl --user)
			login_uid=$(id -u "$LOGIN_USER")
			sudo loginctl enable-linger "$LOGIN_USER"
			if [ "$(id -un)" != "$LOGIN_USER" ]; then
				user_systemctl=(
					sudo -u "$LOGIN_USER" env
					"XDG_RUNTIME_DIR=/run/user/$login_uid"
					"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
					systemctl --user
				)
			fi
			for legacy_unit in vllm-qwen.service vllm-gemma4.service vllm-step3.service; do
				"${user_systemctl[@]}" disable --now "$legacy_unit" >/dev/null 2>&1 || true
				legacy_unit_path="$XDG_CONFIG_HOME/systemd/user/$legacy_unit"
				legacy_unit_target="$DOTFILES_DIR/packages/systemd/.config/systemd/user/$legacy_unit"
				if [ -L "$legacy_unit_path" ] && [ "$(readlink -f "$legacy_unit_path")" = "$legacy_unit_target" ]; then
					rm -f "$legacy_unit_path"
				fi
			done
			"${user_systemctl[@]}" daemon-reload
			"${user_systemctl[@]}" enable dotfiles-process-compose.service
			"${user_systemctl[@]}" restart dotfiles-process-compose.service
			;;
	esac
}

setup_ssh_server() {
	printf '==> Configuring OpenSSH server\n'
	if [ "${DOTFILES_SSH_KEY_ONLY:-false}" = true ]; then
		[ -s "$HOME/.ssh/authorized_keys" ] || fatal 'DOTFILES_SSH_KEY_ONLY=true requires ~/.ssh/authorized_keys'
		cat <<'EOF' | sudo tee /etc/ssh/sshd_config.d/99-dotfiles.conf >/dev/null
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
		sudo chmod 0644 /etc/ssh/sshd_config.d/99-dotfiles.conf
	fi

	sudo sshd -t
	sudo systemctl enable --now ssh
	if command_exists ufw && sudo ufw status | grep -q '^Status: active'; then
		sudo ufw allow OpenSSH
	fi
	sudo systemctl is-active --quiet ssh || fatal 'OpenSSH server failed to start'
}

docker_ce_installed() {
	dpkg-query -W -f='${db:Status-Abbrev}' docker-ce 2>/dev/null | grep -q '^ii'
}

setup_docker() {
	local pkg conflicts=()
	printf '==> Configuring Docker Engine\n'

	if ! docker_ce_installed; then
		for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
			if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
				conflicts+=("$pkg")
			fi
		done
		[ "${#conflicts[@]}" -eq 0 ] || sudo apt-get remove -y "${conflicts[@]}"

		sudo install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
			sudo tee /etc/apt/keyrings/docker.asc >/dev/null
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
			"$(dpkg --print-architecture)" "$VERSION_CODENAME" |
			sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	fi

	sudo groupadd -f docker
	if ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -Fxq docker; then
		sudo usermod -aG docker "$LOGIN_USER"
		RELOGIN_REQUIRED=true
	fi
	sudo systemctl enable --now docker
	sudo systemctl is-active --quiet docker || fatal 'Docker service failed to start'
	sudo docker version >/dev/null
}

setup_nvidia() {
	printf '==> Configuring NVIDIA compute stack\n'
	[ "$(uname -m)" = x86_64 ] || fatal "NVIDIA automation supports x86_64 only: $(uname -m)"
	sudo apt-get install -y "linux-headers-$(uname -r)" ubuntu-drivers-common

	if ! command_exists nvidia-smi; then
		sudo ubuntu-drivers install
		REBOOT_REQUIRED=true
	fi
	bash "$DOTFILES_DIR/scripts/install-cuda.sh" --toolkit --container-toolkit
	if ! command_exists nvidia-smi || ! nvidia-smi >/dev/null 2>&1; then
		REBOOT_REQUIRED=true
	fi
}

setup_linuxbrew_ca() {
	local brew="/home/linuxbrew/.linuxbrew/bin/brew"
	local cert="/home/linuxbrew/.linuxbrew/etc/openssl@3/cert.pem"
	[ -x "$brew" ] || return 0
	[ -e "$cert" ] && return 0
	printf '==> Linking Linuxbrew OpenSSL CA certificates\n'
	"$brew" postinstall openssl@3 2>&1 | tail -5 || true
	if [ ! -e "$cert" ]; then
		printf 'WARNING: openssl postinstall did not create %s; falling back to system CA bundle\n' "$cert" >&2
		mkdir -p "$(dirname "$cert")"
		cp -f /etc/ssl/certs/ca-certificates.crt "$cert"
	fi
}

setup_tailscale() {
	printf '==> Configuring Tailscale\n'
	if ! command_exists tailscale; then
		sudo install -d -m 0755 /usr/share/keyrings
		curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" |
			sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
		curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" |
			sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y tailscale
	fi
	sudo systemctl enable --now tailscaled
	sudo systemctl is-active --quiet tailscaled || fatal 'tailscaled failed to start'
}

case "$OS" in
	Darwin) ;;
	Linux)
		[ -r /etc/os-release ] || fatal '/etc/os-release is required'
		# shellcheck disable=SC1091
		source /etc/os-release
		[ "${ID:-}" = ubuntu ] || fatal "Unsupported Linux distribution: ${ID:-unknown}"
		case "${VERSION_ID:-}" in 22.04 | 24.04 | 26.04) ;; *) fatal "Unsupported Ubuntu release: ${VERSION_ID:-unknown}" ;; esac
		;;
	*) fatal "Unsupported operating system: $OS" ;;
esac

setup_user_state
setup_process_compose

if [ "$OS" = Darwin ]; then
	printf 'macOS system bootstrap complete. Launch installed GUI applications once to finish their setup.\n'
	exit 0
fi

trap cleanup EXIT
keep_sudo_alive

if [ "${DOTFILES_WITH_SSH:-true}" = true ]; then setup_ssh_server; fi
if [ "${DOTFILES_WITH_DOCKER:-true}" = true ]; then setup_docker; fi
if [ "${DOTFILES_WITH_NVIDIA:-auto}" = true ] || { [ "${DOTFILES_WITH_NVIDIA:-auto}" = auto ] && has_nvidia_gpu; }; then
	setup_nvidia
fi
if [ "${DOTFILES_WITH_TAILSCALE:-true}" = true ]; then setup_tailscale; fi
if [ "${DOTFILES_WITH_LINUXBREW_CA:-true}" = true ]; then setup_linuxbrew_ca; fi

if [ -e /var/run/reboot-required ]; then REBOOT_REQUIRED=true; fi

printf 'SSH: %s\n' "$(sudo systemctl is-active ssh 2>/dev/null || printf skipped)"
printf 'Docker: %s\n' "$(sudo systemctl is-active docker 2>/dev/null || printf skipped)"
printf 'Tailscale: %s\n' "$(sudo systemctl is-active tailscaled 2>/dev/null || printf skipped)"
if "$RELOGIN_REQUIRED"; then printf 'Action required: log out and back in for Docker group membership.\n'; fi
if "$REBOOT_REQUIRED"; then printf 'Action required: reboot, then verify nvidia-smi and CUDA container access.\n'; fi
if command_exists tailscale && ! tailscale status >/dev/null 2>&1; then
	printf 'Action required: run tailscale up and authenticate.\n'
fi
