#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

source "${DOTFILES_DIR}/packages/shell/.config/zsh/colors.sh"
source "${DOTFILES_DIR}/packages/shell/.config/zsh/functions.sh"
source "${DOTFILES_DIR}/packages/shell/.config/zsh/env.sh"

run_privileged() {
	if [[ "$(id -u)" == "0" ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

keep_sudo_alive() {
	if [[ "$(id -u)" == "0" ]]; then
		return
	fi

	section_header 'Keeping sudo alive till this script has finished'
	sudo -v
	while true; do
		sudo -n true
		sleep 60
		kill -0 "$$" || exit
	done 2>/dev/null &
}

write_user_file() {
	local target_path="${1}"
	local file_mode="${2}"
	local tmp_file
	tmp_file="$(mktemp)"
	cat > "${tmp_file}"

	if [[ "$(id -u)" == "0" ]]; then
		install -D -m "${file_mode}" -o "${VLLM_OWNER}" -g "${VLLM_OWNER_GROUP}" "${tmp_file}" "${target_path}"
	else
		install -D -m "${file_mode}" "${tmp_file}" "${target_path}"
	fi

	rm -f "${tmp_file}"
}

write_user_file_if_missing() {
	local target_path="${1}"
	local file_mode="${2}"

	if [[ -e "${target_path}" ]]; then
		warn "skipping existing user-managed file '${target_path}'"
		cat >/dev/null
		return
	fi

	write_user_file "${target_path}" "${file_mode}"
}

ensure_user_env_key() {
	local target_path="${1}"
	local key_name="${2}"
	local key_value="${3}"

	if rg -q "^${key_name}=" "${target_path}" 2>/dev/null; then
		return
	fi

	if [[ "$(id -u)" == "0" ]]; then
		printf '%s=%s\n' "${key_name}" "${key_value}" >> "${target_path}"
		chown "${VLLM_OWNER}:${VLLM_OWNER_GROUP}" "${target_path}"
	else
		printf '%s=%s\n' "${key_name}" "${key_value}" >> "${target_path}"
	fi
}

write_root_file() {
	local target_path="${1}"
	local file_mode="${2}"
	local tmp_file
	tmp_file="$(mktemp)"
	cat > "${tmp_file}"
	run_privileged install -D -m "${file_mode}" "${tmp_file}" "${target_path}"
	rm -f "${tmp_file}"
}

require_linux() {
	[[ "$(uname)" == "Linux" ]] || error "setup-vllm.sh only supports Linux"
}

require_command() {
	command_exists "${1}" || error "required command missing: ${1}"
}

ensure_dir_with_owner() {
	local target_path="${1}"
	local target_mode="${2}"
	local target_owner="${3}"
	local target_group="${4}"
	run_privileged install -d -m "${target_mode}" -o "${target_owner}" -g "${target_group}" "${target_path}"
}

require_linux
require_command systemctl
require_command docker
require_command curl

if [[ "$(id -u)" == "0" ]]; then
	if [[ -n "${SUDO_USER:-}" ]]; then
		VLLM_OWNER="${SUDO_USER}"
	else
		[[ -n "${VLLM_OWNER:-}" ]] || error "run as normal user or set VLLM_OWNER when running as root"
	fi
else
	VLLM_OWNER="$(id -un)"
fi

VLLM_OWNER_HOME="$(getent passwd "${VLLM_OWNER}" | cut -d: -f6)"
VLLM_OWNER_GROUP="$(id -gn "${VLLM_OWNER}")"
[[ -n "${VLLM_OWNER_HOME}" ]] || error "failed to resolve home for '${VLLM_OWNER}'"

keep_sudo_alive

CONTROL_DIR="${VLLM_OWNER_HOME}/.config/vllm"
MODELS_DIR="${CONTROL_DIR}/models.d"
CURRENT_LINK="${CONTROL_DIR}/current"
RUNTIME_ENV="${CONTROL_DIR}/runtime.env"
LOCAL_BIN_DIR="${VLLM_OWNER_HOME}/.local/bin"

SYSTEM_LIBEXEC_DIR="/usr/local/libexec/vllm"
SYSTEM_DAEMON="${SYSTEM_LIBEXEC_DIR}/vllm-docker-daemon"
SYSTEM_ADMIN="${SYSTEM_LIBEXEC_DIR}/vllm-admin"
SYSTEMD_UNIT="/etc/systemd/system/vllm.service"
SUDOERS_FILE="/etc/sudoers.d/vllm-model-${VLLM_OWNER}"

SHARED_ROOT="/var/lib/vllm"
SHARED_CONFIG_DIR="${SHARED_ROOT}/config"
SHARED_STATE_DIR="${SHARED_ROOT}/state"
SERVICE_ACTIVE_ENV="${SHARED_CONFIG_DIR}/active.env"
HF_CACHE_DIR="/var/cache/vllm/huggingface"

DOCKER_BIN="$(command -v docker)"

section_header 'Verifying docker service'
run_privileged systemctl enable --now docker.service >/dev/null

section_header 'Creating user control directories'
ensure_dir_exists "${CONTROL_DIR}"
ensure_dir_exists "${MODELS_DIR}"
ensure_dir_exists "${LOCAL_BIN_DIR}"

section_header 'Writing vLLM control defaults'
write_user_file_if_missing "${RUNTIME_ENV}" 0644 <<EOF
VLLM_IMAGE=vllm/vllm-openai:v0.20.2
VLLM_CONTAINER_NAME=vllm
VLLM_HOST=127.0.0.1
VLLM_PORT=8080
VLLM_SHM_SIZE=24g
VLLM_DOCKER_GPUS=all
VLLM_DOCKER_EXTRA_ARGS='--ipc=host'
HF_HOME=${HF_CACHE_DIR}
VLLM_STATE_DIR=${SHARED_STATE_DIR}
EOF
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_IMAGE" "vllm/vllm-openai:v0.20.2"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_CONTAINER_NAME" "vllm"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_HOST" "127.0.0.1"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_PORT" "8080"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_SHM_SIZE" "24g"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_DOCKER_GPUS" "all"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_DOCKER_EXTRA_ARGS" "'--ipc=host'"
ensure_user_env_key "${RUNTIME_ENV}" "HF_HOME" "${HF_CACHE_DIR}"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_STATE_DIR" "${SHARED_STATE_DIR}"

write_user_file_if_missing "${MODELS_DIR}/qwen3-27b-awq.env" 0644 <<'EOF'
MODEL_ID=QuantTrio/Qwen3.6-27B-AWQ
MODEL_ALIAS=qwen3-27b-awq
VLLM_MAX_MODEL_LEN=15360
VLLM_GPU_MEMORY_UTILIZATION=0.98
VLLM_MAX_NUM_SEQS=1
VLLM_MODEL_ARGS='--enable-auto-tool-choice --tool-call-parser qwen3_xml --reasoning-parser qwen3 --generation-config vllm'
EOF

write_user_file_if_missing "${MODELS_DIR}/gemma4.env" 0644 <<'EOF'
MODEL_ID=google/gemma-4-E4B-it
MODEL_ALIAS=gemma4
VLLM_MAX_MODEL_LEN=131072
VLLM_GPU_MEMORY_UTILIZATION=0.88
VLLM_MAX_NUM_SEQS=8
VLLM_MODEL_ARGS='--enable-auto-tool-choice --tool-call-parser gemma4 --generation-config vllm'
EOF

write_user_file_if_missing "${MODELS_DIR}/step3-vl.env" 0644 <<'EOF'
MODEL_ID=stepfun-ai/Step3-VL-10B
MODEL_ALIAS=step3-vl
VLLM_MAX_MODEL_LEN=4096
VLLM_GPU_MEMORY_UTILIZATION=0.95
VLLM_MAX_NUM_SEQS=4
VLLM_TRUST_REMOTE_CODE=1
VLLM_MODEL_ARGS='--reasoning-parser deepseek_r1'
EOF

write_user_file_if_missing "${MODELS_DIR}/smollm2-1.7b.env" 0644 <<'EOF'
MODEL_ID=HuggingFaceTB/SmolLM2-1.7B-Instruct
MODEL_ALIAS=smollm2-1.7b
VLLM_MAX_MODEL_LEN=8192
VLLM_GPU_MEMORY_UTILIZATION=0.55
VLLM_MAX_NUM_SEQS=4
VLLM_MODEL_ARGS=''
EOF

if [[ ! -L "${CURRENT_LINK}" && ! -e "${CURRENT_LINK}" ]]; then
	ln -s "${MODELS_DIR}/qwen3-27b-awq.env" "${CURRENT_LINK}"
	if [[ "$(id -u)" == "0" ]]; then
		chown -h "${VLLM_OWNER}:${VLLM_OWNER_GROUP}" "${CURRENT_LINK}"
	fi
	success "created default active model symlink '${CURRENT_LINK}'"
else
	warn "skipping existing active model pointer '${CURRENT_LINK}'"
fi

section_header 'Creating shared vLLM directories'
ensure_dir_with_owner "${SYSTEM_LIBEXEC_DIR}" 0755 root root
ensure_dir_with_owner "${SHARED_ROOT}" 0755 root root
ensure_dir_with_owner "${SHARED_CONFIG_DIR}" 0755 root root
ensure_dir_with_owner "${SHARED_STATE_DIR}" 0755 root root
ensure_dir_with_owner "${HF_CACHE_DIR}" 0755 root root

section_header 'Installing vLLM docker daemon wrapper'
write_root_file "${SYSTEM_DAEMON}" 0755 <<EOF
#!/usr/bin/env bash

set -euo pipefail

ACTIVE_ENV="${SERVICE_ACTIVE_ENV}"
DOCKER_BIN="${DOCKER_BIN}"

[[ -f "\${ACTIVE_ENV}" ]] || { echo "missing active env: \${ACTIVE_ENV}" >&2; exit 1; }

set -a
source "\${ACTIVE_ENV}"
set +a

: "\${VLLM_IMAGE:?VLLM_IMAGE required}"
: "\${VLLM_CONTAINER_NAME:?VLLM_CONTAINER_NAME required}"
: "\${VLLM_HOST:?VLLM_HOST required}"
: "\${VLLM_PORT:?VLLM_PORT required}"
: "\${VLLM_SHM_SIZE:?VLLM_SHM_SIZE required}"
: "\${VLLM_DOCKER_GPUS:?VLLM_DOCKER_GPUS required}"
: "\${HF_HOME:?HF_HOME required}"
: "\${VLLM_STATE_DIR:?VLLM_STATE_DIR required}"
: "\${MODEL_ID:?MODEL_ID required}"
: "\${VLLM_MAX_MODEL_LEN:?VLLM_MAX_MODEL_LEN required}"
: "\${VLLM_GPU_MEMORY_UTILIZATION:?VLLM_GPU_MEMORY_UTILIZATION required}"
: "\${VLLM_MAX_NUM_SEQS:?VLLM_MAX_NUM_SEQS required}"

"\${DOCKER_BIN}" rm -f "\${VLLM_CONTAINER_NAME}" >/dev/null 2>&1 || true

cmd=(
	"\${DOCKER_BIN}" run
	--name "\${VLLM_CONTAINER_NAME}"
	--rm
	--gpus "\${VLLM_DOCKER_GPUS}"
	-v "\${HF_HOME}:/root/.cache/huggingface"
	-v "\${VLLM_STATE_DIR}:/var/lib/vllm/state"
	-p "\${VLLM_HOST}:\${VLLM_PORT}:8080"
	--shm-size "\${VLLM_SHM_SIZE}"
)

if [[ -n "\${VLLM_DOCKER_EXTRA_ARGS:-}" ]]; then
	# shellcheck disable=SC2206
	extra_docker_args=(\${VLLM_DOCKER_EXTRA_ARGS})
	cmd+=("\${extra_docker_args[@]}")
fi

cmd+=(
	"\${VLLM_IMAGE}"
	"\${MODEL_ID}"
	--port 8080
	--max-model-len "\${VLLM_MAX_MODEL_LEN}"
	--gpu-memory-utilization "\${VLLM_GPU_MEMORY_UTILIZATION}"
	--max-num-seqs "\${VLLM_MAX_NUM_SEQS}"
)

if [[ "\${VLLM_TRUST_REMOTE_CODE:-0}" == "1" ]]; then
	cmd+=(--trust-remote-code)
fi

if [[ -n "\${VLLM_MODEL_ARGS:-}" ]]; then
	# shellcheck disable=SC2206
	model_args=(\${VLLM_MODEL_ARGS})
	cmd+=("\${model_args[@]}")
fi

exec "\${cmd[@]}"
EOF

section_header 'Installing vLLM admin helper'
write_root_file "${SYSTEM_ADMIN}" 0755 <<EOF
#!/usr/bin/env bash

set -euo pipefail

MODELS_DIR="${MODELS_DIR}"
CURRENT_LINK="${CURRENT_LINK}"
RUNTIME_ENV="${RUNTIME_ENV}"
SERVICE_ACTIVE_ENV="${SERVICE_ACTIVE_ENV}"
DOCKER_BIN="${DOCKER_BIN}"
SERVICE_NAME="vllm.service"

die() {
	echo "\$*" >&2
	exit 1
}

require_root() {
	[[ "\$(id -u)" == "0" ]] || die "must run as root"
}

resolve_profile_path() {
	[[ -L "\${CURRENT_LINK}" || -f "\${CURRENT_LINK}" ]] || die "missing current model pointer: \${CURRENT_LINK}"

	if [[ -L "\${CURRENT_LINK}" ]]; then
		readlink -f "\${CURRENT_LINK}"
		return
	fi

	if grep -q '^MODEL_ID=' "\${CURRENT_LINK}" 2>/dev/null; then
		printf '%s\n' "\${CURRENT_LINK}"
		return
	fi

	local pointer_value
	pointer_value="\$(head -n 1 "\${CURRENT_LINK}" | tr -d '[:space:]')"
	[[ -n "\${pointer_value}" ]] || die "empty current model pointer: \${CURRENT_LINK}"

	if [[ -f "\${MODELS_DIR}/\${pointer_value}.env" ]]; then
		printf '%s\n' "\${MODELS_DIR}/\${pointer_value}.env"
		return
	fi

	[[ -f "\${pointer_value}" ]] || die "unable to resolve current model pointer '\${pointer_value}'"
	printf '%s\n' "\${pointer_value}"
}

load_env_file() {
	local env_path="\${1}"
	[[ -f "\${env_path}" ]] || die "missing env file: \${env_path}"
	set -a
	source "\${env_path}"
	set +a
}

quote_env() {
	local name="\${1}"
	local value="\${2:-}"
	printf '%s=%q\n' "\${name}" "\${value}"
}

render_active_env() {
	require_root

	local profile_path
	profile_path="\$(resolve_profile_path)"
	[[ -f "\${profile_path}" ]] || die "missing active profile: \${profile_path}"

	unset VLLM_IMAGE VLLM_CONTAINER_NAME VLLM_HOST VLLM_PORT VLLM_SHM_SIZE VLLM_DOCKER_GPUS
	unset VLLM_DOCKER_EXTRA_ARGS HF_HOME VLLM_STATE_DIR
	unset MODEL_ID MODEL_ALIAS VLLM_MAX_MODEL_LEN VLLM_GPU_MEMORY_UTILIZATION VLLM_MAX_NUM_SEQS
	unset VLLM_MODEL_ARGS VLLM_EXTRA_ARGS VLLM_TRUST_REMOTE_CODE

	load_env_file "\${RUNTIME_ENV}"
	load_env_file "\${profile_path}"

	: "\${VLLM_IMAGE:?VLLM_IMAGE required}"
	: "\${VLLM_CONTAINER_NAME:?VLLM_CONTAINER_NAME required}"
	: "\${VLLM_HOST:?VLLM_HOST required}"
	: "\${VLLM_PORT:?VLLM_PORT required}"
	: "\${VLLM_SHM_SIZE:?VLLM_SHM_SIZE required}"
	: "\${VLLM_DOCKER_GPUS:?VLLM_DOCKER_GPUS required}"
	: "\${HF_HOME:?HF_HOME required}"
	: "\${VLLM_STATE_DIR:?VLLM_STATE_DIR required}"
	: "\${MODEL_ID:?MODEL_ID required}"
	: "\${MODEL_ALIAS:?MODEL_ALIAS required}"
	: "\${VLLM_MAX_MODEL_LEN:?VLLM_MAX_MODEL_LEN required}"
	: "\${VLLM_GPU_MEMORY_UTILIZATION:?VLLM_GPU_MEMORY_UTILIZATION required}"
	: "\${VLLM_MAX_NUM_SEQS:?VLLM_MAX_NUM_SEQS required}"

	if [[ -z "\${VLLM_MODEL_ARGS:-}" && -n "\${VLLM_EXTRA_ARGS:-}" ]]; then
		VLLM_MODEL_ARGS="\${VLLM_EXTRA_ARGS}"
	fi

	install -d -m 0755 "\${HF_HOME}" "\${VLLM_STATE_DIR}" "\$(dirname "\${SERVICE_ACTIVE_ENV}")"

	local tmp_file
	tmp_file="\$(mktemp)"
	{
		echo "# Generated by \${0} on \$(date -Iseconds)"
		quote_env VLLM_IMAGE "\${VLLM_IMAGE}"
		quote_env VLLM_CONTAINER_NAME "\${VLLM_CONTAINER_NAME}"
		quote_env VLLM_HOST "\${VLLM_HOST}"
		quote_env VLLM_PORT "\${VLLM_PORT}"
		quote_env VLLM_SHM_SIZE "\${VLLM_SHM_SIZE}"
		quote_env VLLM_DOCKER_GPUS "\${VLLM_DOCKER_GPUS}"
		quote_env VLLM_DOCKER_EXTRA_ARGS "\${VLLM_DOCKER_EXTRA_ARGS:-}"
		quote_env HF_HOME "\${HF_HOME}"
		quote_env VLLM_STATE_DIR "\${VLLM_STATE_DIR}"
		quote_env MODEL_ID "\${MODEL_ID}"
		quote_env MODEL_ALIAS "\${MODEL_ALIAS}"
		quote_env VLLM_MAX_MODEL_LEN "\${VLLM_MAX_MODEL_LEN}"
		quote_env VLLM_GPU_MEMORY_UTILIZATION "\${VLLM_GPU_MEMORY_UTILIZATION}"
		quote_env VLLM_MAX_NUM_SEQS "\${VLLM_MAX_NUM_SEQS}"
		quote_env VLLM_MODEL_ARGS "\${VLLM_MODEL_ARGS:-}"
		quote_env VLLM_TRUST_REMOTE_CODE "\${VLLM_TRUST_REMOTE_CODE:-0}"
	} > "\${tmp_file}"

	install -m 0644 "\${tmp_file}" "\${SERVICE_ACTIVE_ENV}"
	rm -f "\${tmp_file}"
}

pull_image() {
	require_root
	unset VLLM_IMAGE
	load_env_file "\${RUNTIME_ENV}"
	: "\${VLLM_IMAGE:?VLLM_IMAGE required}"
	"\${DOCKER_BIN}" pull "\${VLLM_IMAGE}"
}

download_model() {
	require_root
	local alias_name="\${1:-}"
	[[ -n "\${alias_name}" ]] || die "usage: \$0 download-model <alias>"

	local profile_path="\${MODELS_DIR}/\${alias_name}.env"
	[[ -f "\${profile_path}" ]] || die "unknown model alias: \${alias_name}"

	unset VLLM_IMAGE HF_HOME MODEL_ID
	load_env_file "\${RUNTIME_ENV}"
	load_env_file "\${profile_path}"

	: "\${VLLM_IMAGE:?VLLM_IMAGE required}"
	: "\${HF_HOME:?HF_HOME required}"
	: "\${MODEL_ID:?MODEL_ID required}"

	install -d -m 0755 "\${HF_HOME}"
	"\${DOCKER_BIN}" pull "\${VLLM_IMAGE}" >/dev/null
	"\${DOCKER_BIN}" run --rm \
		-v "\${HF_HOME}:/root/.cache/huggingface" \
		--entrypoint python3 \
		"\${VLLM_IMAGE}" \
		-c 'from huggingface_hub import snapshot_download; import sys; snapshot_download(repo_id=sys.argv[1]); print(sys.argv[1])' \
		"\${MODEL_ID}"
}

cmd="\${1:-}"
case "\${cmd}" in
	apply-active)
		render_active_env
		;;
	pull-image)
		pull_image
		;;
	restart-service)
		systemctl restart "\${SERVICE_NAME}"
		;;
	start-service)
		systemctl start "\${SERVICE_NAME}"
		;;
	stop-service)
		systemctl stop "\${SERVICE_NAME}"
		;;
	status)
		systemctl --no-pager --full status "\${SERVICE_NAME}"
		;;
	logs)
		journalctl -u "\${SERVICE_NAME}" -f
		;;
	download-model)
		download_model "\${2:-}"
		;;
	*)
		die "usage: \$0 {apply-active|pull-image|restart-service|start-service|stop-service|status|logs|download-model <alias>}"
		;;
esac
EOF

section_header 'Installing user vLLM control CLI'
write_user_file "${LOCAL_BIN_DIR}/vllm-model" 0755 <<EOF
#!/usr/bin/env bash

set -euo pipefail

MODELS_DIR="${MODELS_DIR}"
CURRENT_LINK="${CURRENT_LINK}"
VLLM_ADMIN="${SYSTEM_ADMIN}"
HEALTH_URL="http://127.0.0.1:8080/v1/models"

die() {
	echo "\$*" >&2
	exit 1
}

usage() {
	cat <<'USAGE'
usage:
  vllm-model list
  vllm-model current
  vllm-model use <alias>
  vllm-model add <alias> <model_id>
  vllm-model edit <alias>
  vllm-model rm <alias>
  vllm-model download <alias>
  vllm-model start
  vllm-model stop
  vllm-model restart
  vllm-model status
  vllm-model logs
USAGE
}

profile_path() {
	echo "\${MODELS_DIR}/\${1}.env"
}

resolve_profile_path() {
	if [[ -L "\${CURRENT_LINK}" ]]; then
		readlink -f "\${CURRENT_LINK}"
		return
	fi

	[[ -f "\${CURRENT_LINK}" ]] || return 0

	if grep -q '^MODEL_ID=' "\${CURRENT_LINK}" 2>/dev/null; then
		printf '%s\n' "\${CURRENT_LINK}"
		return
	fi

	local pointer_value
	pointer_value="\$(head -n 1 "\${CURRENT_LINK}" | tr -d '[:space:]')"
	[[ -n "\${pointer_value}" ]] || return 0

	if [[ -f "\$(profile_path "\${pointer_value}")" ]]; then
		profile_path "\${pointer_value}"
		return
	fi

	[[ -f "\${pointer_value}" ]] && printf '%s\n' "\${pointer_value}"
}

current_alias() {
	local resolved_path
	resolved_path="\$(resolve_profile_path || true)"
	[[ -n "\${resolved_path}" && -f "\${resolved_path}" ]] || return 0

	local model_alias
	model_alias="\$(sed -n 's/^MODEL_ALIAS=//p' "\${resolved_path}" | head -n 1)"
	if [[ -n "\${model_alias}" ]]; then
		printf '%s\n' "\${model_alias}"
		return
	fi

	basename "\${resolved_path}" .env
}

ensure_alias_exists() {
	local alias_name="\${1}"
	[[ -f "\$(profile_path "\${alias_name}")" ]] || die "unknown model alias: \${alias_name}"
}

wait_for_health() {
	local tries=300
	local i
	for ((i = 0; i < tries; i++)); do
		if curl -fsS "\${HEALTH_URL}" >/dev/null 2>&1; then
			return 0
		fi
		sleep 2
	done
	die "timed out waiting for vllm health at \${HEALTH_URL}"
}

cmd="\${1:-}"
case "\${cmd}" in
	list)
		current="\$(current_alias || true)"
		shopt -s nullglob
		for profile in "\${MODELS_DIR}"/*.env; do
			alias_name="\$(basename "\${profile}" .env)"
			if [[ "\${alias_name}" == "\${current}" ]]; then
				echo "* \${alias_name}"
			else
				echo "  \${alias_name}"
			fi
		done
		;;
	current)
		current_alias
		;;
	use)
		alias_name="\${2:-}"
		[[ -n "\${alias_name}" ]] || die "usage: vllm-model use <alias>"
		ensure_alias_exists "\${alias_name}"
		tmp_link="\${CURRENT_LINK}.tmp"
		ln -sfn "\$(profile_path "\${alias_name}")" "\${tmp_link}"
		mv -Tf "\${tmp_link}" "\${CURRENT_LINK}"
		sudo "\${VLLM_ADMIN}" apply-active
		sudo "\${VLLM_ADMIN}" restart-service
		wait_for_health
		echo "\${alias_name}"
		;;
	add)
		alias_name="\${2:-}"
		model_id="\${3:-}"
		[[ -n "\${alias_name}" && -n "\${model_id}" ]] || die "usage: vllm-model add <alias> <model_id>"
		target_file="\$(profile_path "\${alias_name}")"
		[[ ! -e "\${target_file}" ]] || die "profile already exists: \${target_file}"
		cat > "\${target_file}" <<PROFILE
MODEL_ID=\${model_id}
MODEL_ALIAS=\${alias_name}
VLLM_MAX_MODEL_LEN=8192
VLLM_GPU_MEMORY_UTILIZATION=0.95
VLLM_MAX_NUM_SEQS=1
VLLM_MODEL_ARGS=''
PROFILE
		echo "\${target_file}"
		;;
	edit)
		alias_name="\${2:-}"
		[[ -n "\${alias_name}" ]] || die "usage: vllm-model edit <alias>"
		ensure_alias_exists "\${alias_name}"
		"\${EDITOR:-vi}" "\$(profile_path "\${alias_name}")"
		;;
	rm)
		alias_name="\${2:-}"
		[[ -n "\${alias_name}" ]] || die "usage: vllm-model rm <alias>"
		ensure_alias_exists "\${alias_name}"
		if [[ "\$(current_alias || true)" == "\${alias_name}" ]]; then
			die "refusing to remove active model alias: \${alias_name}"
		fi
		rm -f "\$(profile_path "\${alias_name}")"
		;;
	download)
		alias_name="\${2:-}"
		[[ -n "\${alias_name}" ]] || die "usage: vllm-model download <alias>"
		ensure_alias_exists "\${alias_name}"
		sudo "\${VLLM_ADMIN}" download-model "\${alias_name}"
		;;
	start)
		sudo "\${VLLM_ADMIN}" apply-active
		sudo "\${VLLM_ADMIN}" pull-image
		sudo "\${VLLM_ADMIN}" start-service
		wait_for_health
		;;
	stop)
		sudo "\${VLLM_ADMIN}" stop-service
		;;
	restart)
		sudo "\${VLLM_ADMIN}" apply-active
		sudo "\${VLLM_ADMIN}" pull-image
		sudo "\${VLLM_ADMIN}" restart-service
		wait_for_health
		;;
	status)
		echo "current: \$(current_alias || true)"
		sudo "\${VLLM_ADMIN}" status
		;;
	logs)
		sudo "\${VLLM_ADMIN}" logs
		;;
	""|-h|--help|help)
		usage
		;;
	*)
		die "unknown command: \${cmd}"
		;;
esac
EOF

section_header 'Installing systemd service'
write_root_file "${SYSTEMD_UNIT}" 0644 <<EOF
[Unit]
Description=vLLM inference server
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
ExecStart=${SYSTEM_DAEMON}
ExecStop=${DOCKER_BIN} stop vllm
Restart=on-failure
RestartSec=5
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

section_header 'Installing sudoers rule for vLLM admin helper'
write_root_file "${SUDOERS_FILE}" 0440 <<EOF
${VLLM_OWNER} ALL=(root) NOPASSWD: ${SYSTEM_ADMIN} *
EOF
run_privileged visudo -cf "${SUDOERS_FILE}" >/dev/null

section_header 'Disabling legacy per-model vLLM units'
for legacy_unit in vllm-qwen.service vllm-gemma4.service vllm-step3.service; do
	if [[ "$(id -u)" == "0" ]]; then
		owner_uid="$(id -u "${VLLM_OWNER}")"
		sudo -u "${VLLM_OWNER}" XDG_RUNTIME_DIR="/run/user/${owner_uid}" \
			systemctl --user disable --now "${legacy_unit}" >/dev/null 2>&1 || true
	else
		systemctl --user disable --now "${legacy_unit}" >/dev/null 2>&1 || true
	fi
done

section_header 'Pulling pinned vLLM image and starting service'
run_privileged "${SYSTEM_ADMIN}" pull-image
run_privileged "${SYSTEM_ADMIN}" apply-active
run_privileged systemctl daemon-reload
run_privileged systemctl enable vllm.service >/dev/null
run_privileged systemctl restart vllm.service

success "vLLM docker setup complete"
echo "Control dir: ${CONTROL_DIR}"
echo "CLI: ${LOCAL_BIN_DIR}/vllm-model"
echo "Service: ${SYSTEMD_UNIT}"
