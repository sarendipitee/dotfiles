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

path_owner_uid() {
	local path="$1"
	local owner_uid
	if owner_uid=$(stat -f '%u' "$path" 2>/dev/null); then
		printf '%s\n' "$owner_uid"
	else
		stat -c '%u' "$path"
	fi
}

path_mode() {
	local path="$1"
	local mode
	if mode=$(stat -f '%Lp' "$path" 2>/dev/null); then
		printf '%s\n' "$mode"
	else
		stat -c '%a' "$path"
	fi
}

validate_path_ancestors() {
	local current_path=/
	local login_uid="$1"
	local mode
	local owner_uid
	local path="$2"
	local path_suffix
	local purpose="$3"

	case "$path" in
		/*) ;;
		*) fatal "$purpose must be an absolute path" ;;
	esac
	path_suffix=${path#/}
	while [ -n "$path_suffix" ]; do
		current_path="${current_path%/}/${path_suffix%%/*}"
		[ -e "$current_path" ] || fatal "$purpose contains a missing path component"
		[ ! -L "$current_path" ] || fatal "$purpose contains a symlink"
		owner_uid=$(path_owner_uid "$current_path") || fatal "Could not inspect $purpose ownership"
		[ "$owner_uid" = 0 ] || [ "$owner_uid" = "$login_uid" ] ||
			fatal "$purpose contains a path component owned by another user"
		mode=$(path_mode "$current_path") || fatal "Could not inspect $purpose permissions"
		(( (8#$mode & 8#022) == 0 )) || fatal "$purpose contains a group- or world-writable path component"
		if [ "$path_suffix" = "${path_suffix#*/}" ]; then
			break
		fi
		path_suffix=${path_suffix#*/}
	done
}

omniroute_binding_works() {
	local mise_bin="$1"
	local package_dir="$2"
	"$mise_bin" exec -- node - "$package_dir" >/dev/null 2>&1 <<'NODE'
const { createRequire } = require("node:module");
const { join } = require("node:path");
const packageDir = process.argv[2];
const requireFromDist = createRequire(join(packageDir, "dist", "package.json"));
try {
  requireFromDist.resolve("better-sqlite3/build/Release/better_sqlite3.node");
} catch {
  process.exit(10);
}
try {
  const Database = requireFromDist("better-sqlite3");
  const database = new Database(":memory:");
  database.close();
} catch {
  process.exit(11);
}
NODE
}

harden_omniroute_env() {
	local binding_status
	local durable_dir="$XDG_STATE_HOME/omniroute"
	local durable_env="$XDG_STATE_HOME/omniroute/.env"
	local package_env
	local install_dir
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local owner_uid
	local package_dir

	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	login_uid=$(id -u "$LOGIN_USER")
	[ "$login_uid" != 0 ] || fatal 'OmniRoute setup refuses root as login user'
	[ "$(id -u)" = "$login_uid" ] && [ "$(id -un)" = "$LOGIN_USER" ] ||
		fatal 'OmniRoute setup must run as login user, not through a root shell'
	install_dir=$("$mise_bin" where npm:omniroute) ||
		fatal 'Could not resolve OmniRoute installation'
	case "$install_dir" in
		/*) ;;
		*) fatal 'Mise returned an invalid OmniRoute installation path' ;;
	esac
	[[ "$install_dir" != *$'\n'* ]] || fatal 'Mise returned multiple OmniRoute installation paths'
	[ -d "$install_dir" ] && [ ! -L "$install_dir" ] || fatal 'OmniRoute installation path is not a safe directory'

	package_dir="$install_dir/lib/node_modules/omniroute"
	[ -d "$package_dir" ] && [ ! -L "$package_dir" ] || fatal 'OmniRoute package path is not a safe directory'
	[ "$(realpath "$package_dir")" = "$package_dir" ] || fatal 'OmniRoute package path contains a symlink'
	package_env="$package_dir/.env"
	[ -f "$package_env" ] && [ ! -L "$package_env" ] || fatal 'OmniRoute package .env is not a regular file'
	validate_path_ancestors "$login_uid" "$package_env" 'OmniRoute package .env path'
	owner_uid=$(path_owner_uid "$package_env") || fatal 'Could not inspect OmniRoute package .env ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'OmniRoute package .env is not owned by login user'
	chmod 0600 "$package_env"

	case "$XDG_STATE_HOME" in
		/*) ;;
		*) fatal 'XDG_STATE_HOME must be an absolute path' ;;
	esac
	validate_path_ancestors "$login_uid" "$XDG_STATE_HOME" 'XDG_STATE_HOME path'
	[ -d "$XDG_STATE_HOME" ] && [ ! -L "$XDG_STATE_HOME" ] || fatal 'XDG_STATE_HOME is not a safe directory'
	owner_uid=$(path_owner_uid "$XDG_STATE_HOME") || fatal 'Could not inspect XDG_STATE_HOME ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'XDG_STATE_HOME is not owned by login user'

	[ ! -L "$durable_dir" ] || fatal 'OmniRoute state directory must not be a symlink'
	if [ ! -e "$durable_dir" ]; then
		mkdir "$durable_dir" || fatal 'Could not create OmniRoute state directory'
	fi
	[ -d "$durable_dir" ] && [ ! -L "$durable_dir" ] || fatal 'OmniRoute state path is not a directory'
	validate_path_ancestors "$login_uid" "$durable_dir" 'OmniRoute state directory path'
	owner_uid=$(path_owner_uid "$durable_dir") || fatal 'Could not inspect OmniRoute state directory ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'OmniRoute state directory is not owned by login user'
	chmod 0700 "$durable_dir"

	if [ -e "$durable_env" ] || [ -L "$durable_env" ]; then
		[ -f "$durable_env" ] && [ ! -L "$durable_env" ] || fatal 'Durable OmniRoute .env is not a regular file'
	else
		bash -c \
			'umask 077; set -o noclobber; command cat -- "$1" > "$2"' \
			bash "$package_env" "$durable_env" || fatal 'Could not seed durable OmniRoute .env'
	fi
	[ -f "$durable_env" ] && [ ! -L "$durable_env" ] || fatal 'Durable OmniRoute .env is not a regular file'
	validate_path_ancestors "$login_uid" "$durable_env" 'Durable OmniRoute .env path'
	owner_uid=$(path_owner_uid "$durable_env") || fatal 'Could not inspect durable OmniRoute .env ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'Durable OmniRoute .env is not owned by login user'
	chmod 0600 "$durable_env"

	if omniroute_binding_works "$mise_bin" "$package_dir"; then
		return 0
	else
		binding_status=$?
	fi
	[ "$binding_status" = 10 ] || fatal 'OmniRoute better-sqlite3 verification failed without a missing binding'
	[ "${OMNIROUTE_REPAIR_ATTEMPTED:-false}" != true ] ||
		fatal 'OmniRoute better-sqlite3 binding is still unavailable after reinstall'
	printf '==> Reinstalling OmniRoute to repair missing better-sqlite3 binding\n'
	"$mise_bin" install --force npm:omniroute || fatal 'Could not reinstall OmniRoute through Mise'
	OMNIROUTE_REPAIR_ATTEMPTED=true harden_omniroute_env
}

write_process_compose_native_environment() {
	local mise_bin="$HOME/.local/bin/mise"
	local native_dir
	local output_path
	local source_path=-

	case "$OS" in
		Darwin)
			native_dir="$XDG_STATE_HOME/process-compose/native"
			output_path="$native_dir/io.sarendipitee.process-compose.plist"
			source_path="$DOTFILES_DIR/packages/launchd/Library/LaunchAgents/io.sarendipitee.process-compose.plist"
			;;
		Linux)
			native_dir="$XDG_CONFIG_HOME/systemd/user/dotfiles-process-compose.service.d"
			output_path="$native_dir/10-xdg-state.conf"
			;;
	esac
	mkdir -p "$native_dir"
	chmod 0700 "$native_dir"
	"$mise_bin" exec -- python - "$OS" "$source_path" "$output_path" "$XDG_STATE_HOME" <<'PY'
import os
import plistlib
import sys
import tempfile

platform, source_path, output_path, state_home = sys.argv[1:]
if not os.path.isabs(state_home) or any(ord(character) < 32 or ord(character) == 127 for character in state_home):
    raise SystemExit("invalid XDG_STATE_HOME for native service")

if platform == "Darwin":
    with open(source_path, "rb") as source:
        service = plistlib.load(source)
    service.setdefault("EnvironmentVariables", {})["XDG_STATE_HOME"] = state_home
    content = plistlib.dumps(service, fmt=plistlib.FMT_XML, sort_keys=False)
else:
    escaped = state_home.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
    content = f'[Service]\nEnvironment="XDG_STATE_HOME={escaped}"\n'.encode()

directory = os.path.dirname(output_path)
descriptor, temporary_path = tempfile.mkstemp(prefix=".native-environment.", dir=directory)
try:
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "wb") as destination:
        destination.write(content)
    os.replace(temporary_path, output_path)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
PY
	printf '%s\n' "$output_path"
}

sanitize_legacy_codex_remote_control_unit() {
	local expected_path="$XDG_CONFIG_HOME/systemd/user/codex-remote-control.service"
	local fragment_path
	local legacy_load_state
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local owner_uid
	local user_systemctl=(systemctl --user)

	login_uid=$(id -u "$LOGIN_USER")
	if [ "$(id -un)" != "$LOGIN_USER" ]; then
		user_systemctl=(
			sudo -u "$LOGIN_USER" env
			"XDG_RUNTIME_DIR=/run/user/$login_uid"
			"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
			systemctl --user
		)
	fi
	legacy_load_state=$("${user_systemctl[@]}" show --property=LoadState --value \
		codex-remote-control.service 2>/dev/null) ||
		fatal 'Could not inspect legacy Codex remote-control service'
	if [ "$legacy_load_state" != not-found ]; then
		[ -n "$legacy_load_state" ] || fatal 'Legacy Codex remote-control service returned empty load state'
		fragment_path=$("${user_systemctl[@]}" show --property=FragmentPath --value \
			codex-remote-control.service 2>/dev/null) ||
			fatal 'Could not locate legacy Codex remote-control unit'
		[ "$fragment_path" = "$expected_path" ] ||
			fatal 'Legacy Codex remote-control unit loaded from unexpected path'
	fi

	if [ ! -e "$expected_path" ] && [ ! -L "$expected_path" ]; then
		return 0
	fi
	[ -f "$expected_path" ] && [ ! -L "$expected_path" ] ||
		fatal 'Legacy Codex remote-control unit is not a regular file'
	validate_path_ancestors "$login_uid" "$(dirname "$expected_path")" \
		'Legacy Codex remote-control unit directory path'
	owner_uid=$(path_owner_uid "$expected_path") ||
		fatal 'Could not inspect legacy Codex remote-control unit ownership'
	[ "$owner_uid" = "$login_uid" ] ||
		fatal 'Legacy Codex remote-control unit is not owned by login user'

	"$mise_bin" exec -- python - "$expected_path" "$login_uid" <<'PY'
import os
import re
import stat
import sys
import tempfile

path, expected_uid = sys.argv[1], int(sys.argv[2])
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise OSError
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "r", encoding="utf-8", newline="") as source:
        lines = source.readlines()
except (OSError, UnicodeError):
    raise SystemExit("could not read legacy Codex remote-control unit")

if any("\x00" in line for line in lines):
    raise SystemExit("legacy Codex remote-control unit contains invalid data")

service_indexes = [index for index, line in enumerate(lines) if line.strip() == "[Service]"]
if len(service_indexes) != 1:
    raise SystemExit("legacy Codex remote-control unit must contain one Service section")

environment_file = "EnvironmentFile=%h/.config/hindsight/hindsight.env"
result = []
inserted = False
for index, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r"^Environment\s*=", stripped) and "OMNIROUTER_API_KEY=" in stripped:
        continue
    if stripped == environment_file:
        continue
    result.append(line)
    if index == service_indexes[0]:
        result.append(environment_file + "\n")
        inserted = True

if not inserted:
    raise SystemExit("could not update legacy Codex remote-control unit")
if any("OMNIROUTER_API_KEY=" in line for line in result):
    raise SystemExit("legacy Codex remote-control unit still contains inline key")

directory = os.path.dirname(path)
descriptor, temporary_path = tempfile.mkstemp(prefix=".codex-remote-control.", dir=directory)
try:
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as destination:
        destination.writelines(result)
        destination.flush()
        os.fsync(destination.fileno())
    os.replace(temporary_path, path)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
PY
}

remove_stale_hindsight_container() {
	local container_id
	local running

	container_id=$(sudo docker ps -aq --filter 'name=^/hindsight$') ||
		fatal 'Could not query stale Hindsight container'
	[ -n "$container_id" ] || return 0
	[[ "$container_id" =~ ^[[:xdigit:]]{12,64}$ ]] ||
		fatal 'Stale Hindsight container query returned invalid identifier'
	running=$(sudo docker container inspect --format '{{.State.Running}}' hindsight 2>/dev/null) ||
		fatal 'Could not inspect stale Hindsight container'
	case "$running" in
		true)
			sudo docker stop -t 30 hindsight >/dev/null ||
				fatal 'Could not stop stale Hindsight container'
			;;
		false) ;;
		*) fatal 'Stale Hindsight container returned invalid running state' ;;
	esac
	container_id=$(sudo docker ps -aq --filter 'name=^/hindsight$') ||
		fatal 'Could not verify stale Hindsight container removal'
	if [ -n "$container_id" ]; then
		sudo docker rm hindsight >/dev/null || fatal 'Could not remove stale Hindsight container'
	fi
}

migrate_linux_process_compose_services() {
	local codex_stop_output
	local hindsight_ownership=false
	local legacy_load_state
	local legacy_unit
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local user_systemctl=(systemctl --user)

	login_uid=$(id -u "$LOGIN_USER")
	if [ "$(id -un)" != "$LOGIN_USER" ]; then
		user_systemctl=(
			sudo -u "$LOGIN_USER" env
			"XDG_RUNTIME_DIR=/run/user/$login_uid"
			"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
			systemctl --user
		)
	fi

	sanitize_legacy_codex_remote_control_unit
	for legacy_unit in \
		codex-remote-control.service \
		codex-remote.service \
		hindsight.service \
		homebrew.et.service \
		omniroute.service; do
		legacy_load_state=$("${user_systemctl[@]}" show --property=LoadState --value "$legacy_unit" 2>/dev/null) ||
			fatal "Could not inspect legacy user service: $legacy_unit"
		[ "$legacy_load_state" = not-found ] && continue
		[ -n "$legacy_load_state" ] || fatal "Legacy user service returned an empty load state: $legacy_unit"
		[ "$legacy_unit" != hindsight.service ] || hindsight_ownership=true
		"${user_systemctl[@]}" disable --now "$legacy_unit" >/dev/null 2>&1 ||
			fatal "Could not disable and stop legacy user service: $legacy_unit"
		! "${user_systemctl[@]}" is-active --quiet "$legacy_unit" ||
			fatal "Legacy user service remains active: $legacy_unit"
		! "${user_systemctl[@]}" is-enabled --quiet "$legacy_unit" ||
			fatal "Legacy user service remains enabled: $legacy_unit"
	done

	codex_stop_output=$("$mise_bin" exec -- codex remote-control --json stop) ||
		fatal 'Could not stop detached Codex remote-control daemon'
	case "$codex_stop_output" in
		*'"status":"stopped"'* | *'"status":"notRunning"'*) ;;
		*) fatal 'Codex remote-control stop returned an unexpected status' ;;
	esac
	if "$hindsight_ownership" || [ "$(current_process_compose_profile)" = aorus ]; then
		remove_stale_hindsight_container
	fi
}

current_process_compose_profile() {
	local host_file="$XDG_CONFIG_HOME/process-compose/host"
	local profile
	local profile_line
	local profile_line_count=0

	if [ -n "${DOTFILES_HOST:-}" ]; then
		profile=$DOTFILES_HOST
	elif [ -e "$host_file" ]; then
		[ -f "$host_file" ] || fatal 'Process Compose host profile is not a regular file'
		profile=
		while IFS= read -r profile_line || [ -n "$profile_line" ]; do
			profile_line_count=$((profile_line_count + 1))
			[ "$profile_line_count" -ne 1 ] || profile=$profile_line
		done < "$host_file"
		[ "$profile_line_count" -eq 1 ] && [ -n "$profile" ] ||
			fatal 'Process Compose host profile must contain one non-empty line'
	else
		profile=$(hostname -s)
	fi
	[[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fatal 'Invalid Process Compose host profile'
	printf '%s\n' "$profile"
}

verify_aorus_process_compose() {
	local curl_timeout
	local deadline
	local interval=${PROCESS_COMPOSE_READY_INTERVAL_SECONDS:-5}
	local mise_bin="$HOME/.local/bin/mise"
	local process_json
	local process_ready
	local remaining
	local sleep_seconds
	local socket_dir
	local socket_path
	local timeout_seconds=${PROCESS_COMPOSE_READY_TIMEOUT_SECONDS:-600}

	[ "$(current_process_compose_profile)" = aorus ] || return 0
	if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ] &&
		[ -O "$XDG_RUNTIME_DIR" ] && [ ! -L "$XDG_RUNTIME_DIR" ]; then
		socket_dir="$XDG_RUNTIME_DIR/dpc"
	else
		socket_dir="$XDG_STATE_HOME/process-compose/run"
	fi
	socket_path="$socket_dir/pc.sock"
	[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] ||
		fatal 'PROCESS_COMPOSE_READY_TIMEOUT_SECONDS must be positive integer'
	[[ "$interval" =~ ^[0-9]+$ ]] ||
		fatal 'PROCESS_COMPOSE_READY_INTERVAL_SECONDS must be non-negative integer'
	command_exists timeout || fatal 'timeout command is required for Process Compose readiness checks'
	deadline=$((SECONDS + timeout_seconds))

	while (( SECONDS < deadline )); do
		process_json=
		process_ready=false
		remaining=$((deadline - SECONDS))
		if [ -S "$socket_path" ]; then
			process_json=$(timeout "${remaining}s" "$mise_bin" exec -- process-compose \
				--use-uds --unix-socket "$socket_path" \
				list -o json 2>/dev/null) || process_json=
		fi
		remaining=$((deadline - SECONDS))
		if [ -n "$process_json" ] && (( remaining > 0 )) &&
			printf '%s' "$process_json" | timeout "${remaining}s" "$mise_bin" exec -- jq -e \
				--argjson names '["eternal-terminal","omniroute","codex-remote-control","hindsight"]' '
			map({key: .name, value: .}) | from_entries as $processes |
			all($names[]; $processes[.] != null and $processes[.].is_running == true and
			  ($processes[.].has_ready_probe != true or $processes[.].is_ready == "Ready"))
		' >/dev/null 2>&1; then
			process_ready=true
		fi
		remaining=$((deadline - SECONDS))
		if "$process_ready" && (( remaining > 0 )); then
			curl_timeout=5
			(( remaining >= curl_timeout )) || curl_timeout=$remaining
			if curl -fsS --max-time "$curl_timeout" \
				http://127.0.0.1:18888/health >/dev/null; then
				return 0
			fi
		fi
		remaining=$((deadline - SECONDS))
		(( remaining > 0 )) || break
		sleep_seconds=$interval
		(( remaining >= sleep_seconds )) || sleep_seconds=$remaining
		(( sleep_seconds == 0 )) || sleep "$sleep_seconds"
	done
	fatal 'Aorus Process Compose replacement services did not become ready'
}

setup_process_compose() {
	local launcher="$HOME/.local/bin/dotfiles-process-compose"
	local native_definition
	native_definition=$(write_process_compose_native_environment)
	[ -x "$launcher" ] || fatal "Process Compose launcher is missing or not executable: $launcher"
	"$launcher" --check

	case "$OS" in
		Darwin)
			local domain
			local label=io.sarendipitee.process-compose
			domain="gui/$(id -u)"
			launchctl enable "$domain/$label"
			launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
			launchctl bootstrap "$domain" "$native_definition"
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
			"${user_systemctl[@]}" stop dotfiles-process-compose.service >/dev/null 2>&1 || true
			! "${user_systemctl[@]}" is-active --quiet dotfiles-process-compose.service ||
				fatal 'Could not stop existing Process Compose service before migration'
			migrate_linux_process_compose_services
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
			verify_aorus_process_compose
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
	fi
	if ! id -nG | tr ' ' '\n' | grep -Fxq docker; then RELOGIN_REQUIRED=true; fi
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
harden_omniroute_env

if [ "$OS" = Darwin ]; then
	setup_process_compose
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
if "$RELOGIN_REQUIRED"; then
	fatal 'Docker group membership changed; log out and back in, then rerun provisioning'
fi
setup_process_compose

if [ -e /var/run/reboot-required ]; then REBOOT_REQUIRED=true; fi

printf 'SSH: %s\n' "$(sudo systemctl is-active ssh 2>/dev/null || printf skipped)"
printf 'Docker: %s\n' "$(sudo systemctl is-active docker 2>/dev/null || printf skipped)"
printf 'Tailscale: %s\n' "$(sudo systemctl is-active tailscaled 2>/dev/null || printf skipped)"
if "$RELOGIN_REQUIRED"; then printf 'Action required: log out and back in for Docker group membership.\n'; fi
if "$REBOOT_REQUIRED"; then printf 'Action required: reboot, then verify nvidia-smi and CUDA container access.\n'; fi
if command_exists tailscale && ! tailscale status >/dev/null 2>&1; then
	printf 'Action required: run tailscale up and authenticate.\n'
fi
