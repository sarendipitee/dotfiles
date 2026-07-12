#!/bin/sh

set -eu

PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
export PATH

MISE_VERSION="2026.7.5"
DOTFILES_PAGES_URL="${DOTFILES_PAGES_URL:-https://sarendipitee.github.io/dotfiles}"
MISE_BIN="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"
TMP_DIR=

cleanup() {
	if [ -n "$TMP_DIR" ]; then
		rm -rf "$TMP_DIR"
	fi
}

fatal() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

download() {
	curl -fsSL --retry 3 --retry-delay 1 "$1" -o "$2"
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

install_mise() {
	asset="mise-v${MISE_VERSION}-${MISE_PLATFORM}"
	url="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/${asset}"
	target="${TMP_DIR}/${asset}"

	download "$url" "$target"
	actual=$(sha256 "$target")
	[ "$actual" = "$MISE_SHA256" ] || fatal "mise checksum mismatch for ${asset}"
	mkdir -p "$(dirname "$MISE_BIN")"
	chmod 0755 "$target"
	mv "$target" "$MISE_BIN"
}

download_bootstrap_config() {
	config_file="${TMP_DIR}/mise.toml"
	checksum_file="${TMP_DIR}/mise.toml.sha256"

	if [ -n "${DOTFILES_MISE_CONFIG_FILE:-}" ]; then
		[ -r "$DOTFILES_MISE_CONFIG_FILE" ] || fatal "mise config is not readable: ${DOTFILES_MISE_CONFIG_FILE}"
		cp "$DOTFILES_MISE_CONFIG_FILE" "$config_file"
		printf 'Using local mise config %s\n' "$DOTFILES_MISE_CONFIG_FILE"
		return
	fi

	download "${DOTFILES_PAGES_URL}/mise/config.toml" "$config_file"
	download "${DOTFILES_PAGES_URL}/mise/config.toml.sha256" "$checksum_file"
	expected=$(awk 'NR == 1 {print $1}' "$checksum_file")
	[ -n "$expected" ] || fatal 'published Mise config checksum is empty'
	actual=$(sha256 "$config_file")
	[ "$actual" = "$expected" ] || fatal 'published Mise config checksum mismatch'
	printf 'Using Mise config from %s\n' "$DOTFILES_PAGES_URL"
}

case "$(uname -s)/$(uname -m)" in
	Darwin/arm64)
		MISE_PLATFORM=macos-arm64
		MISE_SHA256=a456c65907e8334619d77fa152bdcf9023fddc0daa03d47fbe86d032dbf565b0
		;;
	Darwin/x86_64)
		MISE_PLATFORM=macos-x64
		MISE_SHA256=62fe1fe9dbc32c6ce1388ee23df4a0862d3d7f40a6820b40c2f1cbab995dc1d4
		;;
	Linux/aarch64 | Linux/arm64)
		MISE_PLATFORM=linux-arm64
		MISE_SHA256=41fcf744050bfa27f9871e2151ac6f44b5ce2741424b3d5282b92becc71e6bc4
		;;
	Linux/x86_64)
		MISE_PLATFORM=linux-x64
		MISE_SHA256=5f7ab76afdf0780d12edeaa67e908094e9ccf7924cfe203e415c1cfb87bbf778
		;;
	*) fatal "unsupported platform: $(uname -s)/$(uname -m)" ;;
esac

command -v curl >/dev/null 2>&1 || fatal 'curl is required'
TMP_DIR=$(mktemp -d)
trap cleanup EXIT HUP INT TERM

if [ ! -x "$MISE_BIN" ] || ! "$MISE_BIN" --version 2>/dev/null | grep -q "^${MISE_VERSION} "; then
	printf 'Installing mise %s\n' "$MISE_VERSION"
	install_mise
fi

download_bootstrap_config

MISE_GLOBAL_CONFIG_FILE="${TMP_DIR}/mise.toml" \
	MISE_YES=1 \
	"$MISE_BIN" bootstrap --yes --update "$@"
