# for profiling zsh also uncomment `zprof`in .zshrc
# see: https://unix.stackexchange.com/a/329719/27109
# zmodload zsh/zprof


export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:=${HOME}/.config}
export ZDOTDIR=${ZDOTDIR:=${XDG_CONFIG_HOME}/zsh}

source "$ZDOTDIR/env.sh"

# Flox
export PATH="/usr/local/bin:$PATH"
export FLOX_SET_PROMPT=false
eval "$(flox activate -d $DOTFILES_DIR/packages/flox/global-env -m run)"

# Non-interactive shells do not run .zshrc, so direnv's prompt hook never fires.
# Export the current directory's env explicitly for command shells like Kilo tasks.
if [[ ! -o interactive ]] \
  && [[ -z "${DIRENV_DIR-}" ]] \
  && [[ -z "${DOTFILES_DIRENV_EXPORT_IN_PROGRESS-}" ]] \
  && command -v direnv >/dev/null 2>&1; then
  export DOTFILES_DIRENV_EXPORT_IN_PROGRESS=1
  eval "$(direnv export zsh)"
  unset DOTFILES_DIRENV_EXPORT_IN_PROGRESS
fi

source "$ZDOTDIR/colors.sh"
source "$ZDOTDIR/functions.sh"
source "$ZDOTDIR/aliases.sh"
source "$ZDOTDIR/path.sh"

# apparix
source "$XDG_CONFIG_HOME/apparix/apparix.bash"

# Use for machine-local secrets and overrides.
# To avoid leaking secrets in git.
if [[ -d "$PERSONAL_AUTOLOAD_DIR" ]]; then
  for f in ${PERSONAL_AUTOLOAD_DIR}/*; do source $f; done
fi
