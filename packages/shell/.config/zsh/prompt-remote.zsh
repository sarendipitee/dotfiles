# SSH-aware prompt context colors for agnoster
# Uses magenta background when SSH'd in instead of default black

: ${AGNOSTER_CONTEXT_SSH_BG:=magenta}
: ${AGNOSTER_CONTEXT_SSH_FG:=black}

prompt_context() {
  if [[ "$USERNAME" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    local bg=$AGNOSTER_CONTEXT_BG
    local fg=$AGNOSTER_CONTEXT_FG
    if [[ -n "$SSH_CONNECTION" ]]; then
      bg=$AGNOSTER_CONTEXT_SSH_BG
      fg=$AGNOSTER_CONTEXT_SSH_FG
    fi
    prompt_segment "$bg" "$fg" "%(!.%{%F{$AGNOSTER_STATUS_ROOT_FG}%}.)%n@%m"
  fi
}

# Two-line prompt: info segments on line 1, prompt char on line 2
PROMPT='%{%f%b%k%}$(build_prompt)
%(!.%{%F{red}%}#.%{%F{green}%}❯%{%f%}) '
