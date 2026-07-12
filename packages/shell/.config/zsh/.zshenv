# for profiling zsh also uncomment `zprof`in .zshrc
# see: https://unix.stackexchange.com/a/329719/27109
# zmodload zsh/zprof


export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:=${HOME}/.config}
export ZDOTDIR=${ZDOTDIR:=${XDG_CONFIG_HOME}/zsh}
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

source "$ZDOTDIR/env.sh"
source "$ZDOTDIR/path.sh"
