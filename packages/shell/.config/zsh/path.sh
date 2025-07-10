# Android
export ANDROID_USER_HOME="$XDG_DATA_HOME"/android

#Python Path
export PATH=$PATH:$HOME/Library/Python/3.9/bin
export PYTHONSTARTUP="$XDG_CONFIG_HOME"/python/pythonrc

#Postgres
export PSQL_HISTORY="$XDG_STATE_HOME/psql_history"

# Android platform tools
export PATH=$PATH:~/.mine/bin/android

#Rust/Cargo
export PATH=$PATH:~/.cargo/bin
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export RUSTUP_HOME="$XDG_DATA_HOME"/rustup

# gnupg
export GNUPGHOME="$XDG_DATA_HOME"/gnupg

# Keras
export KERAS_HOME="${XDG_STATE_HOME}/keras"

# Node
export NODE_REPL_HISTORY="$XDG_STATE_HOME"/node_repl_history
export NPM_CONFIG_INIT_MODULE="$XDG_CONFIG_HOME"/npm/config/npm-init.js
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME"/npm
export NPM_CONFIG_TMP="$XDG_RUNTIME_DIR"/npm
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME"/npm/npmrc
export TS_NODE_HISTORY="$XDG_STATE_HOME"/ts_node_repl_history

#NVM
export NVM_DIR="$HOME/.local/nvm"

# Nuget
export NUGET_PACKAGES="$XDG_CACHE_HOME"/NuGetPackages

# Go
export PATH=$PATH:$HOME/Projects/go/bin

# Java
export JAVA_HOME=/opt/homebrew/opt/openjdk/

#Go
export GOPATH=$HOME/Projects/go
export PATH=$PATH:$GOROOT/bin

export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker

# Haskell
[ -f "$XDG_DATA_HOME/ghcup/env" ] && source "$XDG_DATA_HOME/ghcup/env" # ghcup-env

# Dotnet
# export PATH="/usr/local/share/dotnet:$PATH"
# export PATH="$HOME/.dotnet/tools:$PATH"
export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet

# bun
export BUN_INSTALL="$XDG_DATA_HOME/bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# eval $(thefuck --alias)

export ZSH="$XDG_DATA_HOME"/oh-my-zsh

#
# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.mine/bin:$PATH
export PATH=$HOME/.mine/scripts:$PATH

# Load this first so that we prefer homebrew installed over XCode crap
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
