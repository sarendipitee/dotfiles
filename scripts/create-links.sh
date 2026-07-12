#!/usr/bin/env bash

set -Eeo pipefail

backup_known_conflicts=false
if [ "${1:-}" = --backup-known-conflicts ]; then
	backup_known_conflicts=true
	shift
fi
[ "$#" -eq 0 ] || { printf 'Usage: create-links.sh [--backup-known-conflicts]\n' >&2; exit 2; }

script_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
packages_dir=$(realpath "${script_dir}/../packages")
dotfiles_dir=$(realpath "${script_dir}/..")

backup_conflicts() {
	local backup_dir target relative_target destination
	backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/$(date +%Y%m%d-%H%M%S)"
	for target in "$HOME/.zshenv" "$HOME/.config/zsh/.zshrc"; do
		if [ -e "$target" ] && [ ! -L "$target" ]; then
			relative_target=${target#"$HOME"/}
			destination="${backup_dir}/${relative_target}"
			mkdir -p "${destination%/*}"
			mv "$target" "$destination"
			printf 'Backed up conflicting file: %s\n' "$destination"
		fi
	done
}

# Initialize git submodules (for antidote, etc.)
git -C "$dotfiles_dir" submodule update --init --recursive

packages=()
for package_dir in "$packages_dir"/*; do
	[ -d "$package_dir" ] || continue
	packages+=("$(basename "$package_dir")")
done

stow_args=(
	--verbose
	--dotfiles
	--ignore='\.gitignore$'
	--no-folding
	--override='.+'
	--restow
	--dir "$packages_dir"
	--target "$HOME"
)

if ! stow --simulate "${stow_args[@]}" "${packages[@]}"; then
	if ! "$backup_known_conflicts"; then
		printf 'Stow preflight failed; no links changed. Resolve reported conflicts and retry.\n' >&2
		exit 1
	fi
	backup_conflicts
	if ! stow --simulate "${stow_args[@]}" "${packages[@]}"; then
		printf 'Stow preflight still fails after known-conflict backup. Resolve reported conflicts and retry.\n' >&2
		exit 1
	fi
fi

stow "${stow_args[@]}" "${packages[@]}"
