# Dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Supports macOS and Linux (Ubuntu).

## Quick Start

```bash
git clone https://github.com/yourusername/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles

./scripts/provision.sh

stow -v --dotfiles -d packages -t $HOME <package>
```

## What's Included

| Package | Description |
|---------|-------------|
| `shell` | Zsh configuration with antigen, tmux, aliases, functions |
| `git` | Git config with aliases and custom settings |
| `vim` | Traditional Vim with vim-plug and common plugins |
| `nvim` | Neovim with LazyVim distribution and 25+ plugins |
| `ai` | Claude, OpenCode, and Kilo AI tool configurations |
| `homebrew` | Brewfile with all Homebrew packages and casks |
| `apparix` | Directory bookmarking tool configuration |
| `misc` | Miscellaneous scripts and binaries |

## Prerequisites

- **GNU Stow** - `brew install stow` or `apt install stow`
- **Homebrew** (macOS) - Package manager for macOS/Linux

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

## License

MIT
