source "$ZDOTDIR/colors.sh"
source "$ZDOTDIR/functions.sh"
source "$ZDOTDIR/aliases.sh"

# Use for machine-local secrets and overrides.
if [[ -d "$PERSONAL_AUTOLOAD_DIR" ]]; then
	for f in "$PERSONAL_AUTOLOAD_DIR"/*(N); do source "$f"; done
fi

if command -v zoxide >/dev/null 2>&1; then
	eval "$(zoxide init zsh)"
fi

source "$ZDOTDIR/completions-opts.zsh"
source "$ZDOTDIR/options.zsh"

# Antidote plugin manager (static loading for speed)
source "$ZDOTDIR/antidote/antidote.zsh"

if [[ "$OSTYPE" == darwin* ]]; then
	export ANTIDOTE_HOME="$HOME/Library/Caches/antidote"
else
	export ANTIDOTE_HOME="$XDG_CACHE_HOME/antidote"
fi
export ZSH="$ANTIDOTE_HOME/github.com/ohmyzsh/ohmyzsh"

zsh_plugins=${ZDOTDIR:-$HOME/.config/zsh}/.zsh_plugins
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  antidote bundle <${zsh_plugins}.txt >! ${zsh_plugins}.zsh
fi
source ${zsh_plugins}.zsh

# Remote session indicator (SSH nesting badge for prompt)
source "${DOTFILES_DIR:?}/packages/shell/.config/zsh/prompt-remote.zsh"

# Unalias Oh My Zsh git aliases that conflict with tools
unalias gc 2>/dev/null

# Apply paths after everything so we get last say of $PATH
# (path_helper in /etc/zprofile runs after .zshenv and can reorder PATH)

# Re-apply user path precedence here after all other scripts have run
# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.local/bin:$HOME/.my/bin:$HOME/.my/scripts:$PATH

# Direnv integration
export DIRENV_LIB_PATH="${HOME}/.config/direnv/lib"
if command -v direnv >/dev/null 2>&1; then
	eval "$(direnv hook zsh)"
fi

# Remove duplicate PATH entries while preserving system paths needed by prompt plugins.
typeset -U path PATH

# GPG agent TTY sync
export GPG_TTY=$TTY
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

# zprof
