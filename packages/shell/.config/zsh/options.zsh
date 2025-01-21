#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for interactive shells. It should contain commands
# to set up aliases, functions, options, key bindings, etc.
#
# file location: ${ZDOTDIR}/.zshrc
# load order: .zshenv [.profile], .zshrc [.profile, .aliases [.profile]], .zlogin
################################################################################

# Optimizing zsh:
# https://htr3n.github.io/2018/07/faster-zsh/
# https://blog.mattclemente.com/2020/06/26/oh-my-zsh-slow-to-load/

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"


# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# hosts completion for some commands
# local knownhosts
# knownhosts=( ${${${${(f)"$(<${HOME}/.ssh/known_hosts)"}:#[0-9]*}%%\ *}%%,*} )
# zstyle ':completion:*:(ssh|scp|sftp):*' hosts $knownhosts
compctl -k hosts ftp lftp ncftp ssh w3m lynx links elinks nc telnet rlogin host
compctl -k hosts -P '@' finger

# Uncomment the following line to enable command auto-correction.
export ENABLE_CORRECTION="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# https://github.com/zsh-users/zsh-autosuggestions?tab=readme-ov-file#suggestion-strategy
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Preferred editor for remote sessions
test -n "${SSH_CONNECTION}" && export EDITOR="vi"
# Use code if its installed (both Mac OSX and Linux)
command_exists code && test -z "${EDITOR}" && export EDITOR="code --wait"
# If neither of the above works, then fall back to vi
command_exists vi && test -z "${EDITOR}" && export EDITOR="vi"

# setup paths in the beginning so that all other conditions work correctly
append_to_path_if_dir_exists "${PERSONAL_BIN_DIR}"
append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"

# erlang history in iex
# export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"

if is_macos; then
  # setopt glob_dots                # no special treatment for file names with a leading dot
  # setopt no_auto_menu             # require an extra TAB press to open the completion menu
  # setopt auto_menu                # automatically use menu completion
  # setopt list_beep
  # setopt correct_all              # autocorrect commands
  # setopt always_to_end            # move cursor to end if word had one match

  setopt append_history           # append history list to the history file
  setopt share_history            # share history between different instances of the shell
  setopt inc_append_history       # append command to history file immediately after execution
  setopt extended_history         # save each command's beginning timestamp and the duration to the history file
  setopt hist_ignore_all_dups     # do not put duplicated command into history list
  setopt hist_ignore_dups         # do not store duplications
  setopt hist_allow_clobber
  setopt hist_reduce_blanks       # remove unnecessary blanks
  setopt hist_save_no_dups        # do not save duplicated command
  setopt auto_cd                  # cd into directory if the name is not an alias or function, but matches a directory
  setopt auto_pushd               # make cd push the old directory onto the directory stack
  setopt pushd_silent             # do not print the directory stack after pushd or popd
  setopt pushd_ignore_dups        # don’t push multiple copies of the same directory
  setopt beep                     # beep on error or on completion of long commands
  setopt extended_glob
  setopt auto_list                # automatically list choices on an ambiguous completion.
  setopt list_ambiguous
  setopt list_types               # if the file being listed is a directory, show a trailing slash
  setopt no_case_glob             # case-insensitive globbing
  setopt hist_expire_dups_first   # expire duplicates first
  setopt hist_find_no_dups        # ignore duplicates when searching

  # console colors
  autoload -U colors && colors
fi

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 1

# Set plugin options that are needed before each plugin is loaded
zstyle ':omz:plugins:eza' 'icons' yes
# zstyle ':omz:plugins:eza' 'git-status' yes
# zstyle ':omz:plugins:eza' 'header' yes
zstyle :omz:plugins:iterm2 shell-integration yes


# Show any programs that return non-0
# export PROMPT_COMMAND='ret=$?; if [ $ret -ne 0 ] ; then echo -e "returned \033[01;31m$ret\033[00;00m"; fi'

# Use bat to colorize man pages
command_exists bat && export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# defines word-boundaries: ensures that deleting word on /path/to/file deletes only 'file' and not the directory, this removes the '/' from $WORDCHARS
export WORDCHARS="${WORDCHARS:s#/#}"
export WORDCHARS="${WORDCHARS:s#.#}"

# fzf 
command_exists fzf && source <(fzf --zsh)

# remove empty components to avoid '::' ending up + resulting in './' being in $PATH, etc
path=( "${path[@]:#}" )
fpath=( "${fpath[@]:#}" )
infopath=( "${infopath[@]:#}" )
manpath=( "${manpath[@]:#}" )

# remove duplicates from some env vars
typeset -gU cdpath CPPFLAGS cppflags FPATH fpath infopath LDFLAGS ldflags MANPATH manpath PATH path PKG_CONFIG_PATH



