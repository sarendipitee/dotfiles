#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

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
export PROJECTS_BASE_DIR="${HOME}/Projects"

export DOTFILES_DIR=$PROJECTS_BASE_DIR/dotfiles

# uv and some other tools put things in ~/.local/bin
export PATH="$PATH:$XDG_DATA_HOME/../bin"

# Executable scripts that are not shared as part of this public repo are present here
export PERSONAL_BIN_DIR="${HOME}/.mine/bin"
export PERSONAL_AUTOLOAD_DIR="${HOME}/.mine/autoload"

# Moving homebrew env vars here itself so that the initial homebrew installation on
# a vanilla OS can be done/applied into memory immediately
export ARCH="$(uname -m)"
export ARCHFLAGS="-arch ${ARCH}"
if [[ "${ARCH}" =~ 'arm' ]]; then
  export HOMEBREW_PREFIX='/opt/homebrew'
else
  export HOMEBREW_PREFIX='/usr/local'
fi
export HOMEBREW_BUNDLE_FILE="${XDG_CONFIG_HOME}/homebrew/Brewfile"
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_CLEANUP_MAX_AGE_DAYS=3
export HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS=3
export HOMEBREW_BAT=1
export HOMEBREW_VERBOSE_USING_DOTS=1

# Load this first so that we prefer homebrew installed over XCode crap
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"

# Antigen
export ADOTDIR="$XDG_DATA_HOME/antigen"

# ZSH
export HISTFILE="$XDG_STATE_HOME"/zsh/history
export ZSH_CACHE_DIR="${XDG_CACHE_HOME}/zsh"
export ZDOTDIR="${ZDOTDIR:-${XDG_CONFIG_HOME}/zsh}"

# remove /usr/local/bin and /usr/bin
export PATH=$(echo ":$PATH:" | sed -e "s#:/usr/local/bin:#:#g" -e "s/^://" -e "s/:$//")
export PATH=$(echo ":$PATH:" | sed -e "s#:/usr/bin:#:#g" -e "s/^://" -e "s/:$//")
# add /usr/local/bin and /usr/bin in that order
export PATH="/usr/local/bin:/usr/bin:$PATH"

# Android
export ANDROID_USER_HOME="$XDG_DATA_HOME"/android

#Python Path
# export PATH=$PATH:$HOME/Library/Python/3.9/bin
export PYTHONSTARTUP="$XDG_CONFIG_HOME"/python/pythonrc

#Postgres.app
export PSQL_HISTORY="$XDG_STATE_HOME/psql_history"

# Android platform tools
export PATH=$PATH:~/.mine/bin/android

#Rust/Cargo
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export RUSTUP_HOME="$XDG_DATA_HOME"/rustup
export PATH="$PATH:$CARGO_HOME/bin"

# gnupg
export GNUPGHOME="$XDG_DATA_HOME"/gnupg

# Keras
export KERAS_HOME="${XDG_STATE_HOME}/keras"

# Apparix (directory bookmarking)
export APPARIX_HOME="${XDG_CONFIG_HOME}/apparix"

# LM Studio
export LM_STUDIO_API_KEY='xxx'
export LM_STUDIO_API_BASE='http://localhost:1234/v1'

# Node
export NODE_REPL_HISTORY="$XDG_STATE_HOME"/node_repl_history
export NPM_CONFIG_INIT_MODULE="$XDG_CONFIG_HOME"/npm/config/npm-init.js
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME"/npm
export NPM_CONFIG_TMP="$XDG_RUNTIME_DIR"/npm
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME"/npm/npmrc
export TS_NODE_HISTORY="$XDG_STATE_HOME"/ts_node_repl_history

# pnpm
export PNPM_HOME="$XDG_DATA_HOME/pnpm"
export PATH="$PNPM_HOME:$PATH"

#NVM
export NVM_DIR="$HOME/.local/nvm"

# Nuget
export NUGET_PACKAGES="$XDG_CACHE_HOME"/NuGetPackages

# Go
# export PATH=$PATH:~/Projects/go/bin
export GOPATH=$HOME/golang
export GOROOT=/opt/homebrew/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

# Java
export JAVA_HOME=/opt/homebrew/opt/openjdk/

#Go
export GOPATH=$HOME/Projects/go
export PATH=$PATH:$GOROOT/bin

export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker

# Haskell
[ -f "/Users/jd/.local/share/ghcup/env" ] && source "/Users/jd/.local/share/ghcup/env" # ghcup-env

# Dotnet
export PATH="/usr/local/share/dotnet:$PATH"
export PATH="$HOME/.dotnet/tools:$PATH"
export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet

# bun
export BUN_INSTALL="$HOME/.local/bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.mine/bin:$PATH
export PATH=$HOME/.mine/scripts:$PATH
