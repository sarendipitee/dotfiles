# PATH entries loaded before Flox activation.

#Python
# export PATH=$PATH:$HOME/Library/Python/3.9/bin

#Rust/Cargo
export PATH="$PATH:$CARGO_HOME/bin"

# Go
export PATH=$PATH:$HOME/Projects/go/bin

# GPG tools
export PATH=$PATH:/usr/local/MacGPG2/bin

# pnpm
export PATH="$PNPM_HOME/bin:$PATH"

# npm global binaries
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

# Krew
export PATH="$PATH:$KREW_ROOT/bin"

# Haskell
[ -f "$XDG_DATA_HOME/ghcup/env" ] && source "$XDG_DATA_HOME/ghcup/env" # ghcup-env

# bun
export PATH="$BUN_INSTALL/bin:$PATH"

# Proto - shims enable dynamic version detection for non-interactive shells
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

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
