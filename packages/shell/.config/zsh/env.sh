# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

export LANG='en_US.UTF-8'
export LANGUAGE='en_US.UTF-8'
export LC_COLLATE='en_US.UTF-8'
export LC_CTYPE='en_US.UTF-8'
export LC_MESSAGES='en_US.UTF-8'
export LC_MONETARY='en_US.UTF-8'
export LC_NUMERIC='en_US.UTF-8'
export LC_TIME='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export LESSCHARSET='utf-8'

# XDG
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state
export XDG_CACHE_HOME=$HOME/.cache

# All development codebases are cloned into a subfolder of this folder
export PROJECTS_BASE_DIR="${HOME}/projects"

export DOTFILES_DIR=$PROJECTS_BASE_DIR/dotfiles

# uv and some other tools put things in ~/.local/bin
# export PATH="$PATH:$XDG_DATA_HOME/../bin"

# Executable scripts that are not shared as part of this public repo are present here
export PERSONAL_BIN_DIR="${HOME}/.my/bin"
export PERSONAL_AUTOLOAD_DIR="${HOME}/.my/autoload"

export ARCH="${HOSTTYPE:-$(uname -m)}"
export ARCHFLAGS="-arch ${ARCH}"

# ZSH
export HISTFILE="$XDG_STATE_HOME"/zsh/history
export ZSH_CACHE_DIR="${XDG_CACHE_HOME}/zsh"
export ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME}/zsh}"

# Android
export ANDROID_USER_HOME="$XDG_DATA_HOME"/android

#Python Path
export PYTHONSTARTUP="$XDG_CONFIG_HOME"/python/pythonrc

#Postgres.app
export PSQL_HISTORY="$XDG_STATE_HOME/psql_history"

# Krew (k8s plugin)
export KREW_ROOT="$XDG_DATA_HOME/krew"

#Rust/Cargo
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export RUSTUP_HOME="$XDG_DATA_HOME"/rustup

# gnupg
export GNUPGHOME="$XDG_DATA_HOME"/gnupg

# Keras
export KERAS_HOME="${XDG_STATE_HOME}/keras"

# LM Studio
export LM_STUDIO_API_KEY='xxx'
export LM_STUDIO_API_BASE='http://localhost:1234/v1'

# Node
export NODE_REPL_HISTORY="$XDG_STATE_HOME"/node_repl_history
export NPM_CONFIG_INIT_MODULE="$XDG_CONFIG_HOME"/npm/config/npm-init.js
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME"/npm
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME"/npm/npmrc
export NPM_CONFIG_PREFIX="$XDG_DATA_HOME"/npm
export TS_NODE_HISTORY="$XDG_STATE_HOME"/ts_node_repl_history

# Bun
export BUN_INSTALL="$XDG_DATA_HOME/bun"

# pnpm
export PNPM_HOME="$XDG_DATA_HOME/pnpm"

# Moon
export MOON_OUTPUT_STYLE=buffer-only-failure

# Nuget
export NUGET_PACKAGES="$XDG_CACHE_HOME"/NuGetPackages

# Go
export GOPATH="$XDG_STATE_HOME/projects/go"

# Java
export JAVA_HOME=/opt/homebrew/opt/openjdk/

# Docker config
export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker

# Haskell
[ -f "/Users/jd/.local/share/ghcup/env" ] && source "/Users/jd/.local/share/ghcup/env" # ghcup-env

# Dotnet
# export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet

# OrbStack shell integration (DOCKER_HOST, PATH, completions)
source "$HOME/.orbstack/shell/init.zsh" 2>/dev/null || :

# dyff
export KUBECTL_EXTERNAL_DIFF="dyff between --omit-header --set-exit-code"
