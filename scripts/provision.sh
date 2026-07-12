#!/usr/bin/env bash

set -Eeo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
DOTFILES_DIR=$(realpath "${SCRIPT_DIR}/..")
MISE_CONFIG="${DOTFILES_DIR}/packages/mise/.config/mise/config.toml"

usage() {
	cat <<'EOF'
Usage: provision.sh

Bootstrap from an existing dotfiles clone with its local Mise config.
Fresh machines should use:
  curl -fsSL https://sarendipitee.github.io/dotfiles/bootstrap.sh | sh
EOF
}

case "${1:-}" in
	-h | --help)
		usage
		exit 0
		;;
	'') ;;
	*)
		usage >&2
		exit 2
		;;
esac

DOTFILES_MISE_CONFIG_FILE="$MISE_CONFIG" \
	sh "$DOTFILES_DIR/bootstrap.sh" --skip repos,task

PATH="/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:$PATH" \
	bash "$DOTFILES_DIR/scripts/create-links.sh" --backup-known-conflicts

bash "$DOTFILES_DIR/scripts/bootstrap-system.sh"
