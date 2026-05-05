# Tool-specific PATH additions
# Note: Final PATH ordering is done in .zshrc to override macOS path_helper

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

# Proto - shims enable dynamic version detection for non-interactive shells
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
