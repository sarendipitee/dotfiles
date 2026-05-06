# for profiling zsh also uncomment `zprof`in .zshrc
# see: https://unix.stackexchange.com/a/329719/27109
# zmodload zsh/zprof


export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:=${HOME}/.config}
export ZDOTDIR=${ZDOTDIR:=${XDG_CONFIG_HOME}/zsh}

source "$ZDOTDIR/env.sh"

export PATH="/usr/local/bin:$PATH"
export FLOX_SET_PROMPT=false
eval "$(flox activate -d $DOTFILES_DIR/packages/flox/global-env -m run)"

source "$ZDOTDIR/colors.sh"
source "$ZDOTDIR/functions.sh"
source "$ZDOTDIR/aliases.sh"
source "$ZDOTDIR/path.sh"

for f in ${PERSONAL_AUTOLOAD_DIR}/*; do source $f; done

