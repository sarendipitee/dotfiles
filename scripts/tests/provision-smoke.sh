#!/usr/bin/env bash

set -Eeo pipefail

repo_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
tmp_dir=$(mktemp -d "$HOME/.dotfiles-provision-smoke.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_mode() {
	local expected="$1" path="$2" actual
	if stat -c '%a' "$path" >/dev/null 2>&1; then
		actual=$(stat -c '%a' "$path")
	else
		actual=$(stat -f '%Lp' "$path")
	fi
	[ "$actual" = "$expected" ] || fail "$path mode is $actual; expected $expected"
}

bash -n \
	"$repo_dir/scripts/provision.sh" \
	"$repo_dir/scripts/bootstrap-system.sh" \
	"$repo_dir/scripts/create-links.sh" \
	"$repo_dir/scripts/install-cuda.sh" \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose"
sh -n "$repo_dir/bootstrap.sh"
zsh -n "$repo_dir/packages/shell/.config/zsh/functions.sh"
"$repo_dir/scripts/provision.sh" --help >/dev/null

bootstrap_mise_version=$(sed -n 's/^MISE_VERSION="\([^"]*\)"/\1/p' "$repo_dir/bootstrap.sh")
config_mise_version=$(sed -n 's/^min_version = "\([^"]*\)"/\1/p' "$repo_dir/packages/mise/.config/mise/config.toml")
[ -n "$bootstrap_mise_version" ] || fail 'Bootstrap Mise version is missing'
[ "$bootstrap_mise_version" = "$config_mise_version" ] || fail 'Bootstrap and config Mise versions differ'

duplicate_system_packages=$(awk -F'"' '/^"(apt|brew):/ { split($2, package, ":"); print package[2] }' \
	"$repo_dir/packages/mise/.config/mise/config.toml" | sort | uniq -d)
[ -z "$duplicate_system_packages" ] || fail "APT/Brew package duplication: $duplicate_system_packages"

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -S warning \
		"$repo_dir/bootstrap.sh" \
		"$repo_dir/scripts/provision.sh" \
		"$repo_dir/scripts/bootstrap-system.sh" \
		"$repo_dir/scripts/create-links.sh" \
		"$repo_dir/scripts/install-cuda.sh" \
		"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose"
fi

yq_bin=$(mise which yq 2>/dev/null || command -v yq) ||
	fail 'yq is required for Process Compose smoke tests'
compose_file="$repo_dir/packages/process-compose/.config/process-compose/process-compose.yaml"
hosts_file="$repo_dir/packages/process-compose/.config/process-compose/hosts.yaml"
"$yq_bin" -e '
  .version == "0.5" and
  .is_strict == true and
  (.processes | tag == "!!map") and
  ((.processes | keys) == ["eternal-terminal", "omniroute"]) and
  (.processes.eternal-terminal.command == "exec etserver --port 2022 --logtostdout") and
  (.processes.eternal-terminal.availability.restart == "always") and
  (.processes.eternal-terminal.availability.backoff_seconds == 5) and
  (.processes.omniroute.command == "exec omniroute serve --no-open --no-recovery") and
  (.processes.omniroute.environment == [
    "DATA_DIR=${HOME}/.local/state/omniroute",
    "OMNIROUTE_SERVER_HOST=127.0.0.1"
  ]) and
  (.processes.omniroute.availability.restart == "always") and
  (.processes.omniroute.availability.backoff_seconds == 5) and
  (.processes.omniroute.readiness_probe.http_get.host == "127.0.0.1") and
  (.processes.omniroute.readiness_probe.http_get.port == 20128) and
  (.processes.omniroute.readiness_probe.http_get.path == "/api/monitoring/health")
' "$compose_file" >/dev/null ||
	fail 'Canonical Process Compose config is invalid'
"$yq_bin" -e '
  tag == "!!map" and
  ((keys) == ["aorus", "sd-mbp"]) and
  (."sd-mbp" == ["eternal-terminal"]) and
  (.aorus == ["eternal-terminal", "omniroute"])
' "$hosts_file" >/dev/null ||
	fail 'Process Compose host mapping is invalid'

grep -Fxq '"node" = "26"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not pin Node 26'
grep -Fxq '"npm:omniroute" = "latest"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not install latest OmniRoute'
grep -Fxq '"brew:et" = "latest"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not install latest Eternal Terminal formula'
grep -Fxq 'export PATH="/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin}"' \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose" ||
	fail 'Process Compose launcher Homebrew PATH is not deterministic'
tracked_process_compose_runtime=$(git -C "$repo_dir" ls-files packages/process-compose | grep -Ei \
	'(^|/)(\.env($|\.)|[^/]*(secret|token|credential)[^/]*|state)(/|$)' || true)
[ -z "$tracked_process_compose_runtime" ] ||
	fail "Process Compose secret or state file is tracked: $tracked_process_compose_runtime"

test_home="$tmp_dir/home"
mkdir -p "$test_home/.config/zsh"
printf 'legacy zshenv\n' > "$test_home/.zshenv"
for legacy_file in flox.sh path.pre-flox.sh path.post-flox.sh; do
	legacy_target=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
		"$repo_dir/packages/shell/.config/zsh/$legacy_file" "$test_home/.config/zsh")
	ln -s "$legacy_target" "$test_home/.config/zsh/$legacy_file"
done
HOME="$test_home" XDG_STATE_HOME="$test_home/.local/state" \
	bash "$repo_dir/scripts/create-links.sh" --backup-known-conflicts >/dev/null 2>&1
HOME="$test_home" XDG_STATE_HOME="$test_home/.local/state" \
	bash "$repo_dir/scripts/create-links.sh" --backup-known-conflicts >/dev/null 2>&1

[ -L "$test_home/.zshenv" ] || fail '.zshenv was not linked'
[ -L "$test_home/.config/zsh/.zshrc" ] || fail 'Zsh config was not linked'
[ -L "$test_home/.config/mise/config.toml" ] || fail 'Mise global config was not linked'
[ -L "$test_home/.config/git/config" ] || fail 'Git config was not linked'
[ -L "$test_home/.config/nvim/init.lua" ] || fail 'Neovim config was not linked'
[ -L "$test_home/.config/process-compose/process-compose.yaml" ] || fail 'Process Compose config was not linked'
[ -L "$test_home/.config/process-compose/hosts.yaml" ] || fail 'Process Compose host mapping was not linked'
[ -L "$test_home/.local/bin/dotfiles-process-compose" ] || fail 'Process Compose launcher was not linked'
grep -R -q '^legacy zshenv$' "$test_home/.local/state/dotfiles/backups" || fail '.zshenv backup missing'
grep -q 'mise/shims' "$test_home/.config/zsh/path.sh" || fail 'Mise shims are absent from shell PATH config'
[ ! -L "$test_home/.config/zsh/flox.sh" ] || fail 'Stow did not remove legacy flox.sh link'
[ ! -L "$test_home/.config/zsh/path.pre-flox.sh" ] || fail 'Stow did not remove legacy pre-Flox PATH link'
[ ! -L "$test_home/.config/zsh/path.post-flox.sh" ] || fail 'Stow did not remove legacy post-Flox PATH link'
if find "$test_home" -type l -lname '*packages/flox/*' | grep -q .; then
	fail 'Legacy Flox package was linked'
fi

case "$(uname -s)" in
	Darwin)
		[ -L "$test_home/Library/LaunchAgents/io.sarendipitee.process-compose.plist" ] ||
			fail 'Process Compose LaunchAgent was not linked on Darwin'
		[ ! -e "$test_home/.config/systemd/user/dotfiles-process-compose.service" ] ||
			fail 'Process Compose systemd unit was linked on Darwin'
		;;
	Linux)
		[ -L "$test_home/.config/systemd/user/dotfiles-process-compose.service" ] ||
			fail 'Process Compose systemd unit was not linked on Linux'
		[ ! -e "$test_home/Library/LaunchAgents/io.sarendipitee.process-compose.plist" ] ||
			fail 'Process Compose LaunchAgent was linked on Linux'
		;;
	esac

platform_mock_bin="$tmp_dir/platform-mock-bin"
mkdir -p "$platform_mock_bin"
cat > "$platform_mock_bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -s ]] || exit 64
printf '%s\n' "$MOCK_UNAME"
EOF
cat > "$platform_mock_bin/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$platform_mock_bin/uname" "$platform_mock_bin/git"

for platform in Darwin Linux; do
	platform_home="$tmp_dir/home-$platform"
	mkdir -p "$platform_home"
	MOCK_UNAME="$platform" PATH="$platform_mock_bin:$PATH" HOME="$platform_home" \
		XDG_STATE_HOME="$platform_home/.local/state" \
		bash "$repo_dir/scripts/create-links.sh" >/dev/null 2>&1
	case "$platform" in
		Darwin)
			[ -L "$platform_home/Library/LaunchAgents/io.sarendipitee.process-compose.plist" ] ||
				fail 'Process Compose LaunchAgent was not linked in mocked Darwin Stow run'
			[ ! -e "$platform_home/.config/systemd/user/dotfiles-process-compose.service" ] ||
				fail 'Process Compose systemd unit was linked in mocked Darwin Stow run'
			;;
		Linux)
			[ -L "$platform_home/.config/systemd/user/dotfiles-process-compose.service" ] ||
				fail 'Process Compose systemd unit was not linked in mocked Linux Stow run'
			[ ! -e "$platform_home/Library/LaunchAgents/io.sarendipitee.process-compose.plist" ] ||
				fail 'Process Compose LaunchAgent was linked in mocked Linux Stow run'
			;;
	esac
done

for legacy_unit in vllm-qwen.service vllm-gemma4.service vllm-step3.service; do
	[ ! -e "$repo_dir/packages/systemd/.config/systemd/user/$legacy_unit" ] ||
		fail "Legacy vLLM unit remains in repository: $legacy_unit"
	[ ! -e "$test_home/.config/systemd/user/$legacy_unit" ] ||
		fail "Legacy vLLM unit was linked: $legacy_unit"
done

mkdir -p "$test_home/.local/bin"
fake_process_compose_log="$tmp_dir/process-compose.log"
cat > "$test_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == exec && "${2:-}" == -- ]] || exit 64
shift 2
tool="$1"
shift
case "$tool" in
	yq) exec env -u XDG_RUNTIME_DIR "$FAKE_REAL_YQ" "$@" ;;
	process-compose)
		printf '<%s>' "$@" >> "$FAKE_PROCESS_COMPOSE_LOG"
		printf '\n' >> "$FAKE_PROCESS_COMPOSE_LOG"
		;;
	*) exit 64 ;;
esac
EOF
chmod +x "$test_home/.local/bin/mise"

launcher="$test_home/.local/bin/dotfiles-process-compose"
: > "$fake_process_compose_log"
runtime_dir="$tmp_dir/runtime"
mkdir -p "$runtime_dir"
chmod 0755 "$runtime_dir"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=sd-mbp HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null ||
	fail 'sd-mbp Process Compose check failed'
expected_sd_mbp="<-f><$test_home/.config/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><--dry-run><up><--><eternal-terminal>"
grep -Fxq -- "$expected_sd_mbp" "$fake_process_compose_log" ||
	fail 'sd-mbp Process Compose argv did not select only eternal-terminal'
grep -Eq -- '<--(port|address|server)(=|>)' "$fake_process_compose_log" &&
	fail 'Process Compose launcher configured a TCP server'
assert_mode 700 "$runtime_dir/dpc"
[ ! -e "$test_home/.local/state/process-compose/run" ] ||
	fail 'Writable owned XDG_RUNTIME_DIR unexpectedly used state-directory socket fallback'

: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=aorus HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null ||
	fail 'aorus Process Compose check failed'
expected_aorus="<-f><$test_home/.config/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><--dry-run><up><--><eternal-terminal><omniroute>"
grep -Fxq -- "$expected_aorus" "$fake_process_compose_log" ||
	fail 'aorus Process Compose argv did not select eternal-terminal then omniroute'

selector_config_home="$tmp_dir/selector-config"
mkdir -p "$selector_config_home/process-compose"
cat > "$selector_config_home/process-compose/process-compose.yaml" <<'EOF'
version: "0.5"
is_strict: true

processes:
  alpha:
    command: "printf alpha"
  beta:
    command: "printf beta"
EOF
cat > "$selector_config_home/process-compose/hosts.yaml" <<'EOF'
override: [alpha]
persistent: [beta]
selected: [alpha, beta]
EOF

: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=selected HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null ||
	fail 'Mapped multi-process Process Compose check failed'
expected_check="<-f><$selector_config_home/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><--dry-run><up><--><alpha><beta>"
grep -Fxq -- "$expected_check" "$fake_process_compose_log" ||
	fail 'Mapped Process Compose check argv was not exact or safe'

: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=selected HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" >/dev/null 2>&1 || fail 'Mapped multi-process Process Compose launch failed'
expected_live="<-f><$selector_config_home/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><up><--><alpha><beta>"
grep -Fxq -- "$expected_live" "$fake_process_compose_log" ||
	fail 'Mapped Process Compose live argv was not exact or safe'

printf '%s\n' persistent > "$selector_config_home/process-compose/host"
: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=override HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null || fail 'DOTFILES_HOST precedence check failed'
grep -Fq -- '<--dry-run><up><--><alpha>' "$fake_process_compose_log" ||
	fail 'DOTFILES_HOST did not override persistent host profile'

: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST= HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null || fail 'Persistent host profile check failed'
grep -Fq -- '<--dry-run><up><--><beta>' "$fake_process_compose_log" ||
	fail 'Persistent host profile was not selected'

for invalid_profile in empty multiline unsafe; do
	case "$invalid_profile" in
		empty) : > "$selector_config_home/process-compose/host" ;;
		multiline) printf 'persistent\noverride\n' > "$selector_config_home/process-compose/host" ;;
		unsafe) printf 'bad/profile\n' > "$selector_config_home/process-compose/host" ;;
	esac
	if FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
		HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" XDG_RUNTIME_DIR="$runtime_dir" \
		"$launcher" --check >"$tmp_dir/invalid-profile-$invalid_profile.out" 2>&1; then
		fail "$invalid_profile persistent host profile did not fail validation"
	fi
done

printf '%s\n' persistent > "$selector_config_home/process-compose/host"
if FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST='bad/profile' HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >"$tmp_dir/invalid-profile-env.out" 2>&1; then
	fail 'Unsafe DOTFILES_HOST profile did not fail validation'
fi

unsafe_runtime_target="$tmp_dir/unsafe-runtime-target"
unsafe_runtime_link="$tmp_dir/unsafe-runtime-link"
mkdir -p "$unsafe_runtime_target"
ln -s "$unsafe_runtime_target" "$unsafe_runtime_link"
: > "$fake_process_compose_log"
FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=sd-mbp HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
	XDG_RUNTIME_DIR="$unsafe_runtime_link" XDG_STATE_HOME="$test_home/.local/state" \
	"$launcher" --check >/dev/null ||
	fail 'Process Compose state-directory socket fallback failed'
grep -Fq -- "<--unix-socket><$test_home/.local/state/process-compose/run/pc.sock>" \
	"$fake_process_compose_log" ||
	fail 'Symlinked XDG_RUNTIME_DIR did not use state-directory socket fallback'
assert_mode 700 "$test_home/.local/state/process-compose/run"

if FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=unknown HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
	"$launcher" --check \
	>"$tmp_dir/unknown-host.out" 2>&1; then
	fail 'Unknown Process Compose host did not fail closed'
fi
grep -q 'unknown host or invalid process list: unknown' "$tmp_dir/unknown-host.out" ||
	fail 'Unknown Process Compose host failure was unclear'

invalid_config_home="$tmp_dir/invalid-config"
mkdir -p "$invalid_config_home/process-compose"
cp "$repo_dir/packages/process-compose/.config/process-compose/process-compose.yaml" \
	"$invalid_config_home/process-compose/process-compose.yaml"
printf 'sd-mbp: [missing-process]\n' > "$invalid_config_home/process-compose/hosts.yaml"
if FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	DOTFILES_HOST=sd-mbp HOME="$test_home" XDG_CONFIG_HOME="$invalid_config_home" \
	"$launcher" --check >"$tmp_dir/undefined-process.out" 2>&1; then
	fail 'Undefined Process Compose process did not fail validation'
fi
grep -q 'undefined process for sd-mbp: missing-process' "$tmp_dir/undefined-process.out" ||
	fail 'Undefined Process Compose process failure was unclear'

setup_process_compose_function=$(awk '
  /^setup_process_compose\(\) \{/ { capture = 1 }
  capture { print }
  capture && /^}/ { exit }
' "$repo_dir/scripts/bootstrap-system.sh")
[ -n "$setup_process_compose_function" ] || fail 'Could not extract setup_process_compose'

lifecycle_home="$tmp_dir/lifecycle-home"
lifecycle_mock_bin="$tmp_dir/lifecycle-mock-bin"
lifecycle_log="$tmp_dir/lifecycle.log"
mkdir -p "$lifecycle_home/.local/bin" "$lifecycle_mock_bin"
cat > "$lifecycle_home/.local/bin/dotfiles-process-compose" <<'EOF'
#!/usr/bin/env bash
printf 'launcher %s\n' "$*" >> "$LIFECYCLE_LOG"
EOF
cat > "$lifecycle_mock_bin/id" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
	-u) printf '%s\n' "${MOCK_UID:-501}" ;;
	-un) printf '%s\n' "$LOGIN_USER" ;;
	*) exit 64 ;;
esac
EOF
cat > "$lifecycle_mock_bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$LIFECYCLE_LOG"
EOF
cat > "$lifecycle_mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$LIFECYCLE_LOG"
EOF
cat > "$lifecycle_mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$LIFECYCLE_LOG"
EOF
chmod +x "$lifecycle_home/.local/bin/dotfiles-process-compose" "$lifecycle_mock_bin"/*

: > "$lifecycle_log"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester OS=Darwin SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; setup_process_compose'
darwin_enable_line=$(grep -nFx 'launchctl enable gui/501/io.sarendipitee.process-compose' "$lifecycle_log" |
	cut -d: -f1 || true)
darwin_bootstrap_line=$(grep -nFx \
	"launchctl bootstrap gui/501 $lifecycle_home/Library/LaunchAgents/io.sarendipitee.process-compose.plist" \
	"$lifecycle_log" | cut -d: -f1 || true)
[ -n "$darwin_enable_line" ] || fail 'macOS lifecycle did not enable exact Process Compose label'
[ -n "$darwin_bootstrap_line" ] || fail 'macOS lifecycle did not bootstrap Process Compose LaunchAgent'
[ "$darwin_enable_line" -lt "$darwin_bootstrap_line" ] ||
	fail 'macOS lifecycle bootstrap preceded launchctl enable'

: > "$lifecycle_log"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester OS=Linux XDG_CONFIG_HOME="$lifecycle_home/.config" DOTFILES_DIR="$repo_dir" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; setup_process_compose'
linger_line=$(grep -nFx 'sudo loginctl enable-linger tester' "$lifecycle_log" | cut -d: -f1 || true)
selector_check_line=$(grep -nFx 'launcher --check' "$lifecycle_log" | cut -d: -f1 || true)
systemd_enable_line=$(grep -nFx \
	'systemctl --user enable dotfiles-process-compose.service' "$lifecycle_log" | cut -d: -f1 || true)
systemd_restart_line=$(grep -nFx \
	'systemctl --user restart dotfiles-process-compose.service' "$lifecycle_log" | cut -d: -f1 || true)
[ -n "$linger_line" ] || fail 'Linux lifecycle did not enable login linger'
[ -n "$selector_check_line" ] || fail 'Linux lifecycle did not validate Process Compose selector'
[ -n "$systemd_enable_line" ] || fail 'Linux lifecycle did not enable Process Compose user service'
[ -n "$systemd_restart_line" ] || fail 'Linux lifecycle did not restart Process Compose user service'
[ "$linger_line" -lt "$systemd_enable_line" ] ||
	fail 'Linux systemctl user enable preceded loginctl enable-linger'
[ "$selector_check_line" -lt "$systemd_enable_line" ] ||
	fail 'Linux systemctl user enable preceded selector validation'
[ "$systemd_enable_line" -lt "$systemd_restart_line" ] ||
	fail 'Linux Process Compose restart preceded systemctl enable'

env -i HOME="$test_home" \
	FLOX_ENV="$repo_dir/packages/flox/envs/global/.flox/run/test" \
	FLOX_TEST_VALUE=retired \
	PATH="/pkg/env/global/bin:/nix/store/flox/bin:$repo_dir/packages/flox/envs/global/.flox/run/test/bin" \
	/bin/zsh -c \
	'command -v uname >/dev/null && command -v sed >/dev/null && command -v tty >/dev/null &&
	 [[ ":$PATH:" == *":/usr/bin:"* ]] && [[ "$PATH" != */packages/flox/* ]] &&
	 [[ "$PATH" != *:/pkg/env/* ]] && [[ "$PATH" != *:/nix/store/* ]] && [[ -z ${FLOX_ENV-}${FLOX_TEST_VALUE-} ]]' \
	>/dev/null 2>&1 || fail 'Zsh could not recover from a retired Flox-only PATH'

ssh_home="$tmp_dir/ssh-home"
mkdir -p "$ssh_home/.ssh/nested" "$tmp_dir/empty-zdotdir"
touch "$ssh_home/.ssh/id_test" "$ssh_home/.ssh/id_test.pub" "$ssh_home/.ssh/known_hosts" "$ssh_home/.ssh/nested/config"
HOME="$ssh_home" ZDOTDIR="$tmp_dir/empty-zdotdir" zsh -f -c \
	"source '$repo_dir/packages/shell/.config/zsh/colors.sh'; source '$repo_dir/packages/shell/.config/zsh/functions.sh'; set_ssh_folder_permissions" >/dev/null
assert_mode 700 "$ssh_home/.ssh"
assert_mode 700 "$ssh_home/.ssh/nested"
assert_mode 600 "$ssh_home/.ssh/id_test"
assert_mode 644 "$ssh_home/.ssh/id_test.pub"
assert_mode 644 "$ssh_home/.ssh/known_hosts"
assert_mode 600 "$ssh_home/.ssh/nested/config"

printf 'Provision smoke tests passed.\n'
