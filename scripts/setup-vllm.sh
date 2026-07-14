#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOTFILES_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

source "${DOTFILES_DIR}/packages/shell/.config/zsh/colors.sh"
source "${DOTFILES_DIR}/packages/shell/.config/zsh/functions.sh"
source "${DOTFILES_DIR}/packages/shell/.config/zsh/env.sh"

write_user_file() {
	local target_path="${1}"
	local file_mode="${2}"
	local tmp_file
	tmp_file="$(mktemp)"
	cat > "${tmp_file}"
	install -D -m "${file_mode}" "${tmp_file}" "${target_path}"
	rm -f "${tmp_file}"
}

write_user_file_if_missing() {
	local target_path="${1}"
	local file_mode="${2}"

	if [[ -e "${target_path}" ]]; then
		warn "preserving existing user-managed file '${target_path}'"
		cat >/dev/null
		return
	fi

	write_user_file "${target_path}" "${file_mode}"
}

ensure_user_env_key() {
	local target_path="${1}"
	local key_name="${2}"
	local key_value="${3}"

	if grep -q "^${key_name}=" "${target_path}" 2>/dev/null; then
		return
	fi
	printf '%s=%s\n' "${key_name}" "${key_value}" >> "${target_path}"
}

require_linux() {
	[[ "$(uname)" == "Linux" ]] || error "setup-vllm.sh only supports Linux"
}

require_command() {
	command_exists "${1}" || error "required command missing: ${1}"
}

ensure_durable_directory() {
	local target_path="${1}"

	[[ -d "${target_path}" ]] && return
	sudo install -d -m 0755 "${target_path}"
}

current_selection_is_ornith() {
	local resolved_path

	[[ -e "${CURRENT_LINK}" || -L "${CURRENT_LINK}" ]] || return 1
	if [[ -L "${CURRENT_LINK}" ]]; then
		resolved_path="$(readlink -f "${CURRENT_LINK}")" || return 1
		[[ "${resolved_path}" == "${MODELS_DIR}/ornith.env" ]]
		return
	fi
	if grep -qx 'ornith' "${CURRENT_LINK}" 2>/dev/null ||
		grep -qx 'ornith.env' "${CURRENT_LINK}" 2>/dev/null ||
		grep -qx "MODEL_ALIAS=ornith" "${CURRENT_LINK}" 2>/dev/null; then
		return 0
	fi
	return 1
}

preserve_direct_ornith_profile() {
	[[ -L "${CURRENT_LINK}" ]] && return
	grep -q '^MODEL_ID=' "${CURRENT_LINK}" 2>/dev/null || return
	[[ -e "${MODELS_DIR}/ornith.env" ]] && return
	install -m 0644 "${CURRENT_LINK}" "${MODELS_DIR}/ornith.env"
}

migrate_known_ornith_selection() {
	local temporary_link="${CURRENT_LINK}.tmp.$$"

	if [[ ! -e "${CURRENT_LINK}" && ! -L "${CURRENT_LINK}" ]]; then
		ln -s "${MODELS_DIR}/qwen3-27b-awq.env" "${CURRENT_LINK}"
		success "created default active model selection 'qwen3-27b-awq'"
		return
	fi
	if ! current_selection_is_ornith; then
		warn "preserving existing active model selection '${CURRENT_LINK}'"
		return
	fi

	preserve_direct_ornith_profile
	rm -f "${temporary_link}"
	ln -s "${MODELS_DIR}/qwen3-27b-awq.env" "${temporary_link}"
	mv -Tf "${temporary_link}" "${CURRENT_LINK}"
	success "migrated known Ornith selection to 'qwen3-27b-awq'; preserved ornith profile"
}

require_linux
require_command docker
require_command curl
require_command sudo
[[ "$(id -u)" != "0" ]] ||
	error "setup-vllm.sh must run as the user who owns the vLLM configuration"

CONTROL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vllm"
MODELS_DIR="${CONTROL_DIR}/models.d"
CURRENT_LINK="${CONTROL_DIR}/current"
RUNTIME_ENV="${CONTROL_DIR}/runtime.env"
LOCAL_BIN_DIR="${HOME}/.local/bin"
PROCESS_COMPOSE="${LOCAL_BIN_DIR}/dotfiles-process-compose"
VLLM_WRAPPER="${LOCAL_BIN_DIR}/dotfiles-vllm-docker"
HF_CACHE_DIR="/var/cache/vllm/huggingface"
VLLM_STATE_DIR="/var/lib/vllm/state"
section_header 'Preflighting Process Compose vLLM declaration'
[[ -x "${VLLM_WRAPPER}" ]] ||
	error "tracked vLLM wrapper is missing or not executable: ${VLLM_WRAPPER}"
[[ -x "${PROCESS_COMPOSE}" ]] ||
	error "Process Compose launcher is missing or not executable: ${PROCESS_COMPOSE}"
"${PROCESS_COMPOSE}" --check


section_header 'Creating user vLLM control directories'
ensure_dir_exists "${CONTROL_DIR}"
ensure_dir_exists "${MODELS_DIR}"
ensure_dir_exists "${LOCAL_BIN_DIR}"

section_header 'Writing vLLM runtime defaults'
write_user_file_if_missing "${RUNTIME_ENV}" 0644 <<EOF
VLLM_IMAGE=vllm/vllm-openai:v0.20.2
VLLM_CONTAINER_NAME=vllm
VLLM_HOST=0.0.0.0
VLLM_PORT=8080
VLLM_SHM_SIZE=24g
VLLM_DOCKER_GPUS=all
VLLM_DOCKER_EXTRA_ARGS='--ipc=host'
HF_HOME=${HF_CACHE_DIR}
VLLM_STATE_DIR=${VLLM_STATE_DIR}
EOF
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_IMAGE" "vllm/vllm-openai:v0.20.2"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_CONTAINER_NAME" "vllm"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_HOST" "0.0.0.0"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_PORT" "8080"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_SHM_SIZE" "24g"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_DOCKER_GPUS" "all"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_DOCKER_EXTRA_ARGS" "'--ipc=host'"
ensure_user_env_key "${RUNTIME_ENV}" "HF_HOME" "${HF_CACHE_DIR}"
ensure_user_env_key "${RUNTIME_ENV}" "VLLM_STATE_DIR" "${VLLM_STATE_DIR}"

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

migrate_known_ornith_selection

section_header 'Ensuring durable vLLM storage directories'
ensure_durable_directory "${HF_CACHE_DIR}"
ensure_durable_directory "${VLLM_STATE_DIR}"

section_header 'Installing user vLLM control CLI'
write_user_file "${LOCAL_BIN_DIR}/vllm-model" 0755 <<EOF
#!/usr/bin/env bash

set -euo pipefail

MODELS_DIR="${MODELS_DIR}"
CURRENT_LINK="${CURRENT_LINK}"
HEALTH_URL="http://127.0.0.1:8080/v1/models"
PROCESS_COMPOSE="${PROCESS_COMPOSE}"

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
  vllm-model start
  vllm-model stop
  vllm-model restart
  vllm-model status
  vllm-model logs
USAGE
}

profile_path() {
	printf '%s/%s.env\n' "\${MODELS_DIR}" "\${1}"
}

resolve_profile_path() {
	local pointer_value

	if [[ -L "\${CURRENT_LINK}" ]]; then
		readlink -f "\${CURRENT_LINK}"
		return
	fi
	[[ -f "\${CURRENT_LINK}" ]] || return 0
	if grep -q '^MODEL_ID=' "\${CURRENT_LINK}" 2>/dev/null; then
		printf '%s\n' "\${CURRENT_LINK}"
		return
	fi
	IFS= read -r pointer_value < "\${CURRENT_LINK}" || return 0
	pointer_value="\${pointer_value%.env}"
	[[ "\${pointer_value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 0
	[[ -f "\$(profile_path "\${pointer_value}")" ]] &&
		profile_path "\${pointer_value}"
}

current_alias() {
	local resolved_path model_alias
	resolved_path="\$(resolve_profile_path || true)"
	[[ -n "\${resolved_path}" && -f "\${resolved_path}" ]] || return 0
	model_alias="\$(sed -n 's/^MODEL_ALIAS=//p' "\${resolved_path}" | head -n 1)"
	[[ -n "\${model_alias}" ]] && printf '%s\n' "\${model_alias}" ||
		basename "\${resolved_path}" .env
}

ensure_alias_exists() {
	local alias_name="\${1}"
	[[ "\${alias_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
		die "invalid model alias: \${alias_name}"
	[[ -f "\$(profile_path "\${alias_name}")" ]] ||
		die "unknown model alias: \${alias_name}"
}

wait_for_health() {
	local tries=300 i
	for ((i = 0; i < tries; i++)); do
		if curl -fsS "\${HEALTH_URL}" >/dev/null 2>&1; then
			return 0
		fi
		sleep 2
	done
	die "timed out waiting for vLLM health at \${HEALTH_URL}"
}

cmd="\${1:-}"
case "\${cmd}" in
	list)
		current="\$(current_alias || true)"
		shopt -s nullglob
		for profile in "\${MODELS_DIR}"/*.env; do
			alias_name="\$(basename "\${profile}" .env)"
			[[ "\${alias_name}" == "\${current}" ]] && echo "* \${alias_name}" ||
				echo "  \${alias_name}"
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
		"\${PROCESS_COMPOSE}" process restart vllm
		wait_for_health
		echo "\${alias_name}"
		;;
	add)
		alias_name="\${2:-}"
		model_id="\${3:-}"
		[[ -n "\${alias_name}" && -n "\${model_id}" ]] ||
			die "usage: vllm-model add <alias> <model_id>"
		[[ "\${alias_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
			die "invalid model alias: \${alias_name}"
		[[ "\${model_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]] ||
			die "invalid model id"
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
		[[ "\$(current_alias || true)" != "\${alias_name}" ]] ||
			die "refusing to remove active model alias: \${alias_name}"
		rm -f "\$(profile_path "\${alias_name}")"
		;;
	start)
		"\${PROCESS_COMPOSE}" process start vllm
		wait_for_health
		;;
	stop)
		"\${PROCESS_COMPOSE}" process stop vllm
		;;
	restart)
		"\${PROCESS_COMPOSE}" process restart vllm
		wait_for_health
		;;
	status)
		echo "current: \$(current_alias || true)"
		"\${PROCESS_COMPOSE}" process get vllm
		;;
	logs)
		"\${PROCESS_COMPOSE}" process logs vllm
		;;
	""|-h|--help|help)
		usage
		;;
	*)
		die "unknown command: \${cmd}"
		;;
esac
EOF


success "vLLM user-owned Process Compose setup complete"
echo "Control dir: ${CONTROL_DIR}"
echo "CLI: ${LOCAL_BIN_DIR}/vllm-model"
echo "Controller: dotfiles-process-compose.service (vllm)"
