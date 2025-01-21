#!/usr/bin/env zsh

antigen use oh-my-zsh

antigen theme agnoster

# Bundles from the default repo (robbyrussell's oh-my-zsh)
antigen bundle brew
antigen bundle eza
antigen bundle fast-syntax-highlighting
antigen bundle git
antigen bundle git-extras
antigen bundle iterm2
antigen bundle last-working-dir
antigen bundle nvm
antigen bundle npm
antigen bundle safe-paste
antigen bundle sudo
antigen bundle vi-mode
antigen bundle zbell
antigen bundle zsh-autosuggestions
antigen bundle zsh-autocomplete
antigen bundle fzf

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting

# Extra zsh completions
antigen bundle zsh-users/zsh-completions

antigen apply

