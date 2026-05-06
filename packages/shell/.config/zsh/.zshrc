
source "$ZDOTDIR/completions-opts.zsh"
source "$ZDOTDIR/options.zsh"

# Antidote plugin manager (static loading for speed)
source "$ZDOTDIR/antidote/antidote.zsh"

zsh_plugins=${ZDOTDIR:-$HOME/.config/zsh}/.zsh_plugins
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
  antidote bundle <${zsh_plugins}.txt >! ${zsh_plugins}.zsh
fi
source ${zsh_plugins}.zsh

# Apply paths after everything so we get last say of $PATH
# (path_helper in /etc/zprofile runs after .zshenv and can reorder PATH)

# Re-apply user path precedence here after all other scripts have run
# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.local/bin:$HOME/.mine/bin:$HOME/.mine/scripts:$PATH

# Homebrew
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# Flox takes ultimate precedence
export FLOX_SET_PROMPT=false
eval "$(flox activate -d $DOTFILES_DIR/packages/flox/global-env -m run)"

# Proto shell activation - enables dynamic version detection per project
eval "$(proto activate zsh)"

# Remove duplicate PATH entries while preserving system paths needed by prompt plugins.
typeset -U path PATH

# zprof
