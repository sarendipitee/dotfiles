# AGENTS.md - Agent Instructions for Dotfiles Repository

## Repository Overview

This is a dotfiles repository using **GNU Stow** for symlink management. Configuration files are organized into packages under `packages/` and symlinked to `$HOME` using Stow.

## Directory Structure

```
dotfiles/
├── packages/              # Config packages (one per tool/application)
│   ├── ai/               # AI tools (Claude, OpenCode, Kilo)
│   ├── apparix/          # Directory bookmarking
│   ├── git/              # Git config
│   ├── flox/             # Flox config (PRIMARY package manager)
│   ├── homebrew/         # Homebrew Brewfile (**only** for MacOS only packages - Flox for everything else for cross platform)
│   ├── misc/             # Miscellaneous scripts/binaries
│   ├── nvim/             # Neovim (LazyVim distribution)
│   ├── shell/            # Zsh, tmux configuration
│   └── vim/              # Traditional Vim
├── scripts/               # Bootstrap and setup scripts
│   ├── provision.sh      # Main bootstrap (macOS/Linux)
│   ├── create-links.sh   # Stow symlink creation
│   ├── osx-defaults.sh   # macOS system defaults
│   └── capture-defaults.sh # Export/import macOS preferences
└── settings/              # Exported macOS app preferences
    └── defaults/          # ~70+ .defaults files
```

## Key Conventions

### Stow Usage

- All configs use GNU Stow with `--dotfiles` flag for proper dotfile handling
- Package directory: `packages/`
- Target directory: `$HOME`
- Symlink command: `stow -v --dotfiles -d packages -t $HOME <package>`

### XDG Base Directory Specification

The repository follows XDG conventions. Key environment variables are set in `packages/shell/.config/zsh/env.sh`:

- `XDG_CONFIG_HOME=$HOME/.config`
- `XDG_DATA_HOME=$HOME/.local/share`
- `XDG_STATE_HOME=$HOME/.local/state`
- `XDG_CACHE_HOME=$HOME/.cache`

### Zsh Configuration (Modular)

Located in `packages/shell/.config/zsh/`:

- `.zshenv` - Environment variables (sourced first)
- `.zshrc` - Interactive shell config
- `env.sh` - All XDG and tool-specific environment variables
- `aliases.sh` - Shell aliases
- `functions.sh` - Helper functions (clone_repo_into, ensure_dir_exists, OS detection)
- `path.sh` - PATH modifications
- `colors.sh` - Color definitions

### Neovim Plugin Organization

Located in `packages/nvim/.config/nvim/`:

- `lua/plugins/` - 32 plugin configurations
- `lua/themes/` - 20+ color schemes
- `lua/plugins/lang/` - Language-specific plugins

## Common Tasks

### Adding a New Package

1. Create directory: `mkdir -p packages/<tool>/.config/<tool>`
2. Add config files in the appropriate subdirectory
3. Create `.stow-local-ignore` if needed to exclude runtime files
4. Run: `stow -v --dotfiles -d packages -t $HOME <tool>`

### Modifying Existing Configs

1. **Read first** - Use Read tool to understand existing conventions
2. **Follow patterns** - Match existing code style, naming, and structure
3. **Edit in place** - Modify files in `packages/<tool>/`, not in `$HOME`
4. **Test symlinks** - Run stow command to verify symlinks work

### Working with AI Tool Configs

Located in `packages/ai/`:

- `.claude/CLAUDE.md` - Instructions for Claude assistant
- `.config/opencode/` - OpenCode configuration
- `.config/kilo/` - Kilo configuration
- `.stow-local-ignore` excludes runtime files (sessions, cache, logs)

## Security Guidelines

- **Never commit secrets** - Check `.gitignore` files before committing
- **Runtime files** - Each package may have `.stow-local-ignore` to exclude generated files
- **SSH keys** - `scripts/provision.sh` sets proper SSH permissions; never modify keys
- **API keys/tokens** - Store in environment variables, not in config files

## Helper Functions

Available in `packages/shell/.config/zsh/functions.sh`:

- `clone_repo_into <repo> <dir>` - Git clone with error handling
- `ensure_dir_exists <dir>` - Create directory safely
- `is_macos()`, `is_linux()`, `is_windows()` - OS detection
- `set_ssh_folder_permissions` - Fix SSH key permissions

## Scripts Overview

| Script | Purpose | Safe to Run |
|--------|---------|-------------|
| `provision.sh` | Full bootstrap for new machine | Yes - idempotent |
| `create-links.sh` | Create stow symlinks | Yes - idempotent |
| `osx-defaults.sh` | Apply macOS preferences | Interactive prompts |
| `capture-defaults.sh` | Export/import app preferences | Safe |

## File Modification Guidelines

1. **Always read files before editing** - Understand context and conventions
2. **Preserve existing style** - Match indentation, quoting, naming conventions
3. **Use edit tool** - Not sed/awk for file modifications
4. **Batch related changes** - Group related edits in one message
5. **Verify after changes** - Run stow to test symlinks if modifying configs

## What NOT to Do

- Don't create symlinks manually - use Stow
- Don't add runtime files to packages (bundle directories, undo files, etc.)
- Don't modify `provision.sh` without understanding the full bootstrap flow
- Don't commit without checking `.gitignore` exclusions
- Don't add documentation files (*.md) unless explicitly requested
- Don't use `cd` in bash commands - use `workdir` parameter instead

## Testing Changes

After modifying configurations:

```bash
stow -v --dotfiles -d packages -t $HOME <package>

find $HOME -xtype l 2>/dev/null

zsh -c "source ~/.zshenv && echo 'OK'"

nvim --headless "+qa" 2>&1 | head -20
```
