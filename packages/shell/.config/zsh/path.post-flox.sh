# Tool-specific environment derived after Flox activation.

# Rust/Cargo
if command -v rustc >/dev/null 2>&1; then
	_rust_sysroot="$(rustc --print sysroot 2>/dev/null)"
	if [ -d "${_rust_sysroot}/lib/rustlib/src/rust/src" ]; then
		export RUST_SRC_PATH="${_rust_sysroot}/lib/rustlib/src/rust/src"
	fi
	unset _rust_sysroot
fi

# Go
if command -v go >/dev/null 2>&1; then
	_go_root="$(go env GOROOT 2>/dev/null)"
	[ -n "$_go_root" ] && export GOROOT="$_go_root"
	unset _go_root
elif [ -d /opt/homebrew/opt/go/libexec ]; then
	export GOROOT=/opt/homebrew/opt/go/libexec
fi
if [ -n "${GOROOT:-}" ] && [[ ":$PATH:" != *":$GOROOT/bin:"* ]]; then
	export PATH=$PATH:$GOROOT/bin
fi
