# Dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Supports macOS and Linux (Ubuntu).

## Quick Start

```bash
curl -fsSL https://sarendipitee.github.io/dotfiles/bootstrap.sh | sh
```

Bootstrap installs pinned Mise binary, loads published global config, installs
packages and tools, clones or updates this repository, links configs with Stow,
and runs machine setup. Bootstrap script and Mise config ship together through
GitHub Pages. Use HTTPS so script cannot be modified in transit.

## What's Included

| Package | Description |
|---------|-------------|
| `shell` | Zsh configuration with Antidote, tmux, aliases, functions |
| `git` | Git config with aliases and custom settings |
| `vim` | Traditional Vim with vim-plug and common plugins |
| `nvim` | Neovim with LazyVim distribution and 25+ plugins |
| `ai` | Claude, OpenCode, and Kilo AI tool configurations |
| `mise` | Global Mise tools, system packages, repositories, and bootstrap hooks |
| `process-compose` | Host-selected declarative user services managed by Process Compose |
| `zoxide` | Directory bookmarking tool configuration |
| `misc` | Miscellaneous scripts and binaries |

## Prerequisites

- curl
- `sudo` access

Ubuntu bootstrap installs and enables OpenSSH server, Docker Engine, and
Tailscale. NVIDIA drivers and CUDA install only when supported NVIDIA display
hardware is detected. Set component controls before running bootstrap:

```sh
export DOTFILES_WITH_SSH=false
export DOTFILES_WITH_DOCKER=false
export DOTFILES_WITH_NVIDIA=false
export DOTFILES_WITH_TAILSCALE=false
export DOTFILES_SSH_KEY_ONLY=true
```

`DOTFILES_SSH_KEY_ONLY=true` requires populated `~/.ssh/authorized_keys` before
password authentication is disabled.

For existing clone development, run `./scripts/provision.sh`. It uses tracked
Mise config and skips repository reconciliation, preventing SSH/HTTPS remote URL
differences from blocking local provisioning.

## Global Packages and Tools

Edit `packages/mise/.config/mise/config.toml`, then apply current declarations:

```bash
mise bootstrap --update
```

Mise config is Stowed to `~/.config/mise/config.toml`. `[tools]` supports Mise
backends such as Aqua, GitHub releases, pipx, npm, and language runtimes.
`[bootstrap.packages]` is limited to operating-system prerequisites,
machine-global libraries and commands without suitable tool backends, and macOS
applications. Mise's Brew package manager supplies shared packages on macOS and
Linux; APT entries cover Ubuntu-only services and build dependencies. No
generated Brewfile or package lock synchronization step is required.

## Declarative User Services

Process definitions live in
`~/.config/process-compose/process-compose.yaml`. Mise owns Process Compose,
`yq`, and service binary versions. Service packages come from Mise/bootstrap:
`brew:et`, `npm:omniroute`, `npm:@openai/codex`, and Node 26.
`~/.config/process-compose/hosts.yaml` selects processes by host profile:

```yaml
sd-mbp: [eternal-terminal]
aorus: [eternal-terminal, omniroute, codex-remote-control, hindsight]
```

Eternal Terminal runs on every declared host and accepts inbound TCP connections
on port 2022. Allow that port through the host firewall and Tailscale policy for
clients that need access.

OmniRoute runs only on `aorus`, binds to `127.0.0.1:20128`, and reports health at
`http://127.0.0.1:20128/api/monitoring/health`. Its database, generated files,
and durable `.env` live under
`${XDG_STATE_HOME:-$HOME/.local/state}/omniroute` and must never be committed.
Bootstrap seeds that `.env` from OmniRoute's package-generated `.env` once,
then preserves it across Mise upgrades. Existing durable values always win
because OmniRoute loads `DATA_DIR/.env` before package `.env`. Loopback binding
keeps its dashboard and API unavailable to remote clients; changing exposure
requires authentication and matching firewall policy.

On Linux profile `aorus`, bootstrap recognizes valid legacy `~/.omniroute`
state and migrates its whole tree into the XDG state directory before Process
Compose starts. Legacy `.env` assignments override same-name seeded values,
including the required `STORAGE_ENCRYPTION_KEY`; secret values are never logged.
Migration stops managed services, rejects unmanaged OmniRoute processes with
`pgrep`, and uses `fuser` from `psmisc` immediately before snapshotting to prove
no process holds the legacy database files open. SQLite's online backup API
creates and integrity-checks a consistent database snapshot; stale WAL/SHM
files are never installed.
Source and destination directories are tightened to mode `0700`, and migrated
regular files to `0600`. Any previous unmarked XDG state is atomically retained
at `${XDG_STATE_HOME:-$HOME/.local/state}/omniroute.pre-legacy-migration-v1`.
Neither the original legacy tree nor that backup is deleted. A migration marker
makes reruns idempotent. Unsafe paths, ambiguous state, or partial migration
state fail closed and may require manual audit before provisioning can continue.
When both legacy and unmarked durable trees exist, provision automatically uses
legacy state as authoritative and atomically preserves prior XDG state at the
backup path before installing the validated legacy SQLite snapshot.

Codex remote control runs only on `aorus` in foreground mode through Mise. Its
wrapper reads only `OMNIROUTER_API_KEY` from Hindsight's environment file;
other Hindsight secrets never enter Codex's environment. File ownership,
permissions, ancestors, syntax, and key uniqueness fail closed before Codex
starts. Its JSON startup line supplies Process Compose readiness, and Process
Compose sends SIGINT for clean shutdown. Hindsight also runs only on `aorus` in
foreground Docker mode. Its API and database ports bind only to
`127.0.0.1:18888` and `127.0.0.1:19999`; health is checked at
`http://127.0.0.1:18888/health`.
Hindsight reads secrets from untracked
`~/.config/hindsight/hindsight.env` and persists database state under
`~/.local/share/hindsight`. Neither path belongs in this repository.
Before provisioning `aorus`, authenticate Codex interactively as the login user:

```bash
mise exec -- codex login
```

Bootstrap checks `mise exec -- codex login status` before changing service or
OmniRoute state. Failed login status aborts without stopping services or
modifying migration state, and command output is suppressed to avoid exposing
authentication details.

Mise permits install scripts only for OmniRoute and its `better-sqlite3` native
dependency. Before starting Process Compose, bootstrap enforces mode `0700` on
OmniRoute's durable state directory and `0600` on both package and durable
`.env` files. OmniRoute's Process Compose command uses a pre-start wrapper that
repeats package `.env` validation and mode convergence on every process start,
including restarts after Mise upgrades. Symlinked, writable-ancestor, or
wrong-owner paths fail closed. Hardening runs with login-user authority.
Invoking bootstrap through a root shell fails before OmniRoute files change.
Bootstrap also opens an
in-memory SQLite database to verify `better-sqlite3`; only a missing native
binding triggers a forced OmniRoute reinstall through Mise, which applies the
declared `omniroute` and `better-sqlite3` build-script allowlist. Bootstrap
persists custom `XDG_STATE_HOME` values into generated launchd or systemd user
service environment configuration so later restarts use identical state paths.

Add process names to host arrays after defining them in `process-compose.yaml`.
Selection precedence is non-empty `DOTFILES_HOST`, optional
`~/.config/process-compose/host`, then `hostname -s`. Use `DOTFILES_HOST` as a
one-shot override. Put one profile name in the untracked `host` file for a
persistent native-service override when machine hostname differs. Empty,
multiline, and unsafe profile values fail validation, as do unknown hosts and
undefined processes. Machine-specific `host` files and secrets must not be
committed. Process declarations needing secrets must use explicit Process
Compose environment configuration or external files outside repository.
Launcher passes `--disable-dotenv`, preventing implicit `.env` loading.
Validate declarations:

```bash
~/.local/bin/dotfiles-process-compose --check
DOTFILES_HOST=sd-mbp ~/.local/bin/dotfiles-process-compose --check
```

Run `./scripts/provision.sh` to install packages, link declarations, and activate
one native user
launcher: `io.sarendipitee.process-compose` through launchd on macOS, or
`dotfiles-process-compose.service` through systemd on Linux. Linux bootstrap
also enables lingering so user services continue without an interactive login.
Before starting Process Compose, Linux bootstrap finishes Docker setup, stops
the existing Process Compose owner, disables and stops legacy per-service
systemd units for Eternal Terminal, OmniRoute, Codex remote control, and
Hindsight, then stops any detached Codex remote-control daemon and removes a
stale `hindsight` container. Legacy Codex rollback configuration is retained,
but inline OmniRouter keys are atomically replaced with
`EnvironmentFile=%h/.config/hindsight/hindsight.env` and mode `0600`. Bootstrap
then waits up to ten minutes for all Aorus processes and Hindsight's HTTP health
endpoint; provisioning fails if ownership transfer leaves replacements down.
On `aorus`, bootstrap also recognizes the root-owned legacy
`/etc/systemd/system/etserver.service`, validates its loaded path, owner, mode,
link count, ancestors, login user, and Homebrew `etserver --cfgfile` command,
then disables and stops it before Process Compose takes port `2022`. Unexpected
or unsafe units fail closed. Unit file remains in place for rollback. Readiness
timeouts report only declared process name, running state, readiness state,
restart count, and exit code; commands, environment, and logs remain hidden.
Fresh Docker group membership requires logout/login and a provisioning rerun
before Process Compose ownership transfer starts.
After declaration changes, validate, then restart and inspect launcher:

```bash
# macOS
launchctl kickstart -k "gui/$(id -u)/io.sarendipitee.process-compose"
launchctl print "gui/$(id -u)/io.sarendipitee.process-compose"

# Linux
systemctl --user restart dotfiles-process-compose.service
systemctl --user status dotfiles-process-compose.service
```

Process Compose exposes its TUI through a user-only Unix socket. Launcher uses
`$XDG_RUNTIME_DIR/dpc/pc.sock` when runtime directory is safe and writable;
otherwise it uses
`${XDG_STATE_HOME:-$HOME/.local/state}/process-compose/run/pc.sock`. Attach with:

```bash
socket="${XDG_STATE_HOME:-$HOME/.local/state}/process-compose/run/pc.sock"
if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/dpc/pc.sock" ]]; then
  socket="$XDG_RUNTIME_DIR/dpc/pc.sock"
fi
~/.local/bin/mise exec -- process-compose --use-uds --unix-socket "$socket" attach
```

Privileged and vendor system daemons such as Docker, SSH, Tailscale, and vLLM
remain native system services.

## Repository Structure

```
dotfiles/
├── packages/           # Config packages (one per tool)
│   ├── shell/         # Zsh, tmux configs
│   ├── git/           # Git configuration
│   ├── vim/           # Vim configuration
│   ├── nvim/          # Neovim configuration
│   ├── ai/            # AI tool configs
│   ├── mise/          # Global Mise bootstrap config
│   ├── process-compose/ # Declarative user services and launcher
│   ├── launchd/       # macOS user launchers
│   ├── systemd/       # Linux user units
│   └── ...
├── scripts/            # Bootstrap and setup scripts
│   ├── provision.sh   # Existing-clone bootstrap wrapper
│   ├── bootstrap-system.sh # Privileged machine setup
│   ├── create-links.sh # Stow symlink creation
│   └── osx-defaults.sh # macOS system defaults
└── settings/           # Exported macOS preferences
    └── defaults/       # App-specific .defaults files
```

## Adding a New Config

1. Create a new directory under `packages/<tool>/`
2. Mirror the home directory structure (e.g., `.config/tool/config`)
3. Run `stow -v --dotfiles -d packages -t $HOME <tool>`

## macOS System Defaults

Apply macOS system preferences:

```bash
./scripts/osx-defaults.sh
```

Export current macOS app preferences:

```bash
./scripts/capture-defaults.sh e
```

## Bootstrap Layout Backup

Create a metadata-only inventory of dotfiles, project repositories, local app
links, and user systemd layout:

```bash
./scripts/backup-home-layout.sh
```

Backup directory contains `manifest.tsv`, Git remotes, untracked-file lists,
plus `RESTORE.md`. It does not copy file contents, secrets, browser profiles,
caches, or large mutable state by default. `--include-git-patches` is an
explicit opt-in and can capture secrets. Use `--inspect` to review scope,
`--dry-run` to make no writes, and `--help` for opt-in flags.

## License

MIT
