
source "$ZDOTDIR/completions-opts.zsh"
source "$ZDOTDIR/options.zsh"
source "$ZDOTDIR/antigen.zsh"

antigen init "$ZDOTDIR/antigenrc.zsh"

# Apply this after so we get last say of path
source "$ZDOTDIR/path.sh"

# zprof 
# /nvm.sh (prevent nvm.sh install.sh from writing to this file)
