#!/usr/bin/env bash

set -Eeo pipefail

CUDA_KEYRING_VERSION="1.1-1"
TMP_DIR=

cleanup() {
	[ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
}

trap cleanup EXIT

usage() {
	cat <<'EOF'
Usage: install-cuda.sh [--toolkit] [--container-toolkit]

Installs current NVIDIA CUDA toolkit and/or NVIDIA Container Toolkit on
supported Ubuntu LTS releases.
EOF
}

error() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

detect_ubuntu() {
	[ -r /etc/os-release ] || error '/etc/os-release is required'
	# shellcheck disable=SC1091
	source /etc/os-release
	[ "${ID:-}" = ubuntu ] || error "Unsupported distribution: ${ID:-unknown}"

	case "${VERSION_ID:-}" in
		22.04) CUDA_REPOSITORY=ubuntu2204; CUDA_KEYRING_SHA256=d93190d50b98ad4699ff40f4f7af50f16a76dac3bb8da1eaaf366d47898ff8df ;;
		24.04) CUDA_REPOSITORY=ubuntu2404; CUDA_KEYRING_SHA256=d2a6b11c096396d868758b86dab1823b25e14d70333f1dfa74da5ddaf6a06dba ;;
		26.04) CUDA_REPOSITORY=ubuntu2604; CUDA_KEYRING_SHA256=f7f474b5f6a4adf987aa587920df00e713285958ef6a913dda1945a544a3099e ;;
		*) error "Unsupported Ubuntu release for CUDA: ${VERSION_ID:-unknown}" ;;
	esac

	[ "$(uname -m)" = x86_64 ] || error "CUDA automation supports x86_64 only: $(uname -m)"
}

install_cuda_repository() {
	local keyring_file keyring_url
	TMP_DIR=$(mktemp -d)
	keyring_file="${TMP_DIR}/cuda-keyring.deb"
	keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPOSITORY}/x86_64/cuda-keyring_${CUDA_KEYRING_VERSION}_all.deb"

	curl -fsSL "$keyring_url" -o "$keyring_file"
	printf '%s  %s\n' "$CUDA_KEYRING_SHA256" "$keyring_file" | sha256sum --check --status
	sudo dpkg -i "$keyring_file"
	rm -rf "$TMP_DIR"
	TMP_DIR=
}

install_cuda_toolkit() {
	if command -v nvcc >/dev/null 2>&1; then
		printf 'CUDA toolkit already installed: %s\n' "$(nvcc --version | tail -1)"
		return
	fi

	install_cuda_repository
	sudo apt-get update
	sudo apt-get install -y cuda-toolkit
	command -v nvcc >/dev/null 2>&1 || error 'CUDA toolkit installed without nvcc'
}

install_container_toolkit() {
	if ! command -v nvidia-ctk >/dev/null 2>&1; then
		sudo install -d -m 0755 /usr/share/keyrings
		curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
			sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
		curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
			sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
			sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y nvidia-container-toolkit
	fi

	command -v docker >/dev/null 2>&1 || error 'Docker is required for NVIDIA Container Toolkit configuration'
	sudo nvidia-ctk runtime configure --runtime=docker
	sudo systemctl restart docker
	sudo systemctl is-active --quiet docker || error 'Docker failed after NVIDIA runtime configuration'
}

main() {
	local toolkit=false container_toolkit=false

	if [ "$#" -eq 0 ]; then
		toolkit=true
		container_toolkit=true
	fi

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--toolkit) toolkit=true ;;
			--container-toolkit) container_toolkit=true ;;
			-h | --help) usage; return 0 ;;
			*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; return 2 ;;
		esac
		shift
	done

	detect_ubuntu
	"$toolkit" && install_cuda_toolkit
	"$container_toolkit" && install_container_toolkit
}

main "$@"
