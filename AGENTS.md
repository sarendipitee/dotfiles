# AGENTS.md — Dotfiles Repository

## Scope

Personal macOS and Ubuntu configuration managed with GNU Stow. Tracked package
contents mirror paths under `$HOME`; Stow owns all links.

## Repository Map

```text
packages/
  ai/                AI agent definitions and tool configuration
  shell/             Zsh, tmux, aliases, functions, XDG environment
  mise/              Global tools, packages, repositories, bootstrap hooks
  process-compose/   Declarative per-user services and launch wrappers
  systemd/           Linux user-service configuration
  launchd/           macOS user-service configuration
  git/, vim/, nvim/  Editor and Git configuration
  ghostty/, lazygit/, mitmproxy/, misc/, zoxide/
  flox/, homebrew/   Environment and package-manager support; not Stowed
scripts/
  create-links.sh        Platform-aware Stow orchestration
  provision.sh           Existing-clone bootstrap entry point
  bootstrap-system.sh    Privileged machine setup
  generate-ai-agents.mjs Agent-definition generator
settings/defaults/       Exported macOS application preferences
```

## Rules

- Edit source only under `packages/`; never edit resulting files under `$HOME`.
- Preserve home-relative layout. `packages/ghostty/.config/ghostty/config`
  becomes `~/.config/ghostty/config`.
- Use `scripts/create-links.sh`; it initializes submodules, excludes
  platform-incompatible packages, preflights Stow, and handles the `ai`
  package's generated definitions. Do not create symlinks manually.
- Use `--dotfiles` with any direct Stow command. Names beginning with `dot-`
  map to dotfiles.
- Keep generated state, caches, sessions, databases, logs, machine-specific
  files, and secrets outside tracked package contents. Respect each package's
  `.stow-local-ignore` and `.gitignore`.
- Never store API keys, tokens, private keys, or durable service `.env` files
  in this repository.
- Read adjacent configuration before changing it; reuse its existing pattern.

## Platform and Provisioning

- `scripts/provision.sh` is for an existing checkout. It links packages and
  runs privileged bootstrap. It can change system packages and services.
- Fresh-machine bootstrap is documented in `README.md`.
- `scripts/create-links.sh` Stows every supported package. On Linux it excludes
  `launchd`; on macOS it excludes `systemd`; it always excludes `flox` and
  `homebrew`.
- `scripts/bootstrap-system.sh` changes host state. Do not run it for routine
  configuration edits.
- macOS defaults belong in `settings/defaults/` and are applied through
  `scripts/osx-defaults.sh`.

## Package-Specific Guidance

### Shell

`packages/shell/.config/zsh/` is modular:

- `.zshenv` loads first.
- `.zshrc` configures interactive shells.
- `env.sh` defines XDG and tool environment variables.
- `path.sh`, `aliases.sh`, `functions.sh`, and `colors.sh` have focused roles.

Keep XDG paths consistent:

```sh
XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share
XDG_STATE_HOME=$HOME/.local/state
XDG_CACHE_HOME=$HOME/.cache
```

Reuse helpers from `functions.sh`, including `clone_repo_into`,
`ensure_dir_exists`, `is_macos`, `is_linux`, `is_windows`, and
`set_ssh_folder_permissions`.

### AI Definitions

`packages/ai/agents/*.yml` is source of truth for shared agent definitions.
Do not edit rendered files in `.claude/agents`, `.codex/agents`,
`.config/kilo/agents`, `.config/opencode/agents`, or `.omp/agent/agents`.

```bash
node scripts/generate-ai-agents.mjs
node scripts/generate-ai-agents.mjs --check
```

Generated definitions are intentionally force-included by `create-links.sh`
despite being in runtime-oriented directories.

### Services

`packages/process-compose/.config/process-compose/` defines portable user
services. Host selection is intentionally machine-local or environment-driven;
do not commit host-specific selection files or secrets. Validate declarations
without starting services:

```bash
~/.local/bin/dotfiles-process-compose --check
```

After a deliberate service-definition change, restart the native launcher:

```bash
# Linux
systemctl --user restart dotfiles-process-compose.service
systemctl --user status dotfiles-process-compose.service

# macOS
launchctl kickstart -k "gui/$(id -u)/io.sarendipitee.process-compose"
launchctl print "gui/$(id -u)/io.sarendipitee.process-compose"
```

## Safe Validation

Run checks matched to changed surface:

```bash
# Shell scripts
bash -n scripts/create-links.sh scripts/provision.sh scripts/bootstrap-system.sh

# Generated AI definitions
node scripts/generate-ai-agents.mjs --check

# One package, no links changed
stow --simulate --verbose --dotfiles --no-folding \
  --dir packages --target "$HOME" <package>
```

For a full link update, run `./scripts/create-links.sh`; this modifies `$HOME`
only after a successful Stow preflight. Use `./scripts/provision.sh` only when
machine provisioning is intended.
