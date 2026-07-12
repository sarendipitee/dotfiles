typeset -U path PATH

if [[ -n ${FLOX_ENV-} ]]; then
	path=(${path:#*/packages/flox/*})
	path=(${path:#/pkg/env/*})
	path=(${path:#/nix/store/*})
	for _flox_var in ${(k)parameters[(I)FLOX_*]}; do
		unset "$_flox_var"
	done
	unset _flox_var
fi

path=(
	"$HOME/.local/bin"
	"$HOME/.my/bin"
	"$HOME/.my/scripts"
	"$XDG_DATA_HOME/mise/shims"
	"$PNPM_HOME/bin"
	"$NPM_CONFIG_PREFIX/bin"
	"$CARGO_HOME/bin"
	"$HOME/Projects/go/bin"
	"$KREW_ROOT/bin"
	"$BUN_INSTALL/bin"
	/opt/homebrew/bin
	/opt/homebrew/sbin
	/home/linuxbrew/.linuxbrew/bin
	/home/linuxbrew/.linuxbrew/sbin
	/usr/local/MacGPG2/bin
	/usr/local/bin
	/usr/bin
	/bin
	/usr/sbin
	/sbin
	$path
)

[ -f "$XDG_DATA_HOME/ghcup/env" ] && source "$XDG_DATA_HOME/ghcup/env"
