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
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose" \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-codex-remote-control" \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-omniroute"
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
		"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose" \
		"$repo_dir/packages/process-compose/.local/bin/dotfiles-codex-remote-control" \
		"$repo_dir/packages/process-compose/.local/bin/dotfiles-omniroute"
fi

cuda_test_home="$tmp_dir/cuda-root/usr/local/cuda"
cuda_test_mock_bin="$tmp_dir/cuda-mock-bin"
cuda_test_output="$tmp_dir/cuda-output"
cuda_test_sudo_log="$tmp_dir/cuda-sudo-log"
mkdir -p "$cuda_test_home/bin" "$cuda_test_mock_bin"
cat > "$cuda_test_home/bin/nvcc" <<'EOF'
#!/usr/bin/env bash
printf 'Cuda compilation tools, release 13.3, V13.3.42\n'
EOF
cat > "$cuda_test_mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo called\n' >> "$CUDA_TEST_SUDO_LOG"
exit 97
EOF
chmod +x "$cuda_test_home/bin/nvcc" "$cuda_test_mock_bin/sudo"
CUDA_HOME="$cuda_test_home" CUDA_TEST_SUDO_LOG="$cuda_test_sudo_log" \
	PATH="$cuda_test_mock_bin:/usr/bin:/bin" \
	bash -c 'source "$1"; install_cuda_toolkit; install_cuda_toolkit' \
	_ "$repo_dir/scripts/install-cuda.sh" > "$cuda_test_output"
[ "$(grep -c '^CUDA toolkit already installed: .*release 13.3, V13.3.42$' \
	"$cuda_test_output")" -eq 2 ] ||
	fail 'CUDA toolkit detection is not idempotent outside PATH'
[ ! -e "$cuda_test_sudo_log" ] || fail 'CUDA toolkit detection attempted reinstall outside PATH'

yq_bin=$(mise which yq 2>/dev/null || command -v yq) ||
	fail 'yq is required for Process Compose smoke tests'
process_compose_bin=$(mise which process-compose 2>/dev/null || command -v process-compose) ||
	fail 'process-compose is required for Process Compose smoke tests'
compose_file="$repo_dir/packages/process-compose/.config/process-compose/process-compose.yaml"
hosts_file="$repo_dir/packages/process-compose/.config/process-compose/hosts.yaml"
"$yq_bin" -e '
  .version == "0.5" and
  .is_strict == true and
  (.processes | tag == "!!map") and
  ((.processes | length) == 4) and
  (.processes | has("eternal-terminal")) and
  (.processes | has("omniroute")) and
  (.processes | has("codex-remote-control")) and
  (.processes | has("hindsight")) and
  (.processes.eternal-terminal.command == "exec etserver --port 2022 --logtostdout") and
  (.processes.eternal-terminal.availability.restart == "always") and
  (.processes.eternal-terminal.availability.backoff_seconds == 5) and
  (.processes.omniroute.command == "exec ${HOME}/.local/bin/dotfiles-omniroute serve --no-open --no-recovery") and
  ((.processes.omniroute.environment | length) == 2) and
  (.processes.omniroute.environment[0] == "DATA_DIR=${XDG_STATE_HOME}/omniroute") and
  (.processes.omniroute.environment[1] == "OMNIROUTE_SERVER_HOST=127.0.0.1") and
  (.processes.omniroute.availability.restart == "always") and
  (.processes.omniroute.availability.backoff_seconds == 5) and
  (.processes.omniroute.readiness_probe.http_get.host == "127.0.0.1") and
  (.processes.omniroute.readiness_probe.http_get.port == 20128) and
  (.processes.omniroute.readiness_probe.http_get.path == "/api/monitoring/health") and
  (.processes."codex-remote-control".command == "exec ${HOME}/.local/bin/dotfiles-codex-remote-control") and
  (.processes."codex-remote-control".availability.restart == "always") and
  (.processes."codex-remote-control".availability.backoff_seconds == 5) and
  (.processes."codex-remote-control".ready_log_line == "\"mode\":\"foreground\",\"status\":\"(connected|connecting)\"") and
  ((.processes."codex-remote-control".success_exit_codes | length) == 1) and
  (.processes."codex-remote-control".success_exit_codes[0] == 130) and
  (.processes."codex-remote-control".shutdown.signal == 2) and
  (.processes."codex-remote-control".shutdown.timeout_seconds == 10) and
  (.processes.hindsight.command == "exec /usr/bin/docker run --rm --name hindsight --pull always --env-file ${HOME}/.config/hindsight/hindsight.env -p 127.0.0.1:18888:8888 -p 127.0.0.1:19999:9999 -v ${HOME}/.local/share/hindsight:/home/hindsight/.pg0 ghcr.io/vectorize-io/hindsight:latest") and
  (.processes.hindsight.availability.restart == "always") and
  (.processes.hindsight.availability.backoff_seconds == 10) and
  (.processes.hindsight.readiness_probe.http_get.host == "127.0.0.1") and
  (.processes.hindsight.readiness_probe.http_get.port == 18888) and
  (.processes.hindsight.readiness_probe.http_get.path == "/health") and
  (.processes.hindsight.readiness_probe.initial_delay_seconds == 10) and
  (.processes.hindsight.readiness_probe.failure_threshold == 60) and
  (.processes.hindsight.shutdown.command == "/usr/bin/docker stop -t 30 hindsight") and
  (.processes.hindsight.shutdown.timeout_seconds == 40)
' "$compose_file" >/dev/null ||
	fail 'Canonical Process Compose config is invalid'
"$yq_bin" -e '
  tag == "!!map" and
  (length == 2) and
  (."sd-mbp" | length == 1) and
  (."sd-mbp"[0] == "eternal-terminal") and
  (.aorus | length == 4) and
  (.aorus[0] == "eternal-terminal") and
  (.aorus[1] == "omniroute") and
  (.aorus[2] == "codex-remote-control") and
  (.aorus[3] == "hindsight")
' "$hosts_file" >/dev/null ||
	fail 'Process Compose host mapping is invalid'

grep -Fxq '"node" = "26"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not pin Node 26'
grep -Fxq '"npm:@openai/codex" = "latest"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not install latest scoped Codex package'
grep -Fxq '"npm:omniroute" = { version = "latest", allow_builds = ["omniroute", "better-sqlite3"] }' \
	"$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not install latest OmniRoute with narrow native-build allowlist'
grep -Fxq '"brew:et" = "latest"' "$repo_dir/packages/mise/.config/mise/config.toml" ||
	fail 'Mise does not install latest Eternal Terminal formula'
grep -Fxq 'export PATH="/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin}"' \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose" ||
	fail 'Process Compose launcher Homebrew PATH is not deterministic'
grep -Fq '[[ -x "${CUDA_HOME:-/usr/local/cuda}/bin/nvcc" ]]' \
	"$repo_dir/packages/process-compose/.local/bin/dotfiles-process-compose" ||
	fail 'Process Compose launcher does not discover canonical CUDA toolkit'
tracked_process_compose_runtime=$(git -C "$repo_dir" ls-files packages/process-compose | grep -Ei \
	'(^|/)(\.env($|\.)|[^/]*(secret|token|credential)[^/]*|state)(/|$)' || true)
[ -z "$tracked_process_compose_runtime" ] ||
	fail "Process Compose secret or state file is tracked: $tracked_process_compose_runtime"

provision_bootstrap_line=$(grep -nF 'sh "$DOTFILES_DIR/bootstrap.sh" --skip repos,task' \
	"$repo_dir/scripts/provision.sh" | cut -d: -f1 || true)
provision_system_line=$(grep -nF 'bash "$DOTFILES_DIR/scripts/bootstrap-system.sh"' \
	"$repo_dir/scripts/provision.sh" | cut -d: -f1 || true)
harden_call_line=$(grep -nFx 'harden_omniroute_env' "$repo_dir/scripts/bootstrap-system.sh" | cut -d: -f1 || true)
process_compose_call_line=$(grep -nFx 'setup_process_compose' "$repo_dir/scripts/bootstrap-system.sh" |
	cut -d: -f1 | head -1 || true)
docker_call_line=$(grep -nF 'then setup_docker; fi' "$repo_dir/scripts/bootstrap-system.sh" |
	cut -d: -f1 || true)
linux_process_compose_call_line=$(grep -nFx 'setup_process_compose' "$repo_dir/scripts/bootstrap-system.sh" |
	cut -d: -f1 | tail -1 || true)
[ -n "$provision_bootstrap_line" ] && [ -n "$provision_system_line" ] && \
	[ "$provision_bootstrap_line" -lt "$provision_system_line" ] ||
	fail 'System bootstrap does not run after Mise bootstrap install'
[ -n "$harden_call_line" ] && [ -n "$process_compose_call_line" ] && \
	[ "$harden_call_line" -lt "$process_compose_call_line" ] ||
	fail 'OmniRoute .env hardening does not precede Process Compose service start'
[ -n "$docker_call_line" ] && [ -n "$linux_process_compose_call_line" ] &&
	[ "$docker_call_line" -lt "$linux_process_compose_call_line" ] ||
	fail 'Linux Process Compose starts before Docker setup completes'

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
[ -L "$test_home/.local/bin/dotfiles-codex-remote-control" ] ||
	fail 'Codex remote-control wrapper was not linked'
[ -L "$test_home/.local/bin/dotfiles-omniroute" ] || fail 'OmniRoute pre-start wrapper was not linked'
grep -R -q '^legacy zshenv$' "$test_home/.local/state/dotfiles/backups" || fail '.zshenv backup missing'
grep -q 'mise/shims' "$test_home/.config/zsh/path.sh" || fail 'Mise shims are absent from shell PATH config'
CUDA_HOME="$cuda_test_home" HOME="$test_home" zsh -c '
	source "$1"
	source "$2"
	[[ "$CUDA_HOME" == "$3" && "$path[1]" == "$3/bin" ]]
' _ "$test_home/.config/zsh/env.sh" "$test_home/.config/zsh/path.sh" "$cuda_test_home" ||
	fail 'Canonical CUDA toolkit is absent from shell environment'
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
		if [[ -n "${FAKE_XDG_STATE_LOG:-}" ]]; then
			printf '%s\n' "$XDG_STATE_HOME" >> "$FAKE_XDG_STATE_LOG"
		fi
		printf '<%s>' "$@" >> "$FAKE_PROCESS_COMPOSE_LOG"
		printf '\n' >> "$FAKE_PROCESS_COMPOSE_LOG"
		;;
	*) exit 64 ;;
esac
EOF
chmod +x "$test_home/.local/bin/mise"

launcher="$test_home/.local/bin/dotfiles-process-compose"
: > "$fake_process_compose_log"
fake_xdg_state_log="$tmp_dir/process-compose-xdg-state.log"
: > "$fake_xdg_state_log"
runtime_dir="$tmp_dir/runtime"
mkdir -p "$runtime_dir"
chmod 0755 "$runtime_dir"
env -u XDG_STATE_HOME FAKE_REAL_YQ="$yq_bin" FAKE_PROCESS_COMPOSE_LOG="$fake_process_compose_log" \
	FAKE_XDG_STATE_LOG="$fake_xdg_state_log" \
	DOTFILES_HOST=sd-mbp HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
	XDG_RUNTIME_DIR="$runtime_dir" \
	"$launcher" --check >/dev/null ||
	fail 'sd-mbp Process Compose check failed'
expected_sd_mbp="<-f><$test_home/.config/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><--dry-run><up><--><eternal-terminal>"
grep -Fxq -- "$expected_sd_mbp" "$fake_process_compose_log" ||
	fail 'sd-mbp Process Compose argv did not select only eternal-terminal'
grep -Fxq "$test_home/.local/state" "$fake_xdg_state_log" ||
	fail 'Process Compose launcher did not export default XDG_STATE_HOME'
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
expected_aorus="<-f><$test_home/.config/process-compose/process-compose.yaml><-t=false><--disable-dotenv><--use-uds><--unix-socket><$runtime_dir/dpc/pc.sock><--dry-run><up><--><eternal-terminal><omniroute><codex-remote-control><hindsight>"
grep -Fxq -- "$expected_aorus" "$fake_process_compose_log" ||
	fail 'aorus Process Compose argv did not select all declared services in order'

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
	DOTFILES_HOST='' HOME="$test_home" XDG_CONFIG_HOME="$selector_config_home" XDG_RUNTIME_DIR="$runtime_dir" \
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

codex_wrapper_home="$tmp_dir/codex-wrapper-home"
codex_wrapper_env="$codex_wrapper_home/.config/hindsight/hindsight.env"
codex_wrapper_log="$tmp_dir/codex-wrapper.log"
codex_wrapper_secret='codex-wrapper-secret-value'
codex_wrapper_python=$(mise which python 2>/dev/null || command -v python3) ||
	fail 'Python is required for Codex wrapper smoke tests'
export CODEX_WRAPPER_PYTHON="$codex_wrapper_python"
mkdir -p "$codex_wrapper_home/.local/bin" "$codex_wrapper_home/.config/hindsight"
cp "$repo_dir/packages/process-compose/.local/bin/dotfiles-codex-remote-control" \
	"$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control"
cat > "$codex_wrapper_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = python ]; then
	shift 3
	exec "$CODEX_WRAPPER_PYTHON" "$@"
fi
[ "$#" -eq 5 ] && [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = codex ] &&
	[ "$4" = remote-control ] && [ "$5" = --json ] || exit 64
[ "$OMNIROUTER_API_KEY" = "$EXPECTED_API_KEY" ] || exit 65
[ -z "${HINDSIGHT_DATABASE_URL+x}${HINDSIGHT_API_KEY+x}" ] || exit 66
printf '%s\n' child-ok > "$CODEX_WRAPPER_LOG"
EOF
chmod +x "$codex_wrapper_home/.local/bin/mise" \
	"$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control"
printf 'HINDSIGHT_DATABASE_URL=must-not-reach-child\nOMNIROUTER_API_KEY=%s\nHINDSIGHT_API_KEY=also-private\n' \
	"$codex_wrapper_secret" > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
HOME="$codex_wrapper_home" EXPECTED_API_KEY="$codex_wrapper_secret" \
	CODEX_WRAPPER_LOG="$codex_wrapper_log" \
	"$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper.out" 2>&1 || fail 'Codex wrapper did not pass isolated OmniRouter key'
grep -Fxq child-ok "$codex_wrapper_log" || fail 'Codex wrapper did not exec expected child'
grep -q "$codex_wrapper_secret" "$tmp_dir/codex-wrapper.out" &&
	fail 'Codex wrapper printed OmniRouter key'
grep -Eq 'must-not-reach-child|also-private' "$tmp_dir/codex-wrapper.out" &&
	fail 'Codex wrapper printed Hindsight secret'

printf 'OMNIROUTER_API_KEY=%s\nOMNIROUTER_API_KEY=duplicate\n' \
	"$codex_wrapper_secret" > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-duplicate.out" 2>&1; then
	fail 'Codex wrapper accepted duplicate OmniRouter keys'
fi
grep -q "$codex_wrapper_secret" "$tmp_dir/codex-wrapper-duplicate.out" &&
	fail 'Codex duplicate-key rejection printed secret'

printf 'export OMNIROUTER_API_KEY=%s\n' "$codex_wrapper_secret" > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-malformed.out" 2>&1; then
	fail 'Codex wrapper accepted malformed OmniRouter key'
fi

printf '%s\n' 'OMNIROUTER_API_KEY=' > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-empty.out" 2>&1; then
	fail 'Codex wrapper accepted empty OmniRouter key'
fi

printf 'OMNIROUTER_API_KEY=bad\tvalue\n' > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-control.out" 2>&1; then
	fail 'Codex wrapper accepted control character in OmniRouter key'
fi

printf '%s\n' 'HINDSIGHT_API_KEY=private' > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-missing.out" 2>&1; then
	fail 'Codex wrapper accepted missing OmniRouter key'
fi

printf 'OMNIROUTER_API_KEY=%s\n' "$codex_wrapper_secret" > "$codex_wrapper_env"
chmod 0640 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-mode.out" 2>&1; then
	fail 'Codex wrapper accepted permissive Hindsight environment'
fi

chmod 0700 "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-executable.out" 2>&1; then
	fail 'Codex wrapper accepted executable Hindsight environment'
fi

rm "$codex_wrapper_env"
printf 'OMNIROUTER_API_KEY=%s\n' "$codex_wrapper_secret" > "$tmp_dir/codex-wrapper-outside.env"
chmod 0600 "$tmp_dir/codex-wrapper-outside.env"
ln -s "$tmp_dir/codex-wrapper-outside.env" "$codex_wrapper_env"
if HOME="$codex_wrapper_home" "$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-symlink.out" 2>&1; then
	fail 'Codex wrapper accepted symlinked Hindsight environment'
fi
grep -q "$codex_wrapper_secret" "$tmp_dir/codex-wrapper-symlink.out" &&
	fail 'Codex symlink rejection printed secret'

rm "$codex_wrapper_env"
printf 'OMNIROUTER_API_KEY=%s\n' "$codex_wrapper_secret" > "$codex_wrapper_env"
chmod 0600 "$codex_wrapper_env"
codex_owner_mock="$tmp_dir/codex-owner-mock"
mkdir "$codex_owner_mock"
cat > "$codex_owner_mock/stat" <<'EOF'
#!/usr/bin/env bash
for argument in "$@"; do
	path=$argument
done
if [ "$path" = "$WRONG_OWNER_PATH" ]; then
	printf '%s\n' "$((MOCK_LOGIN_UID + 1))"
	exit
fi
exec /usr/bin/stat "$@"
EOF
chmod +x "$codex_owner_mock/stat"
if HOME="$codex_wrapper_home" PATH="$codex_owner_mock:$PATH" \
	WRONG_OWNER_PATH="$codex_wrapper_env" MOCK_LOGIN_UID="$(id -u)" \
	"$codex_wrapper_home/.local/bin/dotfiles-codex-remote-control" \
	>"$tmp_dir/codex-wrapper-owner.out" 2>&1; then
	fail 'Codex wrapper accepted wrong-owner Hindsight environment'
fi
grep -q "$codex_wrapper_secret" "$tmp_dir/codex-wrapper-owner.out" &&
	fail 'Codex owner rejection printed secret'

wrapper_home="$tmp_dir/wrapper-home"
wrapper_install="$wrapper_home/.local/share/mise/installs/npm-omniroute/fake"
wrapper_log="$tmp_dir/wrapper.log"
wrapper_binding_env="$wrapper_install/lib/node_modules/omniroute/.env"
wrapper_durable_env="$wrapper_home/.local/state/omniroute/.env"
mkdir -p "$wrapper_home/.local/bin" "$wrapper_home/.local/state/omniroute" \
	"$wrapper_install/lib/node_modules/omniroute"
chmod 0775 "$wrapper_home/.local" "$wrapper_home/.local/share" \
	"$wrapper_home/.local/share/mise" "$wrapper_home/.local/share/mise/installs"
cp "$repo_dir/packages/process-compose/.local/bin/dotfiles-omniroute" \
	"$wrapper_home/.local/bin/dotfiles-omniroute"
cat > "$wrapper_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = where ] && [ "$2" = npm:omniroute ]; then
	printf '%s\n' "$FAKE_OMNIROUTE_DIR"
	exit
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = python ]; then
	shift 3
	exec /usr/bin/python3 "$@"
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = omniroute ]; then
	[ "$(stat -f '%Lp' "$FAKE_PACKAGE_ENV" 2>/dev/null || stat -c '%a' "$FAKE_PACKAGE_ENV")" = 600 ] || exit 65
	printf '%s\n' "${*:3}" >> "$FAKE_WRAPPER_LOG"
	exit
fi
exit 64
EOF
chmod +x "$wrapper_home/.local/bin/mise" "$wrapper_home/.local/bin/dotfiles-omniroute"
printf '%s\n' 'recreated-package-secret' > "$wrapper_binding_env"
chmod 0644 "$wrapper_binding_env"
printf '%s\n' 'preserved-durable-secret' > "$wrapper_durable_env"
chmod 0600 "$wrapper_durable_env"
: > "$wrapper_log"
HOME="$wrapper_home" FAKE_OMNIROUTE_DIR="$wrapper_install" \
	FAKE_PACKAGE_ENV="$wrapper_binding_env" FAKE_WRAPPER_LOG="$wrapper_log" \
	"$wrapper_home/.local/bin/dotfiles-omniroute" serve --no-open --no-recovery \
	>"$tmp_dir/wrapper.out" 2>&1 || fail 'OmniRoute pre-start package .env convergence failed'
assert_mode 600 "$wrapper_binding_env"
assert_mode 755 "$wrapper_home/.local"
assert_mode 755 "$wrapper_home/.local/share"
assert_mode 755 "$wrapper_home/.local/share/mise"
assert_mode 755 "$wrapper_home/.local/share/mise/installs"
grep -Fxq 'omniroute serve --no-open --no-recovery' "$wrapper_log" ||
	fail 'OmniRoute wrapper did not exec exact service command'
grep -Fxq 'preserved-durable-secret' "$wrapper_durable_env" ||
	fail 'OmniRoute wrapper overwrote durable .env'
grep -q 'recreated-package-secret' "$tmp_dir/wrapper.out" &&
	fail 'OmniRoute wrapper printed package secret contents'

rm "$wrapper_binding_env"
printf '%s\n' 'outside-package-secret' > "$tmp_dir/outside-package-env"
chmod 0644 "$tmp_dir/outside-package-env"
ln -s "$tmp_dir/outside-package-env" "$wrapper_binding_env"
if HOME="$wrapper_home" FAKE_OMNIROUTE_DIR="$wrapper_install" \
	FAKE_PACKAGE_ENV="$wrapper_binding_env" FAKE_WRAPPER_LOG="$wrapper_log" \
	"$wrapper_home/.local/bin/dotfiles-omniroute" serve \
	>"$tmp_dir/wrapper-symlink.out" 2>&1; then
	fail 'Symlinked OmniRoute package .env did not fail before exec'
fi
assert_mode 644 "$tmp_dir/outside-package-env"
[ "$(wc -l < "$wrapper_log" | tr -d ' ')" = 1 ] ||
	fail 'Symlinked OmniRoute package .env reached service exec'

wrapper_outside_install="$tmp_dir/wrapper-outside-install"
mkdir -p "$wrapper_outside_install/lib/node_modules/omniroute"
printf '%s\n' 'outside-home-package-secret' > \
	"$wrapper_outside_install/lib/node_modules/omniroute/.env"
chmod 0775 "$wrapper_outside_install"
chmod 0644 "$wrapper_outside_install/lib/node_modules/omniroute/.env"
if HOME="$wrapper_home" FAKE_OMNIROUTE_DIR="$wrapper_outside_install" \
	FAKE_PACKAGE_ENV="$wrapper_outside_install/lib/node_modules/omniroute/.env" \
	FAKE_WRAPPER_LOG="$wrapper_log" \
	"$wrapper_home/.local/bin/dotfiles-omniroute" serve \
	>"$tmp_dir/wrapper-outside.out" 2>&1; then
	fail 'Outside-home OmniRoute package path did not fail before mutation'
fi
assert_mode 775 "$wrapper_outside_install"
assert_mode 644 "$wrapper_outside_install/lib/node_modules/omniroute/.env"
[ "$(wc -l < "$wrapper_log" | tr -d ' ')" = 1 ] ||
	fail 'Outside-home OmniRoute package path reached service exec'

setup_process_compose_function=$(awk '
  /^command_exists\(\) \{/ { capture = 1 }
  /^setup_ssh_server\(\) \{/ { exit }
  capture { print }
' "$repo_dir/scripts/bootstrap-system.sh")
[ -n "$setup_process_compose_function" ] || fail 'Could not extract setup_process_compose'

omniroute_bootstrap_functions=$(awk '
  /^path_owner_uid\(\) \{/ { capture = 1 }
  /^setup_process_compose\(\) \{/ { exit }
  capture { print }
' "$repo_dir/scripts/bootstrap-system.sh")
[ -n "$omniroute_bootstrap_functions" ] || fail 'Could not extract OmniRoute bootstrap functions'

harden_home="$tmp_dir/harden-home"
harden_install="$harden_home/.local/share/mise/installs/npm-omniroute/fake"
repair_log="$tmp_dir/omniroute-repair.log"
binding_missing="$tmp_dir/omniroute-binding-missing"
mkdir -p "$harden_home/.local/bin" "$harden_home/.local/state" \
	"$harden_install/lib/node_modules/omniroute/dist"
chmod 0775 "$harden_home/.local" "$harden_home/.local/share" \
	"$harden_home/.local/share/mise" "$harden_home/.local/share/mise/installs"
cat > "$harden_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = where ] && [ "$2" = npm:omniroute ]; then
	printf '%s\n' "$FAKE_OMNIROUTE_DIR"
	exit
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = python ]; then
	shift 3
	exec /usr/bin/python3 "$@"
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = node ]; then
	if [ -e "$FAKE_BINDING_MISSING" ]; then
		exit "${FAKE_BINDING_FAILURE_STATUS:-10}"
	fi
	exit 0
fi
if [ "$1" = install ] && [ "$2" = --force ] && [ "$3" = npm:omniroute ]; then
	printf '%s\n' "$*" >> "$FAKE_REPAIR_LOG"
	rm -f "$FAKE_BINDING_MISSING"
	exit
fi
exit 64
EOF
chmod +x "$harden_home/.local/bin/mise"
printf '%s\n' 'smoke-secret-value' > "$harden_install/lib/node_modules/omniroute/.env"
chmod 0644 "$harden_install/lib/node_modules/omniroute/.env"
: > "$repair_log"
if OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER=root FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-root.out" 2>&1; then
	fail 'Root OmniRoute setup did not fail before mutation'
fi
grep -q 'OmniRoute setup refuses root as login user' "$tmp_dir/harden-root.out" ||
	fail 'Root OmniRoute setup failure was unclear'
assert_mode 644 "$harden_install/lib/node_modules/omniroute/.env"

OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden.out" 2>&1 || fail 'Owned OmniRoute package .env hardening failed'
assert_mode 600 "$harden_install/lib/node_modules/omniroute/.env"
assert_mode 755 "$harden_home/.local"
assert_mode 755 "$harden_home/.local/share"
assert_mode 755 "$harden_home/.local/share/mise"
assert_mode 755 "$harden_home/.local/share/mise/installs"
assert_mode 700 "$harden_home/.local/state/omniroute"
assert_mode 600 "$harden_home/.local/state/omniroute/.env"
cmp -s "$harden_install/lib/node_modules/omniroute/.env" \
	"$harden_home/.local/state/omniroute/.env" || fail 'Durable OmniRoute .env was not seeded'
grep -q 'smoke-secret-value' "$tmp_dir/harden.out" && fail 'OmniRoute .env hardening printed secret contents'
[ ! -s "$repair_log" ] || fail 'Healthy OmniRoute binding triggered unnecessary rebuild'

custom_xdg_state="$harden_home/custom-state"
mkdir "$custom_xdg_state"
OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$custom_xdg_state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-custom-xdg.out" 2>&1 || fail 'Custom XDG OmniRoute hardening failed'
assert_mode 700 "$custom_xdg_state/omniroute"
assert_mode 600 "$custom_xdg_state/omniroute/.env"

xdg_probe_script="$tmp_dir/omniroute-xdg-probe.sh"
xdg_probe_config="$tmp_dir/omniroute-xdg-probe.yaml"
xdg_probe_output="$tmp_dir/omniroute-xdg-probe.out"
cat > "$xdg_probe_script" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$DATA_DIR" > "$PROBE_OUTPUT"
EOF
chmod +x "$xdg_probe_script"
# shellcheck disable=SC2016
DOTFILES_XDG_PROBE_SCRIPT="$xdg_probe_script" "$yq_bin" '
  .processes = {
    "omniroute-xdg-probe": {
      "command": ("exec " + strenv(DOTFILES_XDG_PROBE_SCRIPT)),
      "environment": [
        .processes.omniroute.environment[0],
        "PROBE_OUTPUT=${PROBE_OUTPUT}"
      ]
    }
  }
' "$compose_file" > "$xdg_probe_config"
XDG_STATE_HOME="$custom_xdg_state" PROBE_OUTPUT="$xdg_probe_output" \
	"$process_compose_bin" run -f "$xdg_probe_config" --disable-dotenv --no-deps \
	omniroute-xdg-probe >/dev/null 2>"$tmp_dir/omniroute-xdg-probe.err" ||
	fail 'Process Compose custom XDG expansion probe failed'
grep -Fxq "$custom_xdg_state/omniroute" "$xdg_probe_output" ||
	fail 'Process Compose DATA_DIR does not match bootstrap custom XDG state path'

printf '%s\n' 'preserved-durable-value' > "$harden_home/.local/state/omniroute/.env"
chmod 0644 "$harden_home/.local/state/omniroute/.env"
harden_install_v2="$harden_home/.local/share/mise/installs/npm-omniroute/fake-v2"
mkdir -p "$harden_install_v2/lib/node_modules/omniroute/dist"
printf '%s\n' 'replacement-package-value' > "$harden_install_v2/lib/node_modules/omniroute/.env"
chmod 0644 "$harden_install_v2/lib/node_modules/omniroute/.env"
OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install_v2" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-preserve.out" 2>&1 || fail 'Existing durable OmniRoute .env convergence failed'
grep -Fxq 'preserved-durable-value' "$harden_home/.local/state/omniroute/.env" ||
	fail 'Existing durable OmniRoute .env was overwritten across package versions'
assert_mode 600 "$harden_home/.local/state/omniroute/.env"
assert_mode 600 "$harden_install_v2/lib/node_modules/omniroute/.env"

touch "$binding_missing"
OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-repair.out" 2>&1 || fail 'Missing OmniRoute binding repair failed'
grep -Fxq 'install --force npm:omniroute' "$repair_log" ||
	fail 'OmniRoute binding repair did not use conditional Mise reinstall'
[ "$(wc -l < "$repair_log" | tr -d ' ')" = 1 ] || fail 'OmniRoute binding repair ran more than once'

touch "$binding_missing"
if OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_BINDING_FAILURE_STATUS=11 \
	FAKE_REPAIR_LOG="$repair_log" XDG_CONFIG_HOME="$harden_home/.config" \
	XDG_DATA_HOME="$harden_home/.local/share" XDG_STATE_HOME="$harden_home/.local/state" \
	XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-non-binding.out" 2>&1; then
	fail 'Non-binding OmniRoute verification failure did not fail closed'
fi
[ "$(wc -l < "$repair_log" | tr -d ' ')" = 1 ] ||
	fail 'Non-binding OmniRoute verification failure triggered rebuild'
rm "$binding_missing"

rm "$harden_home/.local/state/omniroute/.env"
printf '%s\n' 'symlink-secret-value' > "$tmp_dir/outside-env"
ln -s "$tmp_dir/outside-env" "$harden_home/.local/state/omniroute/.env"
if OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-symlink.out" 2>&1; then
	fail 'Symlinked durable OmniRoute .env did not fail safely'
fi
grep -q 'symlink-secret-value' "$tmp_dir/harden-symlink.out" &&
	fail 'OmniRoute symlink rejection printed secret contents'
assert_mode 644 "$tmp_dir/outside-env"

mkdir "$tmp_dir/outside-state"
ln -s "$tmp_dir/outside-state" "$tmp_dir/linked-state"
if OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$tmp_dir/linked-state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-state-symlink.out" 2>&1; then
	fail 'Symlinked XDG_STATE_HOME did not fail safely'
fi
[ -z "$(find "$tmp_dir/outside-state" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
	fail 'Symlinked XDG_STATE_HOME target was modified'

rm "$harden_home/.local/state/omniroute/.env"
printf '%s\n' 'wrong-owner-secret-value' > "$harden_home/.local/state/omniroute/.env"
chmod 0644 "$harden_home/.local/state/omniroute/.env"
harden_mock_bin="$tmp_dir/harden-mock-bin"
mkdir -p "$harden_mock_bin"
cat > "$harden_mock_bin/stat" <<'EOF'
#!/usr/bin/env bash
for argument in "$@"; do
	path=$argument
done
if [ "$path" = "$WRONG_OWNER_PATH" ]; then
	printf '%s\n' "$((MOCK_LOGIN_UID + 1))"
	exit
fi
exec /usr/bin/stat "$@"
EOF
chmod +x "$harden_mock_bin/stat"
if OMNIROUTE_BOOTSTRAP_FUNCTIONS="$omniroute_bootstrap_functions" \
	HOME="$harden_home" LOGIN_USER="$(id -un)" FAKE_OMNIROUTE_DIR="$harden_install" \
	MOCK_LOGIN_UID="$(id -u)" WRONG_OWNER_PATH="$harden_home/.local/state/omniroute/.env" \
	PATH="$harden_mock_bin:$PATH" \
	FAKE_BINDING_MISSING="$binding_missing" FAKE_REPAIR_LOG="$repair_log" \
	XDG_CONFIG_HOME="$harden_home/.config" XDG_DATA_HOME="$harden_home/.local/share" \
	XDG_STATE_HOME="$harden_home/.local/state" XDG_CACHE_HOME="$harden_home/.cache" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$OMNIROUTE_BOOTSTRAP_FUNCTIONS"; harden_omniroute_env' \
	>"$tmp_dir/harden-owner.out" 2>&1; then
	fail 'Wrong-owner durable OmniRoute .env did not fail safely'
fi
grep -q 'wrong-owner-secret-value' "$tmp_dir/harden-owner.out" &&
	fail 'OmniRoute ownership rejection printed secret contents'
assert_mode 644 "$harden_home/.local/state/omniroute/.env"

lifecycle_home="$tmp_dir/lifecycle-home"
lifecycle_mock_bin="$tmp_dir/lifecycle-mock-bin"
lifecycle_log="$tmp_dir/lifecycle.log"
real_python=$(mise which python 2>/dev/null || command -v python3) ||
	fail 'Python is required for native service generation smoke tests'
real_jq=$(mise which jq 2>/dev/null || command -v jq) ||
	fail 'jq is required for lifecycle smoke tests'
mkdir -p "$lifecycle_home/.local/bin" "$lifecycle_mock_bin"
cat > "$lifecycle_home/.local/bin/dotfiles-process-compose" <<'EOF'
#!/usr/bin/env bash
printf 'launcher %s\n' "$*" >> "$LIFECYCLE_LOG"
EOF
cat > "$lifecycle_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = python ]; then
	shift 3
	exec "$REAL_PYTHON" "$@"
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = codex ] &&
	[ "$4" = remote-control ] && [ "$5" = --json ] && [ "$6" = stop ]; then
	printf 'mise codex remote-control --json stop\n' >> "$LIFECYCLE_LOG"
	printf '%s\n' '{"status":"notRunning"}'
	exit
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = process-compose ]; then
	if [ "${MOCK_PROCESS_READY:-false}" = true ]; then
		cat <<'JSON'
[
  {"name":"eternal-terminal","is_running":true,"has_ready_probe":false,"is_ready":"-"},
  {"name":"omniroute","is_running":true,"has_ready_probe":true,"is_ready":"Ready"},
  {"name":"codex-remote-control","is_running":true,"has_ready_probe":true,"is_ready":"Ready"},
  {"name":"hindsight","is_running":true,"has_ready_probe":true,"is_ready":"Ready"}
]
JSON
	else
		printf '%s\n' '[{"name":"hindsight","is_running":false,"has_ready_probe":true,"is_ready":"Not Ready"}]'
	fi
	exit
fi
if [ "$1" = exec ] && [ "$2" = -- ] && [ "$3" = jq ]; then
	shift 3
	exec "$REAL_JQ" "$@"
fi
exit 64
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
cat > "$lifecycle_mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$LIFECYCLE_LOG"
if [ "${MOCK_CURL_HANG:-false}" = true ]; then
	duration=1
	while [ "$#" -gt 0 ]; do
		if [ "$1" = --max-time ]; then
			duration=$2
			break
		fi
		shift
	done
	sleep "$duration"
	exit 28
fi
[ "${MOCK_HINDSIGHT_HEALTH:-true}" = true ]
EOF
cat > "$lifecycle_mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
duration=${1%s}
shift
if [ "${MOCK_PROCESS_HANG:-false}" = true ]; then
	for argument in "$@"; do
		if [ "$argument" = process-compose ]; then
			sleep "$duration"
			exit 124
		fi
	done
fi
exec "$@"
EOF
cat > "$lifecycle_mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$LIFECYCLE_LOG"
if [ "${1:-}" = docker ] && [ "${2:-}" = ps ]; then
	[ ! -e "$MOCK_HINDSIGHT_STATE" ] || printf '%s\n' 0123456789ab
	exit
fi
if [ "${1:-}" = docker ] && [ "${2:-}" = container ] && [ "${3:-}" = inspect ]; then
	if [ "${4:-}" = --format ]; then
		[ -e "$MOCK_HINDSIGHT_STATE" ] || exit 1
		cat "$MOCK_HINDSIGHT_STATE"
		exit
	fi
	[ -e "$MOCK_HINDSIGHT_STATE" ]
	exit
fi
if [ "${1:-}" = docker ] && [ "${2:-}" = stop ]; then
	printf '%s\n' false > "$MOCK_HINDSIGHT_STATE"
	exit
fi
if [ "${1:-}" = docker ] && [ "${2:-}" = rm ]; then
	rm -f "$MOCK_HINDSIGHT_STATE"
	exit
fi
EOF
cat > "$lifecycle_mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$LIFECYCLE_LOG"
if [ "$1" = --user ] && [ "$2" = show ] && [ "$3" = --property=LoadState ] &&
	[ "$4" = --value ]; then
	if [ "${MOCK_LEGACY_UNITS:-absent}" = present ]; then
		printf '%s\n' loaded
	else
		printf '%s\n' not-found
	fi
	exit
fi
if [ "$1" = --user ] && [ "$2" = show ] && [ "$3" = --property=FragmentPath ] &&
	[ "$4" = --value ] && [ "$5" = codex-remote-control.service ]; then
	printf '%s\n' "$MOCK_CODEX_UNIT"
	exit
fi
if [ "$1" = --user ] && { [ "$2" = is-active ] || [ "$2" = is-enabled ]; }; then
	exit 1
fi
EOF
chmod +x "$lifecycle_home/.local/bin/dotfiles-process-compose" \
	"$lifecycle_home/.local/bin/mise" "$lifecycle_mock_bin"/*

: > "$lifecycle_log"
darwin_native_state="$lifecycle_home/state & custom"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester OS=Darwin DOTFILES_DIR="$repo_dir" XDG_STATE_HOME="$darwin_native_state" \
	XDG_CONFIG_HOME="$lifecycle_home/.config" REAL_PYTHON="$real_python" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; setup_process_compose'
darwin_generated_plist="$darwin_native_state/process-compose/native/io.sarendipitee.process-compose.plist"
assert_mode 600 "$darwin_generated_plist"
if command -v plutil >/dev/null 2>&1; then
	plutil -lint "$darwin_generated_plist" >/dev/null || fail 'Generated LaunchAgent plist is invalid'
fi
darwin_enable_line=$(grep -nFx 'launchctl enable gui/501/io.sarendipitee.process-compose' "$lifecycle_log" |
	cut -d: -f1 || true)
darwin_bootstrap_line=$(grep -nFx \
	"launchctl bootstrap gui/501 $darwin_generated_plist" \
	"$lifecycle_log" | cut -d: -f1 || true)
[ -n "$darwin_enable_line" ] || fail 'macOS lifecycle did not enable exact Process Compose label'
[ -n "$darwin_bootstrap_line" ] || fail 'macOS lifecycle did not bootstrap Process Compose LaunchAgent'
[ "$darwin_enable_line" -lt "$darwin_bootstrap_line" ] ||
	fail 'macOS lifecycle bootstrap preceded launchctl enable'
"$real_python" - "$darwin_generated_plist" "$darwin_native_state" <<'PY' ||
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    service = plistlib.load(source)
raise SystemExit(service.get("EnvironmentVariables", {}).get("XDG_STATE_HOME") != sys.argv[2])
PY
	fail 'Generated LaunchAgent did not preserve custom XDG_STATE_HOME safely'

: > "$lifecycle_log"
linux_injection_marker="$tmp_dir/SHOULD_NOT_EXIST"
linux_native_state="$lifecycle_home/state % \"quoted\" \$(touch $linux_injection_marker)"
legacy_codex_unit="$lifecycle_home/.config/systemd/user/codex-remote-control.service"
hindsight_container_state="$tmp_dir/hindsight-container.state"
mkdir -p "$(dirname "$legacy_codex_unit")"
chmod 0775 \
	"$lifecycle_home/.config" \
	"$lifecycle_home/.config/systemd" \
	"$lifecycle_home/.config/systemd/user"
cat > "$legacy_codex_unit" <<'EOF'
[Unit]
Description=Legacy Codex remote control

[Service]
Environment=OMNIROUTER_API_KEY=legacy-inline-secret-value
Environment=UNRELATED=value
ExecStart=%h/.local/bin/codex remote-control
EOF
chmod 0664 "$legacy_codex_unit"
printf '%s\n' true > "$hindsight_container_state"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester OS=Linux XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$linux_native_state" DOTFILES_DIR="$repo_dir" REAL_PYTHON="$real_python" \
	MOCK_LEGACY_UNITS=present MOCK_CODEX_UNIT="$legacy_codex_unit" \
	MOCK_HINDSIGHT_STATE="$hindsight_container_state" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; setup_process_compose'
linux_native_dropin="$lifecycle_home/.config/systemd/user/dotfiles-process-compose.service.d/10-xdg-state.conf"
assert_mode 600 "$linux_native_dropin"
escaped_linux_state=${linux_native_state//\\/\\\\}
escaped_linux_state=${escaped_linux_state//\"/\\\"}
escaped_linux_state=${escaped_linux_state//%/%%}
grep -Fxq "Environment=\"XDG_STATE_HOME=$escaped_linux_state\"" "$linux_native_dropin" ||
	fail 'Generated systemd environment did not escape custom XDG_STATE_HOME safely'
[ ! -e "$linux_injection_marker" ] || fail 'Custom XDG_STATE_HOME triggered parent-shell injection'
assert_mode 755 "$lifecycle_home/.config"
assert_mode 755 "$lifecycle_home/.config/systemd"
assert_mode 755 "$lifecycle_home/.config/systemd/user"
assert_mode 600 "$legacy_codex_unit"
grep -Fxq 'EnvironmentFile=%h/.config/hindsight/hindsight.env' "$legacy_codex_unit" ||
	fail 'Legacy Codex unit rollback environment file missing'
grep -Fq 'Environment=UNRELATED=value' "$legacy_codex_unit" ||
	fail 'Legacy Codex unit sanitizer removed unrelated environment'
grep -Fq 'OMNIROUTER_API_KEY=legacy-inline-secret-value' "$legacy_codex_unit" &&
	fail 'Legacy Codex unit retained inline OmniRouter key'
grep -Fq 'legacy-inline-secret-value' "$lifecycle_log" &&
	fail 'Legacy Codex unit migration printed inline secret'
[ ! -e "$hindsight_container_state" ] || fail 'Stale Hindsight container was not removed'
linger_line=$(grep -nFx 'sudo loginctl enable-linger tester' "$lifecycle_log" | cut -d: -f1 || true)
selector_check_line=$(grep -nFx 'launcher --check' "$lifecycle_log" | cut -d: -f1 || true)
systemd_enable_line=$(grep -nFx \
	'systemctl --user enable dotfiles-process-compose.service' "$lifecycle_log" | cut -d: -f1 || true)
systemd_restart_line=$(grep -nFx \
	'systemctl --user restart dotfiles-process-compose.service' "$lifecycle_log" | cut -d: -f1 || true)
codex_stop_line=$(grep -nFx 'mise codex remote-control --json stop' "$lifecycle_log" | cut -d: -f1 || true)
hindsight_stop_line=$(grep -nFx 'sudo docker stop -t 30 hindsight' "$lifecycle_log" | cut -d: -f1 || true)
hindsight_rm_line=$(grep -nFx 'sudo docker rm hindsight' "$lifecycle_log" | cut -d: -f1 || true)
[ -n "$linger_line" ] || fail 'Linux lifecycle did not enable login linger'
[ -n "$selector_check_line" ] || fail 'Linux lifecycle did not validate Process Compose selector'
[ -n "$systemd_enable_line" ] || fail 'Linux lifecycle did not enable Process Compose user service'
[ -n "$systemd_restart_line" ] || fail 'Linux lifecycle did not restart Process Compose user service'
[ -n "$codex_stop_line" ] || fail 'Linux lifecycle did not stop detached Codex remote-control daemon'
[ -n "$hindsight_stop_line" ] || fail 'Linux lifecycle did not stop stale Hindsight container'
[ -n "$hindsight_rm_line" ] || fail 'Linux lifecycle did not remove stale Hindsight container'
[ "$linger_line" -lt "$systemd_enable_line" ] ||
	fail 'Linux systemctl user enable preceded loginctl enable-linger'
[ "$selector_check_line" -lt "$systemd_enable_line" ] ||
	fail 'Linux systemctl user enable preceded selector validation'
[ "$systemd_enable_line" -lt "$systemd_restart_line" ] ||
	fail 'Linux Process Compose restart preceded systemctl enable'
[ "$codex_stop_line" -lt "$systemd_restart_line" ] ||
	fail 'Linux Process Compose restart preceded Codex daemon migration'
[ "$hindsight_stop_line" -lt "$hindsight_rm_line" ] && [ "$hindsight_rm_line" -lt "$systemd_restart_line" ] ||
	fail 'Linux Hindsight container ownership transfer order is invalid'
for legacy_unit in \
	codex-remote-control.service \
	codex-remote.service \
	hindsight.service \
	homebrew.et.service \
	omniroute.service; do
	legacy_disable_line=$(grep -nFx \
		"systemctl --user disable --now $legacy_unit" "$lifecycle_log" | cut -d: -f1 || true)
	[ -n "$legacy_disable_line" ] || fail "Linux lifecycle did not migrate $legacy_unit"
	[ "$legacy_disable_line" -lt "$systemd_restart_line" ] ||
		fail "Linux Process Compose restart preceded migration of $legacy_unit"
done

stopped_container_log="$tmp_dir/stopped-container.log"
printf '%s\n' false > "$hindsight_container_state"
: > "$stopped_container_log"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$stopped_container_log" \
	MOCK_HINDSIGHT_STATE="$hindsight_container_state" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; remove_stale_hindsight_container' ||
	fail 'Stopped Hindsight container cleanup failed'
[ ! -e "$hindsight_container_state" ] || fail 'Stopped Hindsight container was not removed'
grep -Fxq 'sudo docker rm hindsight' "$stopped_container_log" ||
	fail 'Stopped Hindsight container cleanup omitted remove'
grep -Fq 'sudo docker stop' "$stopped_container_log" &&
	fail 'Stopped Hindsight container cleanup issued unnecessary stop'

: > "$lifecycle_log"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester OS=Linux XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$linux_native_state" DOTFILES_DIR="$repo_dir" REAL_PYTHON="$real_python" \
	MOCK_LEGACY_UNITS=absent MOCK_CODEX_UNIT="$legacy_codex_unit" \
	MOCK_HINDSIGHT_STATE="$hindsight_container_state" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; setup_process_compose'
for legacy_unit in \
	codex-remote-control.service \
	codex-remote.service \
	hindsight.service \
	homebrew.et.service \
	omniroute.service; do
	grep -Fxq "systemctl --user disable --now $legacy_unit" "$lifecycle_log" &&
		fail "Linux lifecycle tried to disable absent $legacy_unit"
done
grep -Fxq 'mise codex remote-control --json stop' "$lifecycle_log" ||
	fail 'Linux lifecycle did not accept detached Codex not-running status'
[ "$(grep -Fxc 'EnvironmentFile=%h/.config/hindsight/hindsight.env' "$legacy_codex_unit")" -eq 1 ] ||
	fail 'Legacy Codex unit sanitizer is not idempotent'

rm "$legacy_codex_unit"
legacy_codex_outside="$tmp_dir/legacy-codex-outside.service"
printf '%s\n' '[Service]' 'Environment=OMNIROUTER_API_KEY=symlink-secret-value' > "$legacy_codex_outside"
chmod 0644 "$legacy_codex_outside"
ln -s "$legacy_codex_outside" "$legacy_codex_unit"
if HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester XDG_CONFIG_HOME="$lifecycle_home/.config" REAL_PYTHON="$real_python" \
	MOCK_LEGACY_UNITS=absent MOCK_CODEX_UNIT="$legacy_codex_unit" \
	MOCK_HINDSIGHT_STATE="$hindsight_container_state" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; sanitize_legacy_codex_remote_control_unit' \
	>"$tmp_dir/legacy-codex-symlink.out" 2>&1; then
	fail 'Legacy Codex unit sanitizer accepted symlink'
fi
grep -Fq 'symlink-secret-value' "$tmp_dir/legacy-codex-symlink.out" &&
	fail 'Legacy Codex unit symlink rejection printed secret'
assert_mode 644 "$legacy_codex_outside"

rm "$legacy_codex_unit"
legacy_codex_symlink_home="$tmp_dir/legacy-codex-symlink-home"
legacy_codex_symlink_target="$tmp_dir/legacy-codex-symlink-target"
mkdir -p "$legacy_codex_symlink_home" "$legacy_codex_symlink_target/systemd/user"
legacy_codex_ancestor_unit="$legacy_codex_symlink_target/systemd/user/codex-remote-control.service"
printf '%s\n' '[Service]' 'Environment=OMNIROUTER_API_KEY=ancestor-symlink-secret-value' > \
	"$legacy_codex_ancestor_unit"
chmod 0644 "$legacy_codex_ancestor_unit"
ln -s "$legacy_codex_symlink_target" "$legacy_codex_symlink_home/.config"
if HOME="$legacy_codex_symlink_home" PATH="$lifecycle_mock_bin:$PATH" \
	LIFECYCLE_LOG="$lifecycle_log" LOGIN_USER=tester \
	XDG_CONFIG_HOME="$legacy_codex_symlink_home/.config" REAL_PYTHON="$real_python" \
	MOCK_LEGACY_UNITS=absent MOCK_CODEX_UNIT="$legacy_codex_ancestor_unit" \
	MOCK_HINDSIGHT_STATE="$hindsight_container_state" \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; sanitize_legacy_codex_remote_control_unit' \
	>"$tmp_dir/legacy-codex-ancestor-symlink.out" 2>&1; then
	fail 'Legacy Codex unit sanitizer accepted symlinked ancestor'
fi
grep -Fq 'ancestor-symlink-secret-value' "$tmp_dir/legacy-codex-ancestor-symlink.out" &&
	fail 'Legacy Codex unit ancestor symlink rejection printed secret'
assert_mode 644 "$legacy_codex_ancestor_unit"
grep -Fq 'OMNIROUTER_API_KEY=ancestor-symlink-secret-value' "$legacy_codex_ancestor_unit" ||
	fail 'Legacy Codex unit ancestor symlink rejection mutated target'

readiness_state=$(mktemp -d /tmp/dotfiles-readiness.XXXXXX)
readiness_socket="$readiness_state/process-compose/run/pc.sock"
mkdir -p "$(dirname "$readiness_socket")"
"$real_python" - "$readiness_socket" <<'PY'
import socket
import sys

listener = socket.socket(socket.AF_UNIX)
listener.bind(sys.argv[1])
listener.close()
PY
: > "$lifecycle_log"
HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester DOTFILES_HOST=aorus XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$readiness_state" XDG_RUNTIME_DIR='' REAL_JQ="$real_jq" \
	MOCK_PROCESS_READY=true MOCK_HINDSIGHT_HEALTH=true \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; verify_aorus_process_compose' ||
	fail 'Aorus replacement readiness verification rejected healthy processes'
grep -Fxq 'curl -fsS --max-time 5 http://127.0.0.1:18888/health' "$lifecycle_log" ||
	fail 'Aorus replacement verification omitted Hindsight HTTP health'

if HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester DOTFILES_HOST=aorus XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$readiness_state" XDG_RUNTIME_DIR='' REAL_JQ="$real_jq" \
	MOCK_PROCESS_READY=false MOCK_HINDSIGHT_HEALTH=true \
	PROCESS_COMPOSE_READY_TIMEOUT_SECONDS=1 PROCESS_COMPOSE_READY_INTERVAL_SECONDS=1 \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; verify_aorus_process_compose' \
	>"$tmp_dir/readiness-failure.out" 2>&1; then
	fail 'Aorus replacement readiness verification accepted stopped process'
fi
grep -q 'did not become ready' "$tmp_dir/readiness-failure.out" ||
	fail 'Aorus replacement readiness failure was unclear'

if HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester DOTFILES_HOST=aorus XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$readiness_state" XDG_RUNTIME_DIR='' REAL_JQ="$real_jq" \
	MOCK_PROCESS_READY=true MOCK_PROCESS_HANG=true MOCK_HINDSIGHT_HEALTH=true \
	PROCESS_COMPOSE_READY_TIMEOUT_SECONDS=1 PROCESS_COMPOSE_READY_INTERVAL_SECONDS=1 \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; verify_aorus_process_compose' \
	>"$tmp_dir/readiness-hanging-client.out" 2>&1; then
	fail 'Aorus replacement readiness hung or accepted wedged Process Compose client'
fi
grep -q 'did not become ready' "$tmp_dir/readiness-hanging-client.out" ||
	fail 'Wedged Process Compose readiness failure was unclear'

: > "$lifecycle_log"
if HOME="$lifecycle_home" PATH="$lifecycle_mock_bin:$PATH" LIFECYCLE_LOG="$lifecycle_log" \
	LOGIN_USER=tester DOTFILES_HOST=aorus XDG_CONFIG_HOME="$lifecycle_home/.config" \
	XDG_STATE_HOME="$readiness_state" XDG_RUNTIME_DIR='' REAL_JQ="$real_jq" \
	MOCK_PROCESS_READY=true MOCK_CURL_HANG=true MOCK_HINDSIGHT_HEALTH=true \
	PROCESS_COMPOSE_READY_TIMEOUT_SECONDS=4 PROCESS_COMPOSE_READY_INTERVAL_SECONDS=1 \
	SETUP_PROCESS_COMPOSE_FUNCTION="$setup_process_compose_function" \
	bash -c 'fatal() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; eval "$SETUP_PROCESS_COMPOSE_FUNCTION"; verify_aorus_process_compose' \
	>"$tmp_dir/readiness-slow-http.out" 2>&1; then
	fail 'Aorus replacement readiness accepted slow Hindsight health probe'
fi
grep -Eq '^curl -fsS --max-time [1-4] http://127[.]0[.]0[.]1:18888/health$' "$lifecycle_log" ||
	fail 'Aorus readiness did not clamp HTTP timeout to absolute deadline'
rm -rf "$readiness_state"

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
