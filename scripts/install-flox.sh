#!/usr/bin/env bash

set -Eeo pipefail

FLOX_VERSION="1.12.0"
TMP_DIR=

cleanup() {
	[ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
}

trap cleanup EXIT

error() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

verify_checksum() {
	local file="$1" expected="$2" actual
	if command -v sha256sum >/dev/null 2>&1; then
		actual=$(sha256sum "$file" | awk '{print $1}')
	else
		actual=$(shasum -a 256 "$file" | awk '{print $1}')
	fi
	[ "$actual" = "$expected" ] || error "Checksum mismatch for $(basename "$file")"
}

main() {
	local os arch artifact checksum package_type package_file package_url

	if command -v flox >/dev/null 2>&1; then
		printf 'Flox already installed: %s\n' "$(flox --version 2>/dev/null || printf unknown)"
		return
	fi

	os=$(uname -s)
	arch=$(uname -m)
	case "${os}/${arch}" in
		Darwin/arm64)
			artifact="flox-${FLOX_VERSION}.aarch64-darwin.pkg"
			checksum="1a30d001ca2bb7506b551528cc68bc4d2226a965e631d3e81389fb1cf2fb18cb"
			package_type=osx
			;;
		Darwin/x86_64)
			artifact="flox-${FLOX_VERSION}.x86_64-darwin.pkg"
			checksum="597df53a8ba66515058243e31b28e92f9284f2e9fd56d86c424eb1b782e74f8b"
			package_type=osx
			;;
		Linux/aarch64 | Linux/arm64)
			artifact="flox-${FLOX_VERSION}.aarch64-linux.deb"
			checksum="50d919fd8977510bf24433374b64672932f3d09115cb555a750647f8a2a8050f"
			package_type=deb
			;;
		Linux/x86_64)
			artifact="flox-${FLOX_VERSION}.x86_64-linux.deb"
			checksum="78c9118823a4e7b4f287a632396d9efb4e9044818ac1d4df36a5b96d3d8df159"
			package_type=deb
			;;
		*) error "Unsupported platform for Flox: ${os}/${arch}" ;;
	esac

	if [ "$package_type" = deb ]; then
		command -v dpkg >/dev/null 2>&1 || error 'Flox Linux bootstrap requires dpkg'
	fi

	TMP_DIR=$(mktemp -d)
	package_file="${TMP_DIR}/${artifact}"
	package_url="https://downloads.flox.dev/by-env/stable/${package_type}/${artifact}"

	printf 'Downloading Flox %s for %s/%s\n' "$FLOX_VERSION" "$os" "$arch"
	curl -fsSL "$package_url" -o "$package_file"
	verify_checksum "$package_file" "$checksum"

	if [ "$package_type" = osx ]; then
		sudo installer -pkg "$package_file" -target /
	else
		sudo dpkg -i "$package_file" || sudo apt-get install -f -y
	fi

	command -v flox >/dev/null 2>&1 || error 'Flox installation completed without a usable flox command'
	printf 'Flox installed: %s\n' "$(flox --version)"
}

main "$@"
