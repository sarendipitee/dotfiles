#!/usr/bin/env bash

set -Eeo pipefail

repo_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
tmp_dir=$(mktemp -d)
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
	"$repo_dir/scripts/create-links.sh" \
	"$repo_dir/scripts/install-flox.sh" \
	"$repo_dir/scripts/install-cuda.sh"
zsh -n "$repo_dir/packages/shell/.config/zsh/functions.sh"
"$repo_dir/scripts/provision.sh" --help >/dev/null

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -S warning \
		"$repo_dir/scripts/provision.sh" \
		"$repo_dir/scripts/create-links.sh" \
		"$repo_dir/scripts/install-flox.sh" \
		"$repo_dir/scripts/install-cuda.sh"
fi

test_home="$tmp_dir/home"
mkdir -p "$test_home"
printf 'legacy zshenv\n' > "$test_home/.zshenv"
HOME="$test_home" XDG_STATE_HOME="$test_home/.local/state" \
	bash "$repo_dir/scripts/create-links.sh" --backup-known-conflicts >/dev/null 2>&1
HOME="$test_home" XDG_STATE_HOME="$test_home/.local/state" \
	bash "$repo_dir/scripts/create-links.sh" --backup-known-conflicts >/dev/null 2>&1

[ -L "$test_home/.zshenv" ] || fail '.zshenv was not linked'
[ -L "$test_home/.config/zsh/.zshrc" ] || fail 'Zsh config was not linked'
[ -L "$test_home/.config/flox/active-envs" ] || fail 'Flox active environment config was not linked'
[ -L "$test_home/.config/git/config" ] || fail 'Git config was not linked'
[ -L "$test_home/.config/nvim/init.lua" ] || fail 'Neovim config was not linked'
grep -R -q '^legacy zshenv$' "$test_home/.local/state/dotfiles/backups" || fail '.zshenv backup missing'

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
