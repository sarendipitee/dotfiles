#!/usr/bin/env bash

set -Eeo pipefail

PROFILE=full
SSH_OVERRIDE=
DOCKER_OVERRIDE=
NVIDIA_OVERRIDE=
TAILSCALE_OVERRIDE=
HOMEBREW_OVERRIDE=
SSH_KEY_ONLY=false

usage() {
	cat <<'EOF'
Usage: provision.sh [options]

Profiles:
  --profile core       Flox, dotfiles, and Zsh only
  --profile server     Core + SSH, Docker, Tailscale, detected NVIDIA GPU
  --profile desktop    Core + desktop packages, Docker, Tailscale, detected NVIDIA GPU
  --profile full       All applicable components (default)

Component overrides:
  --with-ssh | --without-ssh
  --with-docker | --without-docker
  --with-nvidia | --without-nvidia
  --with-tailscale | --without-tailscale
  --with-homebrew | --without-homebrew
  --ssh-key-only       Disable SSH password auth; requires non-empty authorized_keys
  -h, --help
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--profile)
			[ "$#" -ge 2 ] || { printf 'Missing value for --profile\n' >&2; exit 2; }
			PROFILE="$2"
			shift
			;;
		--with-ssh) SSH_OVERRIDE=true ;;
		--without-ssh) SSH_OVERRIDE=false ;;
		--with-docker) DOCKER_OVERRIDE=true ;;
		--without-docker) DOCKER_OVERRIDE=false ;;
		--with-nvidia) NVIDIA_OVERRIDE=true ;;
		--without-nvidia) NVIDIA_OVERRIDE=false ;;
		--with-tailscale) TAILSCALE_OVERRIDE=true ;;
		--without-tailscale) TAILSCALE_OVERRIDE=false ;;
		--with-homebrew) HOMEBREW_OVERRIDE=true ;;
		--without-homebrew) HOMEBREW_OVERRIDE=false ;;
		--ssh-key-only) SSH_KEY_ONLY=true ;;
		-h | --help) usage; exit 0 ;;
		*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

case "$PROFILE" in
	core)
		WITH_SSH=false
		WITH_DOCKER=false
		WITH_NVIDIA=false
		WITH_TAILSCALE=false
		WITH_HOMEBREW=false
		;;
	server)
		WITH_SSH=true
		WITH_DOCKER=true
		WITH_NVIDIA=auto
		WITH_TAILSCALE=true
		WITH_HOMEBREW=false
		;;
	desktop)
		WITH_SSH=false
		WITH_DOCKER=true
		WITH_NVIDIA=auto
		WITH_TAILSCALE=true
		WITH_HOMEBREW=true
		;;
	full)
		WITH_SSH=true
		WITH_DOCKER=true
		WITH_NVIDIA=auto
		WITH_TAILSCALE=true
		WITH_HOMEBREW=true
		;;
	*) printf 'Unknown profile: %s\n' "$PROFILE" >&2; usage >&2; exit 2 ;;
esac

[ -z "$SSH_OVERRIDE" ] || WITH_SSH="$SSH_OVERRIDE"
[ -z "$DOCKER_OVERRIDE" ] || WITH_DOCKER="$DOCKER_OVERRIDE"
[ -z "$NVIDIA_OVERRIDE" ] || WITH_NVIDIA="$NVIDIA_OVERRIDE"
[ -z "$TAILSCALE_OVERRIDE" ] || WITH_TAILSCALE="$TAILSCALE_OVERRIDE"
[ -z "$HOMEBREW_OVERRIDE" ] || WITH_HOMEBREW="$HOMEBREW_OVERRIDE"

OS=$(uname -s)
ARCH=$(uname -m)
DISTRO_ID=
DISTRO_VERSION=
DISTRO_CODENAME=

case "$OS" in
	Darwin)
		case "$ARCH" in arm64 | x86_64) ;; *) printf 'Unsupported macOS architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
		WITH_SSH=false
		WITH_DOCKER=false
		WITH_NVIDIA=false
		;;
	Linux)
		[ -r /etc/os-release ] || { printf '/etc/os-release is required on Linux\n' >&2; exit 1; }
		# shellcheck disable=SC1091
		source /etc/os-release
		DISTRO_ID="${ID:-}"
		DISTRO_VERSION="${VERSION_ID:-}"
		DISTRO_CODENAME="${VERSION_CODENAME:-}"
		[ "$DISTRO_ID" = ubuntu ] || { printf 'Unsupported Linux distribution: %s\n' "${DISTRO_ID:-unknown}" >&2; exit 1; }
		case "$DISTRO_VERSION" in 22.04 | 24.04 | 26.04) ;; *) printf 'Unsupported Ubuntu release: %s\n' "$DISTRO_VERSION" >&2; exit 1 ;; esac
		case "$ARCH" in x86_64 | aarch64 | arm64) ;; *) printf 'Unsupported Ubuntu architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
		WITH_HOMEBREW=false
		;;
	*) printf 'Unsupported operating system: %s\n' "$OS" >&2; exit 1 ;;
esac

if "$SSH_KEY_ONLY" && ! "$WITH_SSH"; then
	printf '%s\n' '--ssh-key-only requires --with-ssh' >&2
	exit 2
fi
if [ "$OS" = Darwin ] && "$WITH_TAILSCALE" && ! "$WITH_HOMEBREW"; then
	printf '%s\n' 'Tailscale installation on macOS requires Homebrew' >&2
	exit 2
fi

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
export DOTFILES_DIR
DOTFILES_DIR=$(realpath "${SCRIPT_DIR}/..")

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export PROJECTS_BASE_DIR="${PROJECTS_BASE_DIR:-$HOME/projects}"
export PERSONAL_BIN_DIR="${PERSONAL_BIN_DIR:-$HOME/.my/bin}"
export PERSONAL_AUTOLOAD_DIR="${PERSONAL_AUTOLOAD_DIR:-$HOME/.my/autoload}"
export HISTFILE="${HISTFILE:-$XDG_STATE_HOME/zsh/history}"

if [[ "$ARCH" == arm* ]]; then
	export HOMEBREW_PREFIX=/opt/homebrew
else
	export HOMEBREW_PREFIX=/usr/local
fi

# shellcheck disable=SC1091
source "${DOTFILES_DIR}/packages/shell/.config/zsh/colors.sh"

is_directory() {
	[ -n "${1:-}" ] && [ -d "$1" ]
}

is_file() {
	[ -n "${1:-}" ] && [ -f "$1" ]
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

ensure_dir_exists() {
	[ -n "${1:-}" ] || fatal 'Cannot create directory from empty path'
	mkdir -p "$1"
}

set_ssh_folder_permissions() {
	local target_folder="${HOME}/.ssh"
	ensure_dir_exists "$target_folder"
	chmod 700 "$target_folder"
	find "$target_folder" -type d -exec chmod 700 {} +
	find "$target_folder" -type f -exec chmod 600 {} +
	find "$target_folder" -type f \( -name '*.pub' -o -name 'known_hosts' -o -name 'known_hosts.old' \) -exec chmod 644 {} +
}

mkdir -p "${XDG_STATE_HOME}/dotfiles/logs"
LOG_FILE="${XDG_STATE_HOME}/dotfiles/logs/provision-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

CURRENT_STAGE=initialization
SUDO_KEEPALIVE_PID=
REBOOT_REQUIRED=false
RELOGIN_REQUIRED=false
MANUAL_ACTIONS=()

fatal() {
	printf '%s\n' "$(red "ERROR: $*")" >&2
	exit 1
}

stage() {
	CURRENT_STAGE="$1"
	section_header "$1"
}

cleanup() {
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	fi
}

on_error() {
	local exit_code=$?
	printf '%s\n' "$(red "Provisioning failed during '${CURRENT_STAGE}' with exit code ${exit_code}.")" >&2
	printf 'Log: %s\n' "$LOG_FILE" >&2
	exit "$exit_code"
}

keep_sudo_alive() {
	stage 'Authenticating sudo'
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

install_ubuntu_packages() {
	local packages=(
		ca-certificates curl gnupg sudo zsh
	)

	if [ "$PROFILE" != core ]; then
		packages+=(avahi-daemon clang g++ git-lfs libpq-dev llvm make software-properties-common watchman)
	fi
	"$WITH_SSH" && packages+=(openssh-server)
	if "$WITH_NVIDIA"; then
		packages+=("linux-headers-$(uname -r)" pciutils ubuntu-drivers-common)
	fi

	stage 'Installing Ubuntu system packages'
	sudo apt-get update
	sudo apt-get install -y "${packages[@]}"
}

setup_ssh_server() {
	stage 'Setting up OpenSSH server'

	if "$SSH_KEY_ONLY"; then
		[ -s "$HOME/.ssh/authorized_keys" ] || fatal '--ssh-key-only requires non-empty ~/.ssh/authorized_keys'
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
	sudo sshd -T | awk '/^(port|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication) /'
	success 'OpenSSH server is enabled and running'
}

activate_flox() {
	local flox_activation global_flox_env
	stage 'Installing Flox'
	if ! command_exists flox; then
		bash "${DOTFILES_DIR}/scripts/install-flox.sh"
	else
		warn "Flox already installed: $(flox --version)"
	fi
	command_exists flox || fatal 'Flox installation completed without a usable flox command'

	global_flox_env="${DOTFILES_DIR}/packages/flox/envs/global"
	is_file "${global_flox_env}/.flox/env/manifest.toml" || fatal "Global Flox environment missing: ${global_flox_env}"

	stage 'Activating global Flox environment'
	export FLOX_SHELL=bash
	if ! flox_activation=$(flox activate -d "$global_flox_env" -m run); then
		fatal 'Failed to activate global Flox environment'
	fi
	eval "$flox_activation"
	command_exists stow || fatal "Global Flox environment activated without required 'stow' command"
	success 'Global Flox environment activated'
}

setup_dotfiles() {
	stage 'Creating dotfile links'
	bash "${DOTFILES_DIR}/scripts/create-links.sh" --backup-known-conflicts
}

setup_homebrew() {
	stage 'Installing Homebrew'
	if ! command_exists brew; then
		NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		eval "$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"
	fi
	command_exists brew || fatal 'Homebrew installation completed without brew'

	stage 'Installing Homebrew-only packages'
	local brewfile="${DOTFILES_DIR}/packages/homebrew/.config/homebrew/Brewfile"
	brew bundle check --file="$brewfile" || brew bundle --file="$brewfile"
	brew bundle check --file="$brewfile" || fatal 'Homebrew bundle verification failed'
	success 'Homebrew bundle verified'
}

docker_ce_installed() {
	dpkg-query -W -f='${db:Status-Abbrev}' docker-ce 2>/dev/null | grep -q '^ii'
}

setup_docker() {
	local pkg conflicts=()
	stage 'Installing Docker Engine'

	if ! docker_ce_installed; then
		for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
			if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
				conflicts+=("$pkg")
			fi
		done
		[ "${#conflicts[@]}" -eq 0 ] || sudo apt-get remove -y "${conflicts[@]}"

		sudo install -m 0755 -d /etc/apt/keyrings
		sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
			"$(dpkg --print-architecture)" "$DISTRO_CODENAME" |
			sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	fi

	sudo groupadd -f docker
	if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq docker; then
		sudo usermod -aG docker "$USER"
		RELOGIN_REQUIRED=true
		MANUAL_ACTIONS+=('Log out and back in to activate Docker group membership.')
	fi
	sudo systemctl enable --now docker
	sudo systemctl is-active --quiet docker || fatal 'Docker service failed to start'
	sudo docker version >/dev/null
	success 'Docker Engine is enabled and running'
}

setup_nvidia() {
	stage 'Installing NVIDIA compute stack'
	[ "$ARCH" = x86_64 ] || fatal "NVIDIA automation supports x86_64 only: ${ARCH}"

	if ! command_exists nvidia-smi; then
		sudo ubuntu-drivers install
		REBOOT_REQUIRED=true
	fi

	bash "${DOTFILES_DIR}/scripts/install-cuda.sh" --toolkit
	bash "${DOTFILES_DIR}/scripts/install-cuda.sh" --container-toolkit

	if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
		success 'NVIDIA driver, CUDA toolkit, and container runtime verified'
	else
		REBOOT_REQUIRED=true
		MANUAL_ACTIONS+=('Reboot, then run nvidia-smi and a CUDA container smoke test.')
		warn 'NVIDIA driver installed; reboot required before runtime verification'
	fi
}

setup_tailscale() {
	stage 'Installing Tailscale'
	if [[ "$OS" == Linux ]]; then
		if ! command_exists tailscale; then
			sudo install -d -m 0755 /usr/share/keyrings
			curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.noarmor.gpg" |
				sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
			curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.tailscale-keyring.list" |
				sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
			sudo apt-get update
			sudo apt-get install -y tailscale
		fi
		sudo systemctl enable --now tailscaled
		sudo systemctl is-active --quiet tailscaled || fatal 'tailscaled failed to start'
	else
		command_exists brew || fatal 'Homebrew is required to install Tailscale on macOS'
		command_exists tailscale || brew install tailscale
		brew services start tailscale
		brew services list | awk '$1 == "tailscale" { found = 1; if ($2 != "started") exit 1 } END { if (!found) exit 1 }' || \
			fatal 'Tailscale Homebrew service failed to start'
	fi

	if ! tailscale status >/dev/null 2>&1; then
		MANUAL_ACTIONS+=('Run tailscale up and authenticate this machine.')
		warn 'Tailscale installed but not authenticated'
	else
		success 'Tailscale is authenticated and running'
	fi
}

setup_shell() {
	stage 'Creating shell state directories'
	ensure_dir_exists "$PROJECTS_BASE_DIR"
	ensure_dir_exists "$PERSONAL_BIN_DIR"
	ensure_dir_exists "$XDG_CACHE_HOME"
	ensure_dir_exists "$XDG_CONFIG_HOME"
	ensure_dir_exists "$XDG_DATA_HOME"
	ensure_dir_exists "$XDG_STATE_HOME"
	ensure_dir_exists "$XDG_CACHE_HOME/zsh"
	ensure_dir_exists "$XDG_STATE_HOME/zsh"
	touch "$HISTFILE"

	stage 'Validating Zsh, Flox, Stow, and Antidote'
	zsh -lic 'rm -f "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"; autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"; command -v flox >/dev/null; command -v stow >/dev/null; command -v antidote >/dev/null'
	if [ "$OS" = Linux ]; then
		sudo chsh -s "$(command -v zsh)" "$USER"
		[ "$(getent passwd "$USER" | cut -d: -f7)" = "$(command -v zsh)" ] || fatal 'Default shell verification failed'
	fi
	success 'Zsh loaded with Flox, Stow, and Antidote'
}

print_summary() {
	local action default_shell ssh_status docker_status nvidia_status tailscale_status
	stage 'Provisioning summary'
	if command_exists getent; then
		default_shell=$(getent passwd "$USER" | cut -d: -f7)
	else
		default_shell="$SHELL"
	fi
	ssh_status=skipped
	docker_status=skipped
	nvidia_status=skipped
	tailscale_status=skipped
	if "$WITH_SSH"; then
		if sudo systemctl is-active --quiet ssh; then ssh_status=active; else ssh_status=failed; fi
	fi
	if "$WITH_DOCKER"; then
		if sudo systemctl is-active --quiet docker; then docker_status=active; else docker_status=failed; fi
	fi
	if "$WITH_NVIDIA"; then
		if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then nvidia_status=active; else nvidia_status=reboot-pending; fi
	fi
	if "$WITH_TAILSCALE"; then
		if tailscale status >/dev/null 2>&1; then tailscale_status=authenticated; else tailscale_status=authentication-required; fi
	fi
	printf 'Profile: %s\n' "$PROFILE"
	printf 'Platform: %s/%s' "$OS" "$ARCH"
	[ "$OS" = Linux ] && printf ' (%s %s)' "$DISTRO_ID" "$DISTRO_VERSION"
	printf '\nFlox: %s\n' "$(flox --version)"
	printf 'Flox environment: %s\n' "${FLOX_ENV_PROJECT:-unknown}"
	printf 'Default shell: %s\n' "$default_shell"
	printf 'SSH: %s\n' "$ssh_status"
	printf 'Docker: %s\n' "$docker_status"
	printf 'NVIDIA: %s\n' "$nvidia_status"
	printf 'Tailscale: %s\n' "$tailscale_status"
	printf 'Log: %s\n' "$LOG_FILE"
	if "$REBOOT_REQUIRED"; then printf 'Reboot required: yes\n'; fi
	if "$RELOGIN_REQUIRED"; then printf 'New login required: yes\n'; fi
	if [ "${#MANUAL_ACTIONS[@]}" -gt 0 ]; then
		printf 'Manual actions:\n'
		for action in "${MANUAL_ACTIONS[@]}"; do printf '  - %s\n' "$action"; done
	fi
}

trap cleanup EXIT
trap on_error ERR

script_start_time=$(date +%s)
printf 'Provisioning started: %s\n' "$(date)"
printf 'Repository: %s\n' "$DOTFILES_DIR"

if [ "$WITH_NVIDIA" = auto ]; then
	if [ "$OS" = Linux ] && has_nvidia_gpu; then WITH_NVIDIA=true; else WITH_NVIDIA=false; fi
fi
if "$WITH_NVIDIA" && ! "$WITH_DOCKER"; then
	fatal 'NVIDIA container setup requires Docker; use --with-docker or --without-nvidia'
fi
if "$WITH_NVIDIA" && [ "$ARCH" != x86_64 ]; then
	fatal "NVIDIA automation supports x86_64 only: ${ARCH}"
fi
if "$SSH_KEY_ONLY" && [ ! -s "$HOME/.ssh/authorized_keys" ]; then
	fatal '--ssh-key-only requires non-empty ~/.ssh/authorized_keys'
fi

keep_sudo_alive

if [ "$OS" = Darwin ]; then
	stage 'Installing Xcode command-line tools'
	if ! is_directory /Library/Developer/CommandLineTools/usr/bin; then
		touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
		sudo softwareupdate -ia --agree-to-license --force
		rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
	fi
else
	install_ubuntu_packages
fi

activate_flox
setup_dotfiles
setup_shell

if "$WITH_SSH"; then setup_ssh_server; fi
if "$WITH_HOMEBREW"; then setup_homebrew; fi
if "$WITH_DOCKER"; then setup_docker; fi
if "$WITH_NVIDIA"; then setup_nvidia; fi
if "$WITH_TAILSCALE"; then setup_tailscale; fi

if [ "$OS" = Linux ] && [ -e /var/run/reboot-required ]; then
	REBOOT_REQUIRED=true
fi

stage 'Setting SSH client permissions'
set_ssh_folder_permissions

stage 'Setting up cron jobs'
if command_exists recron; then
	recron
	success 'Cron jobs configured'
else
	warn "Skipping cron jobs because 'recron' is unavailable"
fi

print_summary
printf 'Provisioning completed: %s\n' "$(date)"
printf 'Elapsed: %ss\n' "$(( $(date +%s) - script_start_time ))"
