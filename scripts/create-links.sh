#!/usr/bin/env bash

set -Eeo pipefail

script_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
packages_dir=$(realpath "${script_dir}/../packages")
dotfiles_dir=$(realpath "${script_dir}/..")

# Initialize git submodules (for antidote, etc.)
git -C "$dotfiles_dir" submodule update --init --recursive

packages=()
for package_dir in "$packages_dir"/*; do
	[ -d "$package_dir" ] || continue
	packages+=("$(basename "$package_dir")")
done

stow \
	--verbose \
	--dotfiles \
	--ignore='\.gitignore$' \
	--no-folding \
	--override='.+' \
	--restow \
	--dir "$packages_dir" \
	--target "$HOME" \
	"${packages[@]}"
