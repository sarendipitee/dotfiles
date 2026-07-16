[[ -r "$ZDOTDIR/colors.sh" ]] && source "$ZDOTDIR/colors.sh" >/dev/null 2>&1
[[ -r "$ZDOTDIR/functions.sh" ]] && source "$ZDOTDIR/functions.sh" >/dev/null 2>&1
[[ -r "$ZDOTDIR/aliases.sh" ]] && source "$ZDOTDIR/aliases.sh" >/dev/null 2>&1

# Use for machine-local secrets and overrides.
if [[ -d "$PERSONAL_AUTOLOAD_DIR" ]]; then
	for f in "$PERSONAL_AUTOLOAD_DIR"/*(N); do
		[[ -r "$f" ]] && source "$f" >/dev/null 2>&1
	done
fi

if command -v zoxide >/dev/null 2>&1; then
	_zoxide_init="${XDG_CACHE_HOME:-$HOME/.cache}/zoxide-init.zsh"
	if [[ ! -s "$_zoxide_init" || "$_zoxide_init" -ot "$(command -v zoxide)" ]] && mkdir -p "${_zoxide_init:h}" 2>/dev/null; then
		_zoxide_tmp="${_zoxide_init}.tmp.$$"
		if { zoxide init zsh >| "$_zoxide_tmp"; } 2>/dev/null && [[ -s "$_zoxide_tmp" ]]; then
			mv -f "$_zoxide_tmp" "$_zoxide_init" 2>/dev/null || rm -f "$_zoxide_tmp" 2>/dev/null
		else
			rm -f "$_zoxide_tmp" 2>/dev/null
		fi
		unset _zoxide_tmp
	fi
	[[ -r "$_zoxide_init" ]] && source "$_zoxide_init" >/dev/null 2>&1
fi

[[ -r "$ZDOTDIR/completions-opts.zsh" ]] && source "$ZDOTDIR/completions-opts.zsh" >/dev/null 2>&1
[[ -r "$ZDOTDIR/options.zsh" ]] && source "$ZDOTDIR/options.zsh" >/dev/null 2>&1

# Local completions (must be before compinit, which runs inside .zsh_plugins.zsh)
fpath=( "$ZDOTDIR/completions" $fpath )

# Antidote plugin manager (static loading for speed)
[[ -r "$ZDOTDIR/antidote/antidote.zsh" ]] && source "$ZDOTDIR/antidote/antidote.zsh" >/dev/null 2>&1

export ANTIDOTE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/antidote"
export ZSH="$ANTIDOTE_HOME/github.com/ohmyzsh/ohmyzsh"

zsh_plugins=${ZDOTDIR:-$HOME/.config/zsh}/.zsh_plugins
if (( $+functions[antidote] )) && [[ -r ${zsh_plugins}.txt ]] && [[ ! -s ${zsh_plugins}.zsh || ${zsh_plugins}.zsh -ot ${zsh_plugins}.txt ]] && mkdir -p "${zsh_plugins:h}" 2>/dev/null; then
  _zsh_plugins_tmp="${zsh_plugins}.zsh.tmp.$$"
  if { antidote bundle <${zsh_plugins}.txt >! "$_zsh_plugins_tmp"; } 2>/dev/null && [[ -s "$_zsh_plugins_tmp" ]]; then
    mv -f "$_zsh_plugins_tmp" "${zsh_plugins}.zsh" 2>/dev/null || rm -f "$_zsh_plugins_tmp" 2>/dev/null
  else
    rm -f "$_zsh_plugins_tmp" 2>/dev/null
  fi
  unset _zsh_plugins_tmp
fi
if [[ -o interactive && -t 0 && -t 1 && -s "${zsh_plugins}.zsh" && -r "${zsh_plugins}.zsh" ]]; then
  source "${zsh_plugins}.zsh" >/dev/null 2>&1
fi

# Load fzf key bindings/widgets AFTER oh-my-zsh so they override OMZ's
# history-incremental-search-backward on ^R (and ^T / ALT-C).
if [[ -o interactive && -t 0 && -t 1 ]] && command -v fzf >/dev/null 2>&1; then
  _fzf_init="${XDG_CACHE_HOME:-$HOME/.cache}/fzf-init.zsh"
  if [[ ! -s "$_fzf_init" || "$_fzf_init" -ot "$(command -v fzf)" ]] && mkdir -p "${_fzf_init:h}" 2>/dev/null; then
    _fzf_tmp="${_fzf_init}.tmp.$$"
    if { fzf --zsh >| "$_fzf_tmp"; } 2>/dev/null && [[ -s "$_fzf_tmp" ]]; then
      mv -f "$_fzf_tmp" "$_fzf_init" 2>/dev/null || rm -f "$_fzf_tmp" 2>/dev/null
    else
      rm -f "$_fzf_tmp" 2>/dev/null
    fi
    unset _fzf_tmp
  fi
  [[ -r "$_fzf_init" ]] && source "$_fzf_init" >/dev/null 2>&1
fi

# Remote session indicator (SSH nesting badge for prompt)
if [[ -n "$DOTFILES_DIR" && -r "$DOTFILES_DIR/packages/shell/.config/zsh/prompt-remote.zsh" ]]; then
  source "$DOTFILES_DIR/packages/shell/.config/zsh/prompt-remote.zsh" >/dev/null 2>&1
fi

# Unalias Oh My Zsh git aliases that conflict with tools
unalias gc 2>/dev/null

# Apply paths after everything so we get last say of $PATH
# (path_helper in /etc/zprofile runs after .zshenv and can reorder PATH)

# Re-apply user path precedence here after all other scripts have run
# Things I build myself go in here, overrides all other paths
export PATH=$HOME/.local/bin:$HOME/.my/bin:$HOME/.my/scripts:$PATH

# Direnv integration
export DIRENV_LIB_PATH="${HOME}/.config/direnv/lib"

if [[ -o interactive && -t 0 && -t 1 ]] && command -v direnv >/dev/null 2>&1; then
	_direnv_hook="${XDG_CACHE_HOME:-$HOME/.cache}/direnv-hook.zsh"
	if [[ ! -s "$_direnv_hook" || "$_direnv_hook" -ot "$(command -v direnv)" ]] && mkdir -p "${_direnv_hook:h}" 2>/dev/null; then
		_direnv_tmp="${_direnv_hook}.tmp.$$"
		if { direnv hook zsh >| "$_direnv_tmp"; } 2>/dev/null && [[ -s "$_direnv_tmp" ]]; then
			mv -f "$_direnv_tmp" "$_direnv_hook" 2>/dev/null || rm -f "$_direnv_tmp" 2>/dev/null
		else
			rm -f "$_direnv_tmp" 2>/dev/null
		fi
		unset _direnv_tmp
	fi
	[[ -r "$_direnv_hook" ]] && source "$_direnv_hook" >/dev/null 2>&1
fi

# Remove duplicate PATH entries while preserving system paths needed by prompt plugins.
typeset -U path PATH

# GPG agent TTY sync
export GPG_TTY=$TTY
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

# zprof
