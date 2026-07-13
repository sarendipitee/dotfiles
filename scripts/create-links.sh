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

git_ignore_patterns() {
	local pkg_rel="$1" pkg_dir="$2" force="$3" tracked prefix esc type path parent
	tracked=$(mktemp)
	git -C "$dotfiles_dir" ls-files -- "$pkg_rel" > "$tracked" || { rm -f "$tracked"; return; }
	prefix="$pkg_rel/"
	(
		cd "$pkg_dir" || return 0
		find . -path ./.git -prune -o -printf '%y\t%p\n'
	) 2>/dev/null | awk -v tf="$tracked" -v prefix="$prefix" -v force="$force" '
		BEGIN {
			while ((getline line < tf) > 0) {
				if (line == "") continue
				sub("^" prefix, "", line)
				trackedfile[line] = 1
				d = line
				while (d ~ /\//) { sub(/\/[^\/]*$/, "", d); trackeddir[d] = 1 }
			}
			close(tf)
			nf = split(force, fl, "\n")
			for (i = 1; i <= nf; i++) if (fl[i] != "") forcep[fl[i]] = 1
		}
		function keeps(path,    k) {
			for (k in forcep) {
				if (path == k) return 1
				if (substr(path, 1, length(k) + 1) == k "/") return 1
				if (substr(k, 1, length(path) + 1) == path "/") return 1
			}
			return 0
		}
		{
			type = substr($0, 1, 1)
			path = substr($0, 3)
			sub(/^\.\//, "", path)
			if (path == "" || path == ".") next
			if (keeps(path)) next
			if (path in trackedfile) next
			if (path in trackeddir) next
			parent = path
			sub(/\/[^\/]*$/, "", parent)
			if (parent == path) parent = ""
			if (parent != "" && !(parent in trackeddir)) next
			esc = path
			gsub(/[.+*?()|\[\]{}^$]/, "\\\\&", esc)
			if (type == "d") print "^" esc "(/.*)?$"
			else print "^" esc "$"
		}
	'
	rm -f "$tracked"
}

# Initialize git submodules (for antidote, etc.)
git -C "$dotfiles_dir" submodule update --init --recursive

packages=()
for package_dir in "$packages_dir"/*; do
	[ -d "$package_dir" ] || continue
	case "$(basename "$package_dir")" in flox | homebrew) continue ;; esac
	packages+=("$(basename "$package_dir")")
done

stow_args=(
	--verbose
	--dotfiles
	--ignore='\.gitignore$'
	--ignore='^agents'
	--no-folding
	--override='.+'
	--restow
	--dir "$packages_dir"
	--target "$HOME"
)

# Whitelist by git for the ai package: only symlink files tracked by git there,
# ignoring the generated runtime dirs (.claude, .codex, node_modules, ...).
# Generated agent definitions (from scripts/generate-ai-agents.mjs) live in
# gitignored dirs but must still be stowed, so force-include them.
# Other packages keep their own stow-local-ignore handling for intentionally
# untracked-but-stowed files.
ignore_args=()
if printf '%s\n' "${packages[@]}" | grep -qx ai; then
	ai_force_include=$'.claude/agents
.codex/agents
.config/kilo/agents
.config/opencode/agents
.omp/agent/agents'
	while IFS= read -r pattern; do
		[ -n "$pattern" ] && ignore_args+=(--ignore="$pattern")
	done < <(git_ignore_patterns packages/ai "${packages_dir}/ai" "$ai_force_include")
fi

if ! stow --simulate "${stow_args[@]}" "${ignore_args[@]}" "${packages[@]}"; then
	if ! "$backup_known_conflicts"; then
		printf 'Stow preflight failed; no links changed. Resolve reported conflicts and retry.\n' >&2
		exit 1
	fi
	backup_conflicts
	if ! stow --simulate "${stow_args[@]}" "${ignore_args[@]}" "${packages[@]}"; then
		printf 'Stow preflight still fails after known-conflict backup. Resolve reported conflicts and retry.\n' >&2
		exit 1
	fi
fi

stow "${stow_args[@]}" "${ignore_args[@]}" "${packages[@]}"
