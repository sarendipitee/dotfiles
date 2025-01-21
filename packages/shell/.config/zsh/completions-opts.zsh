#!/usr/bin/env zsh


# manpage completion
man_glob() {
	local a
	read -cA a
	if [[ $a[2] = -s ]]; then
		reply=( ${^manpath}/man$a[3]/${1}*${2}(N:t:r) )
	else
		reply=( ${^manpath}/man*/${1}*${2}(N:t:r) )
	fi
}

compctl -K man_glob -x 'C[-1,-P]' -m - 'R[-*l*,;]' -g '*.(man|[0-9nlpo](|[a-z]))' + -g '*(-/)' -- man

# Turn on autocomplete predictions
autoload -U incremental-complete-word predict-on
zle -N incremental-complete-word
zle -N predict-on
zle -N predict-off
bindkey '^Xi' incremental-complete-word
bindkey '^Xp' predict-on
bindkey '^X^P' predict-off


zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# colorize completion
# zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#)*=$color[cyan]=$color[red]"
# zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
# case insensitive path-completion
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'
# partial completion suggestions
zstyle ':completion:*' list-suffixeszstyle ':completion:*' expand prefix suffix
# prevent CVS and SVN from being completed
zstyle ':completion:*:(all-|)files' ignored-patterns '(|*/)CVS'
zstyle ':completion:*:cd:*' ignored-patterns '(*/)#CVS'
# ignore completion functions
zstyle ':completion:*:functions' ignored-patterns '_*'
# ignore what's already selected on line
zstyle ':completion:*:(rm|kill|diff):*' ignore-line yes

# fuzzy matching
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric
# completion cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zsh"
# remove trailing slash in directory names, useful for ln
zstyle ':completion:*' squeeze-slashes true
# docker completion
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# Use modern completion system (needs to be run AFTER some zstyle defns; usually a good idea to do so after all of them)
autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"
