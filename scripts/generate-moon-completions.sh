#!/usr/bin/env bash
# Regenerate the moon zsh completion with dynamic project/task target support.
#
# moon completions emits static clap completions where `moon run <target>`,
# `moon ci <target>`, etc. fall back to `_default` (no suggestions). This wraps
# those target positionals with dynamic completers that query the workspace:
#
#   - `moon run <TAB>`         -> project IDs and task IDs
#   - `moon run foo:<TAB>`     -> tasks belonging to project `foo`
#   - `moon run :<TAB>`        -> all task IDs
#   - `moon check <TAB>`       -> project IDs
#
# Run: bash scripts/generate-moon-completions.sh
# The output file is committed; regenerating requires the pinned moon version.

set -Eeo pipefail

script_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
dotfiles_dir=$(realpath "${script_dir}/..")
out_file="${dotfiles_dir}/packages/shell/.config/zsh/completions/_moon"

moon_bin=$(command -v moon || true)
if [ -z "$moon_bin" ]; then
	printf 'moon not on PATH; run via mise or install it first.\n' >&2
	exit 1
fi

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

# 1. Base clap completions.
moon completions --shell zsh >| "$tmp_file"

# 2. Ride the target/project positionals with dynamic completers.
#    Positionals are unique by their help text, so target by description.
sed -i \
	-e "s|Task targets to \\*only\\* graph:_default|Task targets to *only* graph:_moon_task_targets|" \
	-e "s|Task target to \\*only\\* graph:_default|Task target to *only* graph:_moon_task_targets|" \
	-e "s|List of explicit project IDs to check:_default|List of explicit project IDs to check:_moon_project_ids|" \
	-e "s|List of explicit task targets to run:_default|List of explicit task targets to run:_moon_task_targets|" \
	-e "s|List of project IDs to copy sources for:_default|List of project IDs to copy sources for:_moon_project_ids|" \
	-e "s|List of task targets to execute in the action pipeline:_default|List of task targets to execute in the action pipeline:_moon_task_targets|" \
	-e "s|Project ID to inspect:_default|Project ID to inspect:_moon_project_ids|" \
	-e "s|Project ID to \\*only\\* graph:_default|Project ID to *only* graph:_moon_project_ids|" \
	"$tmp_file"

# 3. Insert the dynamic completers before the autoload dispatch footer.
if ! grep -q 'funcstack\[1\]' "$tmp_file"; then
	printf 'Footer marker not found; generated layout changed.\n' >&2
	exit 1
fi

# Split the file at the dispatch footer, then reassemble body + helpers + footer.
footer_text=$(sed -n '/^if \[ "$funcstack\[1\]" = "_moon" \]; then$/,$p' "$tmp_file")
body_text=$(sed '/^if \[ "$funcstack\[1\]" = "_moon" \]; then$/,$d' "$tmp_file")
[ -n "$footer_text" ] || {
	printf 'Failed to isolate dispatch footer.\n' >&2
	exit 1
}

{
	printf '%s\n' "$body_text"
	cat <<'FUNCS'

# ---- Generated patch (see scripts/generate-moon-completions.sh) ----
# Dynamic completion sourced from the moon workspace graph.

(( $+functions[_moon_targets_from_query] )) ||
_moon_targets_from_query() {
	# Usage: _moon_targets_from_query <query kind> [project]
	# Emits candidates with any <project> prefix so they match the current word.
	local kind="$1" project="$2"
	local out
	if [[ "$kind" == "projects" ]]; then
		out=$(moon query projects 2>/dev/null | jq -r '.projects[].id' 2>/dev/null)
	elif [[ "$kind" == "project-tasks" ]]; then
		out=$(moon query tasks --project "$project" 2>/dev/null \
			| jq -r --arg p "$project" '.tasks[$p] | keys[] | "\($p):\(.)"' 2>/dev/null)
	else
		out=$(moon query tasks 2>/dev/null | jq -r '.tasks | to_entries[].value | keys[]' 2>/dev/null)
	fi
	[[ -n "$out" ]] && compadd -- ${(f)out}
}

(( $+functions[_moon_project_ids] )) ||
_moon_project_ids() {
	_moon_targets_from_query projects
}

(( $+functions[_moon_task_targets] )) ||
_moon_task_targets() {
	local current="${words[CURRENT]}"
	if [[ "$current" == *:* ]]; then
		# foo:<TAB> -> tasks for foo; :<TAB> -> all task IDs
		local project="${current%%:*}"
		if [[ -n "$project" ]]; then
			_moon_targets_from_query project-tasks "$project"
		else
			compadd -- "${(@f)$(moon query tasks 2>/dev/null \
				| jq -r '.tasks | to_entries[].value | keys[] | ":\(.)"' 2>/dev/null)}"
		fi
	else
		# bare <TAB> -> projects (suffixed with ':') plus global task IDs
		compadd -S ':' -- "${(@f)$(moon query projects 2>/dev/null | jq -r '.projects[].id' 2>/dev/null)}"
		_moon_targets_from_query all-tasks
	fi
}
FUNCS
	printf '%s\n' "$footer_text"
} > "$tmp_file"

mv "$tmp_file" "$out_file"
trap - EXIT
printf 'Wrote %s\n' "$out_file"