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
	"$repo_dir/scripts/install-cuda.sh"
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
		"$repo_dir/scripts/install-cuda.sh"
fi

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
grep -R -q '^legacy zshenv$' "$test_home/.local/state/dotfiles/backups" || fail '.zshenv backup missing'
grep -q 'mise/shims' "$test_home/.config/zsh/path.sh" || fail 'Mise shims are absent from shell PATH config'
[ ! -L "$test_home/.config/zsh/flox.sh" ] || fail 'Stow did not remove legacy flox.sh link'
[ ! -L "$test_home/.config/zsh/path.pre-flox.sh" ] || fail 'Stow did not remove legacy pre-Flox PATH link'
[ ! -L "$test_home/.config/zsh/path.post-flox.sh" ] || fail 'Stow did not remove legacy post-Flox PATH link'
if find "$test_home" -type l -lname '*packages/flox/*' | grep -q .; then
	fail 'Legacy Flox package was linked'
fi

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
