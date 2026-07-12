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
