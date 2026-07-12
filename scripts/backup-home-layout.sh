#!/usr/bin/env bash
# Create a portable inventory of bootstrap-relevant home-directory layout.

set -euo pipefail

readonly SCRIPT_NAME=${0##*/}
readonly SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
readonly DOTFILES_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

output_dir=''
restore_dir=''
restore_target="$HOME"
dry_run=false
inspect=false
include_large_state=false
include_untracked_archive=false
include_git_patches=false

usage() {
  cat <<'EOF'
Usage: backup-home-layout.sh [options]

Create a timestamped, metadata-only bootstrap backup. Default output contains a
 directory/symlink manifest, Git remotes, and a list of untracked files. It
 never follows symlinks or copies file contents by default.

Options:
  -o, --output DIR                Backup directory (must not already exist)
      --dry-run                   Print scope; write nothing
      --inspect                   Print discovered scope; write nothing
      --include-large-state       Inventory opt-in mutable state (.beads*,
                                  .dolt, .openclaw); still copies no contents
      --include-untracked-archive Copy untracked Git files into archives.
                                  Explicitly opt-in: archives can contain secrets.
      --include-git-patches       Write Git worktree and index patches.
                                  Explicitly opt-in: patches can contain secrets.
      --restore BACKUP_DIR        Recreate only recorded directories and symlinks
      --target DIR                Restore target (default: $HOME; with --restore)
  -h, --help                      Show this help

Sensitive locations are always excluded: .ssh, .gnupg, .netrc, .kube, .docker,
GitHub CLI config, .pki, and browser profiles. Put any such data in a separate
encrypted backup; this script intentionally has no switch to copy it.
EOF
}

die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

say() {
  printf '%s\n' "$*"
}

path_is_safe() {
  case "$1" in
    */.ssh|*/.ssh/*|*/.gnupg|*/.gnupg/*|*/.netrc|*/.netrc/*|*/.kube|*/.kube/*|*/.docker|*/.docker/*|*/.pki|*/.pki/*|*/.config/gh|*/.config/gh/*|*/Library/Application\ Support/Google/Chrome|*/Library/Application\ Support/Google/Chrome/*|*/Library/Application\ Support/Chromium|*/Library/Application\ Support/Chromium/*|*/.config/google-chrome|*/.config/google-chrome/*|*/.config/chromium|*/.config/chromium/*|*/.mozilla|*/.mozilla/*) return 1 ;;
  esac
  return 0
}

path_is_large_state() {
  case "$1" in
    */.beads|*/.beads/*|*/.beads-*|*/.beads-*/*|*/.dolt|*/.dolt/*|*/.openclaw|*/.openclaw/*) return 0 ;;
  esac
  return 1
}

path_is_cache() {
  case "$1" in
    */.cache|*/.cache/*|*/Cache|*/Cache/*|*/Caches|*/Caches/*|*/node_modules|*/node_modules/*|*/.codex/.tmp|*/.codex/.tmp/*|*/.claude/plugins/cache|*/.claude/plugins/cache/*) return 0 ;;
  esac
  return 1
}

mode_of() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

size_of() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

entry_type() {
  if [ -L "$1" ]; then printf 'symlink';
  elif [ -d "$1" ]; then printf 'directory';
  elif [ -f "$1" ]; then printf 'file';
  else printf 'other'; fi
}

relative_home_path() {
  case "$1" in
    "$HOME") printf '.' ;;
    "$HOME"/*) printf '%s' "${1#"$HOME"/}" ;;
    *) return 1 ;;
  esac
}

add_root() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  path_is_safe "$1" || return 0
  path_is_cache "$1" && return 0
  path_is_large_state "$1" && ! "$include_large_state" && return 0
  roots+=("$1")
}

discover_roots() {
  roots=()
  add_root "$DOTFILES_DIR"
  add_root "$HOME/projects"
  add_root "$HOME/Projects"
  add_root "$HOME/src"
  add_root "$HOME/code"
  add_root "$HOME/.config/systemd/user"
  add_root "$HOME/.local/share/systemd/user"
  add_root "$HOME/.config/autostart"
  add_root "$HOME/.local/bin"
  add_root "$HOME/.local/share/applications"
  add_root "$HOME/.beads"
  add_root "$HOME/.dolt"
  add_root "$HOME/.openclaw"
}

discover_repos() {
  repos=()
  local root git_dir repo known existing_repo
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' git_dir; do
      repo=${git_dir%/.git}
      path_is_safe "$repo" || continue
      path_is_cache "$repo" && continue
      known=false
      for existing_repo in "${repos[@]}"; do
        [ "$existing_repo" = "$repo" ] && known=true && break
      done
      "$known" && continue
      repos+=("$repo")
    done < <(find_repo_dirs "$root")
  done
}

find_prune_expression() {
  local pattern
  local -a patterns=(
    '*/.git' '*/.ssh' '*/.gnupg' '*/.kube' '*/.docker' '*/.pki'
    '*/.config/gh' '*/.mozilla' '*/.config/google-chrome' '*/.config/chromium'
    '*/Library/Application Support/Google/Chrome' '*/Library/Application Support/Chromium'
    '*/.cache' '*/Cache' '*/Caches' '*/cache' '*/node_modules' '*/.codex/.tmp'
    '*/.codex/plugins/cache' '*/.claude/plugins/cache' '*/.claude/plugins/marketplaces'
  )
  if ! "$include_large_state"; then
    patterns+=('*/.beads' '*/.beads-*' '*/.dolt' '*/.openclaw')
  fi
  for pattern in "${patterns[@]}"; do printf '%s\n' "$pattern"; done
}

find_visible_entries() {
  local root=$1 pattern
  local -a expression=()
  while IFS= read -r pattern; do expression+=( -path "$pattern" -o ); done < <(find_prune_expression)
  unset 'expression[${#expression[@]}-1]'
  find -P "$root" \( "${expression[@]}" \) -prune -o -print0 2>/dev/null
}

find_repo_dirs() {
  local root=$1 pattern
  local -a expression=()
  while IFS= read -r pattern; do
    [ "$pattern" = '*/.git' ] && continue
    expression+=( -path "$pattern" -o )
  done < <(find_prune_expression)
  unset 'expression[${#expression[@]}-1]'
  find -P "$root" \( "${expression[@]}" \) -prune -o -type d -name .git -print0 -prune 2>/dev/null
}

print_scope() {
  local root repo
  say 'Inventory roots:'
  for root in "${roots[@]}"; do say "  $root"; done
  say 'Git repositories:'
  for repo in "${repos[@]}"; do say "  $repo"; done
  say 'Excluded: secrets, browser profiles, caches, and large mutable state unless explicitly requested.'
}

write_manifest_entry() {
  local entry=$1 rel type mode size target
  path_is_safe "$entry" || return 0
  path_is_cache "$entry" && return 0
  path_is_large_state "$entry" && ! "$include_large_state" && return 0
  rel=$(relative_home_path "$entry") || return 0
  case "$rel" in *$'\t'*|*$'\n'*) printf 'Skipped unsupported path in manifest.\n' >&2; return 0;; esac
  type=$(entry_type "$entry")
  mode=$(mode_of "$entry")
  size='-'
  target='-'
  if [ "$type" = file ]; then size=$(size_of "$entry"); fi
  if [ "$type" = symlink ]; then target=$(readlink "$entry"); fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$mode" "$size" "$target" "$rel" >> "$output_dir/manifest.tsv"
}

write_manifest() {
  local root entry
  printf 'type\tmode\tsize_bytes\tlink_target\tpath_relative_to_home\n' > "$output_dir/manifest.tsv"
  for root in "${roots[@]}"; do
    while IFS= read -r -d '' entry; do write_manifest_entry "$entry"; done < <(find_visible_entries "$root")
  done
  while IFS= read -r -d '' entry; do write_manifest_entry "$entry"; done < <(find -P "$HOME" -maxdepth 1 -type l -print0 2>/dev/null)
}

git_pathspecs=(. ':(exclude)**/.env' ':(exclude)**/.env.*' ':(exclude)**/*credentials*' ':(exclude)**/*secret*' ':(exclude)**/*.pem' ':(exclude)**/*.key')

write_repo_state() {
  local repo=$1 id=$2 state_dir relative remote branch head
  state_dir="$output_dir/repos/$id"
  mkdir -p "$state_dir"
  relative=$(relative_home_path "$repo" || printf '%s' "$repo")
  printf 'path=%s\n' "$relative" > "$state_dir/repository.txt"
  git -C "$repo" remote -v > "$state_dir/remotes.txt" 2>/dev/null || true
  branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
  printf 'branch=%s\nhead=%s\n' "$branch" "$head" >> "$state_dir/repository.txt"
  git -C "$repo" status --porcelain=v1 --branch > "$state_dir/status.txt"
  if "$include_git_patches"; then
    git -C "$repo" diff --binary -- "${git_pathspecs[@]}" > "$state_dir/worktree.patch"
    git -C "$repo" diff --cached --binary -- "${git_pathspecs[@]}" > "$state_dir/index.patch"
  fi
  git -C "$repo" ls-files --others --exclude-standard > "$state_dir/untracked.txt"
  if "$include_untracked_archive" && [ -s "$state_dir/untracked.txt" ]; then
    (cd "$repo" && tar -czf "$state_dir/untracked.tar.gz" -T "$state_dir/untracked.txt")
  fi
}

write_restore_notes() {
  cat > "$output_dir/RESTORE.md" <<'EOF'
# Bootstrap-layout restore

1. Clone dotfiles and project repositories from `repos/*/remotes.txt`.
2. Run dotfiles `scripts/provision.sh` and `scripts/create-links.sh` as appropriate.
3. To recreate only missing recorded directories and symlinks, run:
   `./restore-layout.sh --target "$HOME"`
4. `untracked.txt` records files not tracked by Git; restore
   `untracked.tar.gz` only when explicitly created. `index.patch` and
   `worktree.patch` exist only when the backup used `--include-git-patches`;
   they can contain secrets, so inspect them before applying.
5. Recreate user systemd unit contents from their source repositories, then run
   `systemctl --user daemon-reload` and enable required units.

This backup intentionally excludes secret stores, browser profiles, caches, and
large application state. Restore these only from a separately encrypted backup.
EOF
  cp "$SCRIPT_DIR/$SCRIPT_NAME" "$output_dir/restore-layout.sh"
  chmod 700 "$output_dir/restore-layout.sh"
}

restore_layout() {
  local manifest="$restore_dir/manifest.tsv" type mode size target relative destination
  [ -f "$manifest" ] || die "manifest not found: $manifest"
  while IFS=$'\t' read -r type mode size target relative; do
    [ "$type" = type ] && continue
    validate_restore_relative_path "$relative"
    destination="$restore_target/$relative"
    if [ "$type" = directory ]; then
      validate_restore_directory "$relative"
      if "$dry_run"; then
        say "mkdir -p $destination"
      else
        ensure_restore_directory "$relative"
        chmod "$mode" "$destination"
      fi
    elif [ "$type" = symlink ]; then
      if "$dry_run"; then
        validate_restore_parent_directory "$relative"
      else
        ensure_restore_parent_directory "$relative"
      fi
      if [ -e "$destination" ] || [ -L "$destination" ]; then
        [ -L "$destination" ] && [ "$(readlink "$destination")" = "$target" ] && continue
        die "refusing to replace: $destination"
      fi
      if "$dry_run"; then say "ln -s $target $destination"; else ln -s "$target" "$destination"; fi
    fi
  done < "$manifest"
}

validate_restore_relative_path() {
  local relative=$1 component
  case "$relative" in ''|/*) die "unsafe manifest path: $relative";; esac
  IFS='/' read -r -a restore_path_components <<< "$relative"
  for component in "${restore_path_components[@]}"; do
    case "$component" in ''|.|..) die "unsafe manifest path: $relative";; esac
  done
}

validate_restore_directory() {
  local relative=$1 component current=$restore_target
  validate_restore_root
  IFS='/' read -r -a restore_path_components <<< "$relative"
  for component in "${restore_path_components[@]}"; do
    current="$current/$component"
    if [ -L "$current" ]; then die "refusing symlink in restore path: $current"; fi
    if [ -e "$current" ]; then
      [ -d "$current" ] || die "refusing to replace: $current"
    fi
  done
}

validate_restore_parent_directory() {
  local relative=$1 parent=${1%/*}
  if [ "$parent" = "$relative" ]; then
    validate_restore_root
  else
    validate_restore_directory "$parent"
  fi
}

ensure_restore_directory() {
  local relative=$1 component current=$restore_target
  ensure_restore_root
  IFS='/' read -r -a restore_path_components <<< "$relative"
  for component in "${restore_path_components[@]}"; do
    current="$current/$component"
    if [ -L "$current" ]; then die "refusing symlink in restore path: $current"; fi
    if [ -e "$current" ]; then
      [ -d "$current" ] || die "refusing to replace: $current"
    else
      mkdir "$current"
    fi
  done
}

ensure_restore_parent_directory() {
  local relative=$1 parent=${1%/*}
  if [ "$parent" = "$relative" ]; then
    ensure_restore_root
  else
    ensure_restore_directory "$parent"
  fi
}

ensure_restore_root() {
  validate_restore_root
  if [ ! -e "$restore_target" ]; then
    mkdir "$restore_target"
  fi
}

validate_restore_root() {
  if [ -L "$restore_target" ]; then die "refusing symlink restore target: $restore_target"; fi
  if [ -e "$restore_target" ]; then
    [ -d "$restore_target" ] || die "restore target is not a directory: $restore_target"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output) [ "$#" -ge 2 ] || die "missing output directory"; output_dir=$2; shift 2;;
    --dry-run) dry_run=true; shift;;
    --inspect) inspect=true; shift;;
    --include-large-state) include_large_state=true; shift;;
    --include-untracked-archive) include_untracked_archive=true; shift;;
    --include-git-patches) include_git_patches=true; shift;;
    --restore) [ "$#" -ge 2 ] || die "missing backup directory"; restore_dir=$2; shift 2;;
    --target) [ "$#" -ge 2 ] || die "missing restore target"; restore_target=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done

if [ -n "$restore_dir" ]; then
  [ -z "$output_dir" ] || die "--restore and --output cannot be combined"
  restore_layout
  exit 0
fi

discover_roots
discover_repos
if "$inspect" || "$dry_run"; then print_scope; exit 0; fi
if [ -z "$output_dir" ]; then output_dir="$HOME/bootstrap-layout-backup-$(date -u +%Y%m%dT%H%M%SZ)"; fi
[ ! -e "$output_dir" ] || die "output already exists: $output_dir"
if "$include_git_patches"; then
  printf '%s\n' 'WARNING: Git patches can contain secrets. Store this backup securely.' >&2
fi
mkdir -p "$output_dir/repos"
chmod 700 "$output_dir"
print_scope > "$output_dir/scope.txt"
write_manifest
repo_id=0
for repo in "${repos[@]}"; do repo_id=$((repo_id + 1)); write_repo_state "$repo" "$(printf '%03d' "$repo_id")"; done
write_restore_notes
say "Backup inventory written to: $output_dir"
