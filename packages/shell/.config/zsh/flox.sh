# Flox environments to activate.

_delete_invalid_flox_compdump() {
	local flox_env_dir="${1}"
	local flox_compdump="${flox_env_dir}/.flox/cache/.zcompdump"
	local flox_header

	[ ! -f "${flox_compdump}" ] && return

	IFS= read -r flox_header < "${flox_compdump}"
	[[ "${flox_header}" == '#files:'* ]] && return

	rm -f "${flox_compdump}"
}

_FLOX_ENVS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/flox/active-envs"
if [ -f "$_FLOX_ENVS_FILE" ]; then
	while IFS= read -r _flox_env || [ -n "$_flox_env" ]; do
		case "$_flox_env" in '' | \#*) continue ;; esac
		_flox_env_dir="$DOTFILES_DIR/packages/flox/${_flox_env}"
		_delete_invalid_flox_compdump "$_flox_env_dir"
		eval "$(flox activate -d "$_flox_env_dir" -m run)"
	done <"$_FLOX_ENVS_FILE"
	unset _flox_env _flox_env_dir
else
	_delete_invalid_flox_compdump "$DOTFILES_DIR/packages/flox/envs/global"
	eval "$(flox activate -d "$DOTFILES_DIR/packages/flox/envs/global" -m run)"
fi
unset _FLOX_ENVS_FILE
unset -f _delete_invalid_flox_compdump

PS1="$FLOX_SAVE_ZSH_PS1"
