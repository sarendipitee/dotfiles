# Start with minimal sane path without /usr/libexec/path_helper or other crap
PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

#Python
# export PATH=$PATH:$HOME/Library/Python/3.9/bin

# Android platform tools
export PATH=$PATH:~/.mine/bin/android

#Rust/Cargo
export PATH="$PATH:$CARGO_HOME/bin"

# Go
export PATH=$PATH:$HOME/Projects/go/bin

# GPG tools
export PATH=$PATH:/usr/local/MacGPG2/bin

# pnpm
export PATH="$PNPM_HOME:$PATH"

# Krew
export PATH="$PATH:$KREW_ROOT/bin"

#Go
export PATH=$PATH:$GOROOT/bin

# Haskell
[ -f "$XDG_DATA_HOME/ghcup/env" ] && source "$XDG_DATA_HOME/ghcup/env" # ghcup-env

# bun
export PATH="$BUN_INSTALL/bin:$PATH"
# [ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# Proto - shims enable dynamic version detection for non-interactive shells
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

# ----

# remove /usr/local/bin and /usr/bin
export PATH=$(echo ":$PATH:" | sed -e "s#:/usr/local/bin:#:#g" -e "s/^://" -e "s/:$//")
export PATH=$(echo ":$PATH:" | sed -e "s#:/usr/bin:#:#g" -e "s/^://" -e "s/:$//")
# add /usr/local/bin and /usr/bin in that order
export PATH="/usr/local/bin:/usr/bin:$PATH"

# Load this first so that we prefer homebrew installed over XCode crap
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"

# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/.mine/bin:$PATH
export PATH=$HOME/.mine/scripts:$PATH

if command -v flox &>/dev/null; then
	eval "$(flox activate -d $DOTFILES_DIR/packages/flox/global-env -m run)"
fi
