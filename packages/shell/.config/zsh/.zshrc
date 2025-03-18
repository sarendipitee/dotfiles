
source "$ZDOTDIR/completions-opts.zsh"
source "$ZDOTDIR/options.zsh"
source "$ZDOTDIR/antigen.zsh"

antigen init "$ZDOTDIR/antigenrc.zsh"

# zprof 

export NVM_DIR="$HOME/.local/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
