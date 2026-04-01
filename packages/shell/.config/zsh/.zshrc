
source "$ZDOTDIR/completions-opts.zsh"
source "$ZDOTDIR/options.zsh"
source "$ZDOTDIR/antigen.zsh"

antigen init "$ZDOTDIR/antigenrc.zsh"

# Apply paths after everything so we get last say of $PATH

# zprof 

# (prevent nvm.sh install.sh from writing to this file)
# /nvm.sh 

. "$HOME/.local/share/../bin/env"
