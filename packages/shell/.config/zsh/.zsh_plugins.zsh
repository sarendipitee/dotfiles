fpath+=( "$HOME/.cache/antidote/github.com/getantidote/use-omz" )
source "$HOME/.cache/antidote/github.com/getantidote/use-omz/use-omz.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/async_prompt.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/bzr.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/clipboard.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/cli.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/compfix.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/completion.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/correction.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/diagnostics.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/directories.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/functions.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/git.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/grep.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/history.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/key-bindings.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/misc.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/nvm.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/prompt_info_functions.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/spectrum.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/termsupport.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/theme-and-appearance.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/lib/vcs_info.zsh"
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/themes/agnoster.zsh-theme"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/brew" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/brew/brew.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/eza" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/eza/eza.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/iterm2" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/iterm2/iterm2.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/last-working-dir" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/last-working-dir/last-working-dir.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/npm" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/npm/npm.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/safe-paste" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/safe-paste/safe-paste.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/vi-mode" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/vi-mode/vi-mode.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/zbell" )
source "$HOME/.cache/antidote/github.com/ohmyzsh/ohmyzsh/plugins/zbell/zbell.plugin.zsh"
fpath+=( "$HOME/.cache/antidote/github.com/zsh-users/zsh-completions" )
source "$HOME/.cache/antidote/github.com/zsh-users/zsh-completions/zsh-completions.plugin.zsh"
if ! (( $+functions[zsh-defer] )); then
  fpath+=( "$HOME/.cache/antidote/github.com/romkatv/zsh-defer" )
  source "$HOME/.cache/antidote/github.com/romkatv/zsh-defer/zsh-defer.plugin.zsh"
fi
fpath+=( "$HOME/.cache/antidote/github.com/zsh-users/zsh-syntax-highlighting" )
zsh-defer source "$HOME/.cache/antidote/github.com/zsh-users/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
