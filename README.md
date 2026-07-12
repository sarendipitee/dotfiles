# Dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Supports macOS and Linux (Ubuntu).

## Quick Start

```bash
git clone https://github.com/jondum/dotfiles.git ~/projects/dotfiles

~/projects/dotfiles/scripts/provision.sh
```

## What's Included

| Package | Description |
|---------|-------------|
| `shell` | Zsh configuration with Antidote, tmux, aliases, functions |
| `git` | Git config with aliases and custom settings |
| `vim` | Traditional Vim with vim-plug and common plugins |
| `nvim` | Neovim with LazyVim distribution and 25+ plugins |
| `ai` | Claude, OpenCode, and Kilo AI tool configurations |
| `homebrew` | Brewfile with all Homebrew packages and casks |
| `zoxide` | Directory bookmarking tool configuration |
| `misc` | Miscellaneous scripts and binaries |

## Prerequisites

- Git
- `sudo` access

Provisioning installs Flox, activates tracked global environment, installs GNU
Stow from that environment, links packages, initializes Antidote, and configures
Zsh. On Ubuntu, it also installs and enables OpenSSH server.

Profiles and component overrides:

```bash
./scripts/provision.sh --profile core
./scripts/provision.sh --profile server
./scripts/provision.sh --profile desktop
./scripts/provision.sh --profile full

./scripts/provision.sh --profile server --without-nvidia
./scripts/provision.sh --profile core --with-ssh --ssh-key-only
```

`full` is default. NVIDIA setup runs only when supported NVIDIA display hardware
is detected. `--ssh-key-only` requires populated `~/.ssh/authorized_keys` before
disabling password authentication. Provision logs live under
`~/.local/state/dotfiles/logs/`.

## Repository Structure

```
dotfiles/
├── packages/           # Config packages (one per tool)
│   ├── shell/         # Zsh, tmux configs
│   ├── git/           # Git configuration
│   ├── vim/           # Vim configuration
│   ├── nvim/          # Neovim configuration
│   ├── ai/            # AI tool configs
│   └── ...
├── scripts/            # Bootstrap and setup scripts
│   ├── provision.sh   # Main bootstrap script
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
