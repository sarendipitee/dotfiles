#!/usr/bin/env bash

set -Eeo pipefail

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
DOTFILES_DIR=$(realpath "${SCRIPT_DIR}/..")
OS=$(uname -s)
LOGIN_USER="${SUDO_USER:-$(id -un)}"
SUDO_KEEPALIVE_PID=
REBOOT_REQUIRED=false
RELOGIN_REQUIRED=false

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

fatal() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

migrate_legacy_codex_auth() {
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"

	[ "$OS" = Linux ] || return 0
	[ "$(current_process_compose_profile)" = aorus ] || return 0
	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	login_uid=$(id -u "$LOGIN_USER")
	[ "$(id -u)" = "$login_uid" ] && [ "$(id -un)" = "$LOGIN_USER" ] ||
		fatal 'Codex auth migration must run as login user, not through a root shell'

	if ! "$mise_bin" exec -- python - "$DOTFILES_DIR" "$HOME" "$login_uid" <<'PY'
import errno
import hmac
import os
import secrets
import stat
import sys

dotfiles_directory, home_directory, uid_text = sys.argv[1:]
expected_uid = int(uid_text)
source_path = os.path.join(dotfiles_directory, "packages", "ai", ".codex", "auth.json")
canonical_directory_path = os.path.join(home_directory, ".codex")
canonical_path = os.path.join(canonical_directory_path, "auth.json")


def fail(message):
    raise SystemExit(message)


def validate_path(root, path, purpose):
    for value in (root, path):
        if not os.path.isabs(value) or value != os.path.normpath(value):
            fail(f"{purpose} path is not absolute and normalized")
        if any(ord(character) < 32 or ord(character) == 127 for character in value):
            fail(f"{purpose} path contains control characters")
    try:
        if os.path.commonpath((root, path)) != root:
            fail(f"{purpose} path escapes expected root")
    except ValueError:
        fail(f"{purpose} path is invalid")


validate_path(dotfiles_directory, source_path, "historical Codex auth")
validate_path(home_directory, canonical_path, "canonical Codex auth")
if not hasattr(os, "O_NOFOLLOW"):
    fail("platform cannot reject credential symlinks")

directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
file_flags = os.O_RDONLY | os.O_NOFOLLOW


def open_absolute_directory(path, purpose):
    descriptor = os.open("/", directory_flags)
    try:
        for component in path.split(os.sep)[1:]:
            if component in ("", ".", ".."):
                fail(f"{purpose} contains invalid path component")
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=descriptor)
            except OSError:
                fail(f"{purpose} contains unsafe or missing directory")
            os.close(descriptor)
            descriptor = next_descriptor
            metadata = os.fstat(descriptor)
            if not stat.S_ISDIR(metadata.st_mode):
                fail(f"{purpose} contains non-directory component")
            if metadata.st_uid not in (0, expected_uid):
                fail(f"{purpose} contains directory owned by another user")
            if metadata.st_mode & 0o022:
                fail(f"{purpose} contains group- or world-writable ancestor")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def open_optional_directory(parent_descriptor, name, purpose):
    try:
        descriptor = os.open(name, directory_flags, dir_fd=parent_descriptor)
    except FileNotFoundError:
        return None
    except OSError:
        fail(f"{purpose} is not a safe directory")
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != expected_uid:
        os.close(descriptor)
        fail(f"{purpose} is not owned directory")
    return descriptor


def open_optional_auth(directory_descriptor, name, purpose, expected_links=(1,)):
    if isinstance(expected_links, int):
        expected_links = (expected_links,)
    try:
        descriptor = os.open(name, file_flags, dir_fd=directory_descriptor)
    except FileNotFoundError:
        return None
    except OSError:
        fail(f"{purpose} is not safe regular file")
    metadata = os.fstat(descriptor)
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != expected_uid or
            metadata.st_nlink not in expected_links or stat.S_IMODE(metadata.st_mode) != 0o600):
        os.close(descriptor)
        fail(f"{purpose} must be login-user-owned regular file with mode 0600 and one link")
    return descriptor


def descriptors_equal(left_descriptor, right_descriptor):
    left_metadata = os.fstat(left_descriptor)
    right_metadata = os.fstat(right_descriptor)
    if left_metadata.st_size != right_metadata.st_size:
        return False
    offset = 0
    while offset < left_metadata.st_size:
        length = min(1024 * 1024, left_metadata.st_size - offset)
        left = os.pread(left_descriptor, length, offset)
        right = os.pread(right_descriptor, length, offset)
        if not hmac.compare_digest(left, right):
            return False
        if not left:
            fail("credential changed while being compared")
        offset += len(left)
    return True


def path_matches_descriptor(directory_descriptor, name, descriptor, purpose, links=1):
    try:
        path_metadata = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
    except OSError:
        fail(f"{purpose} changed during migration")
    metadata = os.fstat(descriptor)
    if ((path_metadata.st_dev, path_metadata.st_ino) != (metadata.st_dev, metadata.st_ino) or
            not stat.S_ISREG(path_metadata.st_mode) or path_metadata.st_uid != expected_uid or
            path_metadata.st_nlink != links or stat.S_IMODE(path_metadata.st_mode) != 0o600):
        fail(f"{purpose} changed during migration")


source_parent = open_absolute_directory(os.path.dirname(source_path), "historical Codex auth path")
home_descriptor = open_absolute_directory(home_directory, "home directory")
canonical_directory = open_optional_directory(home_descriptor, ".codex", "canonical Codex directory")
if canonical_directory is not None:
    os.fchmod(canonical_directory, 0o700)
    os.fsync(canonical_directory)
source_descriptor = open_optional_auth(
    source_parent, "auth.json", "historical Codex auth", (1, 2))
canonical_descriptor = None
if canonical_directory is not None:
    canonical_descriptor = open_optional_auth(
        canonical_directory, "auth.json", "canonical Codex auth", (1, 2))

try:
    source_links = os.fstat(source_descriptor).st_nlink if source_descriptor is not None else None
    canonical_links = (
        os.fstat(canonical_descriptor).st_nlink if canonical_descriptor is not None else None)
    interrupted_link = False
    if source_links == 2 or canonical_links == 2:
        if source_descriptor is None or canonical_descriptor is None:
            fail("Codex credential has unexpected additional hard link")
        source_metadata = os.fstat(source_descriptor)
        canonical_metadata = os.fstat(canonical_descriptor)
        interrupted_link = (
            source_links == 2 and canonical_links == 2 and
            (source_metadata.st_dev, source_metadata.st_ino) ==
            (canonical_metadata.st_dev, canonical_metadata.st_ino))
        if not interrupted_link:
            fail("Codex credential has unexpected additional hard link")

    if source_descriptor is None and canonical_descriptor is None:
        raise SystemExit(0)

    if canonical_descriptor is not None:
        path_matches_descriptor(canonical_directory, "auth.json", canonical_descriptor,
                                "canonical Codex auth", 2 if interrupted_link else 1)
        if source_descriptor is not None:
            if not descriptors_equal(source_descriptor, canonical_descriptor):
                fail("historical and canonical Codex credentials differ; refusing to overwrite either")
            path_matches_descriptor(source_parent, "auth.json", source_descriptor,
                                    "historical Codex auth", 2 if interrupted_link else 1)
            path_matches_descriptor(canonical_directory, "auth.json", canonical_descriptor,
                                    "canonical Codex auth", 2 if interrupted_link else 1)
            os.fsync(canonical_descriptor)
        os.fchmod(canonical_directory, 0o700)
        os.fsync(canonical_directory)
        if source_descriptor is not None:
            path_matches_descriptor(source_parent, "auth.json", source_descriptor,
                                    "historical Codex auth", 2 if interrupted_link else 1)
            path_matches_descriptor(canonical_directory, "auth.json", canonical_descriptor,
                                    "canonical Codex auth", 2 if interrupted_link else 1)
            os.unlink("auth.json", dir_fd=source_parent)
            os.fsync(source_parent)
            path_matches_descriptor(canonical_directory, "auth.json", canonical_descriptor,
                                    "canonical Codex auth")
        raise SystemExit(0)

    if canonical_directory is None:
        try:
            os.mkdir(".codex", 0o700, dir_fd=home_descriptor)
            os.fsync(home_descriptor)
        except FileExistsError:
            pass
        canonical_directory = open_optional_directory(
            home_descriptor, ".codex", "canonical Codex directory")
        if canonical_directory is None:
            fail("could not create canonical Codex directory")

    os.fchmod(canonical_directory, 0o700)
    try:
        os.stat("auth.json", dir_fd=canonical_directory, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        fail("canonical Codex credential appeared during migration")
    path_matches_descriptor(source_parent, "auth.json", source_descriptor,
                            "historical Codex auth")

    try:
        os.link("auth.json", "auth.json", src_dir_fd=source_parent,
                dst_dir_fd=canonical_directory, follow_symlinks=False)
        os.fsync(canonical_directory)
        linked_descriptor = os.open("auth.json", file_flags, dir_fd=canonical_directory)
        try:
            linked_metadata = os.fstat(linked_descriptor)
            source_metadata = os.fstat(source_descriptor)
            if ((linked_metadata.st_dev, linked_metadata.st_ino) !=
                    (source_metadata.st_dev, source_metadata.st_ino) or
                    linked_metadata.st_nlink != 2 or not descriptors_equal(
                        source_descriptor, linked_descriptor)):
                fail("could not verify linked canonical Codex credential")
            os.fsync(linked_descriptor)
        finally:
            os.close(linked_descriptor)
    except OSError as error:
        if error.errno != errno.EXDEV:
            fail("could not atomically install canonical Codex credential")
        temporary_name = f".auth.json.{os.getpid()}.{secrets.token_hex(8)}.tmp"
        temporary_descriptor = None
        try:
            temporary_descriptor = os.open(
                temporary_name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=canonical_directory,
            )
            offset = 0
            while True:
                chunk = os.pread(source_descriptor, 1024 * 1024, offset)
                if not chunk:
                    break
                view = memoryview(chunk)
                while view:
                    written = os.write(temporary_descriptor, view)
                    view = view[written:]
                offset += len(chunk)
            os.fchmod(temporary_descriptor, 0o600)
            os.fsync(temporary_descriptor)
            os.link(temporary_name, "auth.json", src_dir_fd=canonical_directory,
                    dst_dir_fd=canonical_directory, follow_symlinks=False)
            os.fsync(canonical_directory)
            os.unlink(temporary_name, dir_fd=canonical_directory)
            temporary_name = None
            os.fsync(canonical_directory)
        finally:
            if temporary_descriptor is not None:
                os.close(temporary_descriptor)
            if temporary_name is not None:
                try:
                    os.unlink(temporary_name, dir_fd=canonical_directory)
                except FileNotFoundError:
                    pass

    source_links = os.fstat(source_descriptor).st_nlink
    installed_descriptor = open_optional_auth(
        canonical_directory, "auth.json", "canonical Codex auth", source_links)
    if installed_descriptor is None:
        fail("canonical Codex credential disappeared after installation")
    try:
        if not descriptors_equal(source_descriptor, installed_descriptor):
            fail("canonical Codex credential failed verification")
        os.fsync(installed_descriptor)
        path_matches_descriptor(source_parent, "auth.json", source_descriptor,
                                "historical Codex auth",
                                2 if os.fstat(source_descriptor).st_nlink == 2 else 1)
        path_matches_descriptor(canonical_directory, "auth.json", installed_descriptor,
                                "canonical Codex auth",
                                os.fstat(installed_descriptor).st_nlink)
        os.unlink("auth.json", dir_fd=source_parent)
        os.fsync(source_parent)
        path_matches_descriptor(canonical_directory, "auth.json", installed_descriptor,
                                "canonical Codex auth")
        os.fsync(canonical_directory)
    finally:
        os.close(installed_descriptor)
finally:
    if canonical_descriptor is not None:
        os.close(canonical_descriptor)
    if source_descriptor is not None:
        os.close(source_descriptor)
    if canonical_directory is not None:
        os.close(canonical_directory)
    os.close(home_descriptor)
    os.close(source_parent)
PY
	then
		fatal 'Could not securely migrate historical Codex authentication'
	fi
}

verify_aorus_codex_login() {
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"

	[ "$OS" = Linux ] || return 0
	[ "$(current_process_compose_profile)" = aorus ] || return 0
	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	login_uid=$(id -u "$LOGIN_USER")
	[ "$(id -u)" = "$login_uid" ] && [ "$(id -un)" = "$LOGIN_USER" ] ||
		fatal 'Codex login preflight must run as login user, not through a root shell'
	if ! "$mise_bin" exec -- codex login status >/dev/null 2>&1; then
		fatal 'Codex login is required on Aorus. Run mise exec -- codex login, then rerun provisioning'
	fi
}

cleanup() {
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	fi
}

keep_sudo_alive() {
	sudo -v
	(
		while kill -0 "$$" 2>/dev/null; do
			sleep 50
			sudo -n true || exit
		done
	) 2>/dev/null &
	SUDO_KEEPALIVE_PID=$!
}

has_nvidia_gpu() {
	local device vendor class
	for device in /sys/bus/pci/devices/*; do
		if [ ! -r "$device/vendor" ] || [ ! -r "$device/class" ]; then
			continue
		fi
		read -r vendor < "$device/vendor"
		read -r class < "$device/class"
		[ "$vendor" = 0x10de ] && [[ "$class" == 0x03* ]] && return 0
	done
	return 1
}

set_ssh_permissions() {
	local ssh_dir="$HOME/.ssh"
	mkdir -p "$ssh_dir"
	chmod 700 "$ssh_dir"
	find "$ssh_dir" -type d -exec chmod 700 {} +
	find "$ssh_dir" -type f -exec chmod 600 {} +
	find "$ssh_dir" -type f \( -name '*.pub' -o -name known_hosts -o -name known_hosts.old \) -exec chmod 644 {} +
}

setup_user_state() {
	mkdir -p \
		"$XDG_CACHE_HOME/zsh" \
		"$XDG_CONFIG_HOME" \
		"$XDG_DATA_HOME" \
		"$XDG_STATE_HOME/zsh"
	touch "$XDG_STATE_HOME/zsh/history"
	set_ssh_permissions
}

path_owner_uid() {
	local path="$1"
	local owner_uid
	if owner_uid=$(stat -f '%u' "$path" 2>/dev/null); then
		printf '%s\n' "$owner_uid"
	else
		stat -c '%u' "$path"
	fi
}

path_mode() {
	local path="$1"
	local mode
	if mode=$(stat -f '%Lp' "$path" 2>/dev/null); then
		printf '%s\n' "$mode"
	else
		stat -c '%a' "$path"
	fi
}

converge_path_directories() {
	local mise_bin="$1"
	local expected_home="$2"
	local login_uid="$3"
	local path="$4"
	local purpose="$5"

	if ! "$mise_bin" exec -- python - "$expected_home" "$login_uid" "$path" "$purpose" <<'PY'
import os
import stat
import sys

expected_home, uid_text, path, purpose = sys.argv[1:]
user_uid = int(uid_text)

def fail(message):
    raise SystemExit(f"{purpose} {message}")

for name, value in (("expected home", expected_home), ("path", path)):
    if not os.path.isabs(value):
        fail(f"{name} must be absolute")
    if value != os.path.normpath(value):
        fail(f"{name} must be normalized")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        fail(f"{name} contains control characters")

try:
    if os.path.commonpath((expected_home, path)) != expected_home:
        fail("escapes expected home")
except ValueError:
    fail("is not under expected home")

flags = os.O_RDONLY | os.O_DIRECTORY
if not hasattr(os, "O_NOFOLLOW"):
    fail("cannot reject symlinks on this platform")
flags |= os.O_NOFOLLOW

current_fd = os.open("/", flags)
try:
    for component in path.split(os.sep)[1:]:
        if component in ("", ".", ".."):
            fail("contains an invalid path component")
        try:
            next_fd = os.open(component, flags, dir_fd=current_fd)
        except OSError as error:
            fail(f"contains an unsafe or missing directory: {error.strerror}")
        os.close(current_fd)
        current_fd = next_fd

        metadata = os.fstat(current_fd)
        if not stat.S_ISDIR(metadata.st_mode):
            fail("contains a non-directory component")
        if metadata.st_uid not in (0, user_uid):
            fail("contains a directory owned by another user")
        if metadata.st_mode & 0o022:
            if metadata.st_uid != user_uid:
                fail("contains a writable directory not owned by login user")
            os.fchmod(current_fd, stat.S_IMODE(metadata.st_mode) & ~0o022)
            metadata = os.fstat(current_fd)
        if metadata.st_uid not in (0, user_uid) or metadata.st_mode & 0o022:
            fail("remains writable or changed during convergence")
finally:
    os.close(current_fd)
PY
	then
		fatal "Could not securely converge $purpose"
	fi
}

omniroute_binding_works() {
	local mise_bin="$1"
	local package_dir="$2"
	"$mise_bin" exec -- node - "$package_dir" >/dev/null 2>&1 <<'NODE'
const { createRequire } = require("node:module");
const { join } = require("node:path");
const packageDir = process.argv[2];
const requireFromDist = createRequire(join(packageDir, "dist", "package.json"));
try {
  requireFromDist.resolve("better-sqlite3/build/Release/better_sqlite3.node");
} catch {
  process.exit(10);
}
try {
  const Database = requireFromDist("better-sqlite3");
  const database = new Database(":memory:");
  database.close();
} catch {
  process.exit(11);
}
NODE
}

migrate_legacy_omniroute_state() {
	local durable_dir="$XDG_STATE_HOME/omniroute"
	local fuser_status
	local install_dir
	local legacy_dir="$HOME/.omniroute"
	local legacy_load_state
	local mise_bin="$HOME/.local/bin/mise"
	local package_dir
	local package_env
	local legacy_database_paths=(
		"$legacy_dir/storage.sqlite"
		"$legacy_dir/storage.sqlite-wal"
		"$legacy_dir/storage.sqlite-shm"
	)
	local user_systemctl=(systemctl --user)
	local unit

	[ "$OS" = Linux ] || return 0
	[ "$(current_process_compose_profile)" = aorus ] || return 0
	if [ ! -e "$legacy_dir" ] && [ ! -L "$legacy_dir" ]; then
		return 0
	fi
	if ! python3 - "$HOME" "$XDG_STATE_HOME" <<'PY'
import os
import stat
import sys

home, state_home = sys.argv[1:]


def fail(message):
    raise SystemExit(message)


def validate_home_path(path, purpose):
    if not os.path.isabs(path) or path != os.path.normpath(path):
        fail(f"{purpose} is not an absolute normalized path")
    if any(ord(character) < 32 or ord(character) == 127 for character in path):
        fail(f"{purpose} contains control characters")
    try:
        if os.path.commonpath((home, path)) != home:
            fail(f"{purpose} escapes login home")
    except ValueError:
        fail(f"{purpose} escapes login home")


def lstat_under_home(path, purpose):
    validate_home_path(path, purpose)
    current = home
    components = os.path.relpath(path, home).split(os.sep)
    for index, component in enumerate(components):
        current = os.path.join(current, component)
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            return None
        except OSError:
            fail(f"could not safely inspect {purpose}")
        if index != len(components) - 1 and not stat.S_ISDIR(metadata.st_mode):
            fail(f"{purpose} contains a symlink or non-directory path component")
    return metadata


validate_home_path(home, "login home")
validate_home_path(state_home, "XDG_STATE_HOME")
try:
    home_metadata = os.lstat(home)
except OSError:
    fail("login home could not be safely inspected")
if not stat.S_ISDIR(home_metadata.st_mode):
    fail("login home is not a safe directory")

legacy_database = os.path.join(home, ".omniroute", "storage.sqlite")
durable_directory = os.path.join(state_home, "omniroute")
durable_database = os.path.join(durable_directory, "storage.sqlite")
marker = os.path.join(durable_directory, ".dotfiles-legacy-migration-v1")
legacy_metadata = lstat_under_home(legacy_database, "legacy OmniRoute database")
durable_metadata = lstat_under_home(durable_database, "durable OmniRoute database")
marker_metadata = lstat_under_home(marker, "OmniRoute migration marker")
if marker_metadata is not None and not stat.S_ISREG(marker_metadata.st_mode):
    fail("OmniRoute migration marker is unsafe")
PY
	then
		fatal 'Could not safely authorize legacy OmniRoute state migration'
	fi
	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	login_uid=$(id -u "$LOGIN_USER")
	[ "$login_uid" != 0 ] || fatal 'OmniRoute migration refuses root as login user'
	[ "$(id -u)" = "$login_uid" ] && [ "$(id -un)" = "$LOGIN_USER" ] ||
		fatal 'OmniRoute migration must run as login user, not through a root shell'
	command_exists pgrep ||
		fatal 'OmniRoute migration requires pgrep from procps; install it and retry'
	command_exists fuser ||
		fatal 'OmniRoute migration requires fuser from psmisc to verify database file holders; install it and retry'
	if [ "$(id -un)" != "$LOGIN_USER" ]; then
		user_systemctl=(
			sudo -u "$LOGIN_USER" env
			"XDG_RUNTIME_DIR=/run/user/$login_uid"
			"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
			systemctl --user
		)
	fi

	for unit in dotfiles-process-compose.service omniroute.service; do
		legacy_load_state=$("${user_systemctl[@]}" show --property=LoadState --value "$unit" 2>/dev/null) ||
			fatal "Could not inspect OmniRoute service before migration: $unit"
		[ "$legacy_load_state" = not-found ] && continue
		[ -n "$legacy_load_state" ] || fatal "OmniRoute service returned an empty load state: $unit"
		"${user_systemctl[@]}" stop "$unit" || fatal "Could not stop OmniRoute service before migration: $unit"
		! "${user_systemctl[@]}" is-active --quiet "$unit" ||
			fatal "OmniRoute service remains active before migration: $unit"
	done
	if pgrep -u "$login_uid" -f '[o]mniroute' >/dev/null; then
		fatal 'An OmniRoute process remains active outside managed services'
	fi

	install_dir=$("$mise_bin" where npm:omniroute) ||
		fatal 'Could not resolve OmniRoute installation for migration'
	case "$install_dir" in
		/*) ;;
		*) fatal 'Mise returned an invalid OmniRoute installation path for migration' ;;
	esac
	[[ "$install_dir" != *$'\n'* ]] || fatal 'Mise returned multiple OmniRoute installation paths for migration'
	package_dir="$install_dir/lib/node_modules/omniroute"
	package_env="$package_dir/.env"

	case "$XDG_STATE_HOME" in
		/*) ;;
		*) fatal 'XDG_STATE_HOME must be an absolute path' ;;
	esac
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$legacy_dir" \
		'Legacy OmniRoute path'
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$XDG_STATE_HOME" \
		'XDG_STATE_HOME path'
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$package_dir" \
		'OmniRoute package path'

	if fuser -- "${legacy_database_paths[@]}" >/dev/null 2>&1; then
		fuser_status=0
	else
		fuser_status=$?
	fi
	case "$fuser_status" in
		0) fatal 'An open file holder remains on legacy OmniRoute database files' ;;
		1) ;;
		*) fatal 'Could not verify legacy OmniRoute database file holders with fuser' ;;
	esac

	if ! "$mise_bin" exec -- python - \
		"$HOME" "$login_uid" "$legacy_dir" "$durable_dir" "$package_env" <<'PY'
import ctypes
import errno
import os
import re
import sqlite3
import stat
import subprocess
import sys

home, uid_text, legacy_path, destination_path, package_env_path = sys.argv[1:]
expected_uid = int(uid_text)
marker_name = ".dotfiles-legacy-migration-v1"
marker_content = b"dotfiles-omniroute-legacy-migration-v1\n"
parent_path = os.path.dirname(destination_path)
backup_path = destination_path + ".pre-legacy-migration-v1"
temporary_path = os.path.join(parent_path, ".omniroute.legacy-migration-v1.tmp")
assignment_pattern = re.compile(r"^(?:export +)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
storage_key_pattern = re.compile(r"^[0-9A-Fa-f]{64}$")


def fail(message):
    raise SystemExit(message)


def validate_absolute_home_path(path, purpose):
    if not os.path.isabs(path) or path != os.path.normpath(path):
        fail(f"{purpose} is not an absolute normalized path")
    if any(ord(character) < 32 or ord(character) == 127 for character in path):
        fail(f"{purpose} contains control characters")
    try:
        if os.path.commonpath((home, path)) != home:
            fail(f"{purpose} escapes login home")
    except ValueError:
        fail(f"{purpose} escapes login home")


def directory_flags():
    if not hasattr(os, "O_NOFOLLOW"):
        fail("platform cannot reject symlinks during OmniRoute migration")
    return os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def open_owned_directory(path, purpose):
    try:
        descriptor = os.open(path, directory_flags())
    except OSError:
        fail(f"{purpose} is not a safe directory")
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != expected_uid:
        os.close(descriptor)
        fail(f"{purpose} is not owned by login user")
    os.fchmod(descriptor, 0o700)
    return descriptor


def inspect_owned_directory(path, purpose):
    try:
        descriptor = os.open(path, directory_flags())
    except OSError:
        fail(f"{purpose} is not a safe directory")
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != expected_uid:
        os.close(descriptor)
        fail(f"{purpose} is not owned by login user")
    return descriptor


def open_owned_regular_at(parent_fd, name, purpose):
    flags = os.O_RDONLY | os.O_NOFOLLOW
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError:
        fail(f"{purpose} is not a safe regular file")
    metadata = os.fstat(descriptor)
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != expected_uid or
            metadata.st_nlink != 1):
        os.close(descriptor)
        fail(f"{purpose} is not a singly linked file owned by login user")
    os.fchmod(descriptor, 0o600)
    return descriptor, metadata


def read_regular_at(parent_fd, name, purpose):
    descriptor, before = open_owned_regular_at(parent_fd, name, purpose)
    try:
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity = ("st_dev", "st_ino", "st_uid", "st_nlink", "st_size", "st_mtime_ns")
    if any(getattr(before, field) != getattr(after, field) for field in identity):
        fail(f"{purpose} changed while being read")
    return b"".join(chunks)


def parse_env(content, purpose, reject_duplicates):
    try:
        text = content.decode("utf-8")
    except UnicodeError:
        fail(f"{purpose} is not valid UTF-8")
    if any(ord(character) < 32 and character != "\n" or ord(character) == 127
           for character in text):
        fail(f"{purpose} contains control characters")
    assignments = []
    seen = set()
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = assignment_pattern.fullmatch(stripped)
        if match is None:
            fail(f"{purpose} contains malformed assignment")
        name, value = match.groups()
        if reject_duplicates and name in seen:
            fail(f"{purpose} contains duplicate assignment")
        seen.add(name)
        assignments.append((name, value))
    return assignments, text.splitlines()


def merge_env(base_content, legacy_content):
    legacy_assignments, _ = parse_env(legacy_content, "legacy OmniRoute .env", True)
    storage_values = [value for name, value in legacy_assignments if name == "STORAGE_ENCRYPTION_KEY"]
    if len(storage_values) != 1 or not storage_key_pattern.fullmatch(storage_values[0]):
        fail("legacy OmniRoute .env must contain exactly one valid STORAGE_ENCRYPTION_KEY")
    _, base_lines = parse_env(base_content, "OmniRoute seed .env", False)
    legacy_names = {name for name, _ in legacy_assignments}
    retained_lines = []
    for line in base_lines:
        stripped = line.strip()
        match = assignment_pattern.fullmatch(stripped) if stripped and not stripped.startswith("#") else None
        if match is None or match.group(1) not in legacy_names:
            retained_lines.append(line)
    retained_lines.extend(f"{name}={value}" for name, value in legacy_assignments)
    return ("\n".join(retained_lines) + "\n").encode("utf-8")


def list_directory(fd, purpose):
    try:
        os.lseek(fd, 0, os.SEEK_SET)
        entries = list(os.scandir(fd))
    except OSError:
        fail(f"could not enumerate {purpose}")
    names = []
    for entry in entries:
        name = entry.name
        if name in ("", ".", "..") or "/" in name or "\x00" in name:
            fail(f"{purpose} contains an invalid entry name")
        if any(ord(character) < 32 or ord(character) == 127 for character in name):
            fail(f"{purpose} contains an entry name with control characters")
        names.append(name)
    if len(names) != len(set(names)):
        fail(f"{purpose} changed while being enumerated")
    return sorted(names)


def copy_regular(source_fd, destination_fd, name, purpose):
    source, before = open_owned_regular_at(source_fd, name, purpose)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    try:
        output = os.open(name, flags, 0o600, dir_fd=destination_fd)
    except OSError:
        os.close(source)
        fail(f"could not create migrated {purpose}")
    try:
        os.fchmod(output, 0o600)
        while True:
            content = os.read(source, 1024 * 1024)
            if not content:
                break
            offset = 0
            while offset < len(content):
                written = os.write(output, content[offset:])
                if written == 0:
                    fail(f"could not completely write migrated {purpose}")
                offset += written
        os.fsync(output)
        after = os.fstat(source)
    finally:
        os.close(output)
        os.close(source)
    identity = ("st_dev", "st_ino", "st_uid", "st_nlink", "st_size", "st_mtime_ns")
    if any(getattr(before, field) != getattr(after, field) for field in identity):
        fail(f"{purpose} changed while being copied")


def copy_tree(source_fd, destination_fd, relative=""):
    initial_names = list_directory(source_fd, "legacy OmniRoute state")
    for name in initial_names:
        purpose = os.path.join(relative, name) if relative else name
        if not relative and name in (
                ".env", marker_name, "storage.sqlite", "storage.sqlite-wal",
                "storage.sqlite-shm"):
            if name == marker_name:
                fail("legacy OmniRoute state contains reserved migration marker")
            continue
        try:
            metadata = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
        except OSError:
            fail(f"legacy OmniRoute entry changed before copy: {purpose}")
        if stat.S_ISDIR(metadata.st_mode):
            if metadata.st_uid != expected_uid:
                fail(f"legacy OmniRoute directory is not owned by login user: {purpose}")
            try:
                child_source = os.open(name, directory_flags(), dir_fd=source_fd)
                os.mkdir(name, 0o700, dir_fd=destination_fd)
                child_destination = os.open(name, directory_flags(), dir_fd=destination_fd)
            except OSError:
                fail(f"could not safely copy legacy OmniRoute directory: {purpose}")
            try:
                child_metadata = os.fstat(child_source)
                if not stat.S_ISDIR(child_metadata.st_mode) or child_metadata.st_uid != expected_uid:
                    fail(f"legacy OmniRoute directory changed during copy: {purpose}")
                os.fchmod(child_source, 0o700)
                os.fchmod(child_destination, 0o700)
                copy_tree(child_source, child_destination, purpose)
                os.fsync(child_destination)
            finally:
                os.close(child_destination)
                os.close(child_source)
        elif stat.S_ISREG(metadata.st_mode):
            copy_regular(source_fd, destination_fd, name, purpose)
        else:
            fail(f"legacy OmniRoute state contains symlink or special entry: {purpose}")
    if initial_names != list_directory(source_fd, "legacy OmniRoute state"):
        fail("legacy OmniRoute state changed while being copied")


def safe_exists(path):
    try:
        os.lstat(path)
        return True
    except FileNotFoundError:
        return False


def validate_owned_tree(directory_fd, relative=""):
    initial_names = list_directory(directory_fd, "prepared OmniRoute state")
    for name in initial_names:
        purpose = os.path.join(relative, name) if relative else name
        try:
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError:
            fail(f"prepared OmniRoute entry changed during validation: {purpose}")
        if stat.S_ISDIR(metadata.st_mode):
            if metadata.st_uid != expected_uid:
                fail(f"prepared OmniRoute directory is not owned by login user: {purpose}")
            try:
                child = os.open(name, directory_flags(), dir_fd=directory_fd)
            except OSError:
                fail(f"prepared OmniRoute directory is unsafe: {purpose}")
            try:
                child_metadata = os.fstat(child)
                if not stat.S_ISDIR(child_metadata.st_mode) or child_metadata.st_uid != expected_uid:
                    fail(f"prepared OmniRoute directory changed during validation: {purpose}")
                os.fchmod(child, 0o700)
                validate_owned_tree(child, purpose)
                os.fsync(child)
            finally:
                os.close(child)
        elif stat.S_ISREG(metadata.st_mode):
            descriptor, _ = open_owned_regular_at(directory_fd, name,
                                                  f"prepared OmniRoute file {purpose}")
            os.fsync(descriptor)
            os.close(descriptor)
        else:
            fail(f"prepared OmniRoute state contains symlink or special entry: {purpose}")
    if initial_names != list_directory(directory_fd, "prepared OmniRoute state"):
        fail("prepared OmniRoute state changed during validation")


def validate_database(database_path, purpose):
    try:
        metadata = os.stat(database_path, follow_symlinks=False)
    except OSError:
        fail(f"{purpose} is missing or unsafe")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        fail(f"{purpose} is not a singly linked file owned by login user")
    if metadata.st_size == 0:
        fail(f"{purpose} is empty")
    try:
        connection = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
        try:
            result = connection.execute("PRAGMA integrity_check").fetchall()
        finally:
            connection.close()
    except sqlite3.Error:
        fail(f"{purpose} could not be opened as SQLite")
    if result != [("ok",)]:
        fail(f"{purpose} failed SQLite integrity_check")


def validate_env(directory_fd, purpose):
    content = read_regular_at(directory_fd, ".env", f"{purpose} .env")
    assignments, _ = parse_env(content, f"{purpose} .env", True)
    storage_values = [value for name, value in assignments if name == "STORAGE_ENCRYPTION_KEY"]
    if len(storage_values) != 1 or not storage_key_pattern.fullmatch(storage_values[0]):
        fail(f"{purpose} .env must contain exactly one valid STORAGE_ENCRYPTION_KEY")


def validate_prepared_state(directory_path, require_marker):
    directory_fd = open_owned_directory(directory_path, "OmniRoute migrated state")
    try:
        validate_env(directory_fd, "OmniRoute migrated state")
        database_fd, _ = open_owned_regular_at(
            directory_fd, "storage.sqlite", "OmniRoute migrated storage.sqlite")
        os.close(database_fd)
        validate_database(os.path.join(directory_path, "storage.sqlite"),
                          "OmniRoute migrated storage.sqlite")
        try:
            marker_metadata = os.stat(marker_name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            if require_marker:
                fail("OmniRoute migrated state is missing migration marker")
            return False
        if not stat.S_ISREG(marker_metadata.st_mode):
            fail("OmniRoute migration marker is unsafe")
        content = read_regular_at(directory_fd, marker_name, "OmniRoute migration marker")
        validate_owned_tree(directory_fd)
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    if content != marker_content:
        fail("OmniRoute migration marker has invalid content")
    return True


def validate_backup_tree(directory_path):
    directory_fd = open_owned_directory(directory_path, "retained OmniRoute backup")
    try:
        validate_owned_tree(directory_fd)
        database_path = os.path.join(directory_path, "storage.sqlite")
        if safe_exists(database_path):
            validate_database(database_path, "retained OmniRoute backup storage.sqlite")
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def rename_noreplace(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        fail("platform cannot atomically preserve OmniRoute migration backup")
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p,
                          ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    result = renameat2(-100, os.fsencode(source), -100, os.fsencode(destination), 1)
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            fail("OmniRoute migration destination appeared concurrently")
        raise OSError(error_number, os.strerror(error_number), destination)


def fsync_parent():
    descriptor = os.open(parent_path, directory_flags())
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_all(descriptor, content, purpose):
    offset = 0
    while offset < len(content):
        written = os.write(descriptor, content[offset:])
        if written == 0:
            fail(f"could not completely write {purpose}")
        offset += written


def snapshot_database(source_path, destination_path):
    try:
        source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True)
        destination = sqlite3.connect(destination_path)
        try:
            source.backup(destination)
            destination.execute("PRAGMA journal_mode=DELETE")
            result = destination.execute("PRAGMA integrity_check").fetchall()
            destination.commit()
        finally:
            destination.close()
            source.close()
    except sqlite3.Error:
        fail("could not create consistent legacy OmniRoute SQLite snapshot")
    if result != [("ok",)]:
        fail("migrated OmniRoute SQLite snapshot failed integrity_check")
    descriptor = os.open(destination_path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def reject_database_holders(database_paths):
    try:
        result = subprocess.run(["fuser", "--", *database_paths],
                                stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                                check=False)
    except OSError:
        fail("could not verify legacy OmniRoute database file holders with fuser")
    if result.returncode == 0:
        fail("an open file holder remains on legacy OmniRoute database files")
    if result.returncode != 1:
        fail("could not verify legacy OmniRoute database file holders with fuser")


for candidate, purpose in (
        (home, "login home"),
        (legacy_path, "legacy OmniRoute state"),
        (destination_path, "durable OmniRoute state"),
        (package_env_path, "OmniRoute package .env"),
        (backup_path, "OmniRoute migration backup"),
        (temporary_path, "OmniRoute migration temporary path")):
    validate_absolute_home_path(candidate, purpose)

if safe_exists(destination_path):
    destination_fd = inspect_owned_directory(destination_path, "durable OmniRoute state")
    os.close(destination_fd)
    marker_path = os.path.join(destination_path, marker_name)
    if safe_exists(marker_path):
        validate_prepared_state(destination_path, True)
        raise SystemExit(0)

legacy_fd = inspect_owned_directory(legacy_path, "legacy OmniRoute state")
try:
    legacy_database_metadata = os.stat("storage.sqlite", dir_fd=legacy_fd, follow_symlinks=False)
    if (not stat.S_ISREG(legacy_database_metadata.st_mode) or
            legacy_database_metadata.st_uid != expected_uid or
            legacy_database_metadata.st_nlink != 1):
        fail("legacy OmniRoute storage.sqlite is unsafe")
finally:
    os.close(legacy_fd)

if safe_exists(destination_path) and safe_exists(backup_path):
    fail("unmarked durable OmniRoute state and retained backup both exist")

if safe_exists(temporary_path):
    validate_prepared_state(temporary_path, True)
    if safe_exists(destination_path):
        fail("OmniRoute migration temporary state conflicts with durable state")
    if safe_exists(backup_path):
        validate_backup_tree(backup_path)
    rename_noreplace(temporary_path, destination_path)
    fsync_parent()
    raise SystemExit(0)

if safe_exists(backup_path) and not safe_exists(destination_path):
    fail("retained OmniRoute backup exists without safely prepared migrated state")

legacy_fd = open_owned_directory(legacy_path, "legacy OmniRoute state")
try:
    legacy_env = read_regular_at(legacy_fd, ".env", "legacy OmniRoute .env")
    database_fd, _ = open_owned_regular_at(
        legacy_fd, "storage.sqlite", "legacy OmniRoute storage.sqlite")
    os.close(database_fd)
finally:
    os.close(legacy_fd)
validate_database(os.path.join(legacy_path, "storage.sqlite"),
                  "legacy OmniRoute storage.sqlite")

base_env_path = package_env_path
if safe_exists(destination_path):
    validate_backup_tree(destination_path)
    base_env_path = os.path.join(destination_path, ".env")
base_parent_fd = open_owned_directory(os.path.dirname(base_env_path), "OmniRoute seed .env directory")
try:
    base_env = read_regular_at(base_parent_fd, os.path.basename(base_env_path), "OmniRoute seed .env")
finally:
    os.close(base_parent_fd)
merged_env = merge_env(base_env, legacy_env)

legacy_database_paths = [
    os.path.join(legacy_path, "storage.sqlite"),
    os.path.join(legacy_path, "storage.sqlite-wal"),
    os.path.join(legacy_path, "storage.sqlite-shm"),
]
reject_database_holders(legacy_database_paths)
os.mkdir(temporary_path, 0o700)
temporary_fd = open_owned_directory(temporary_path, "OmniRoute migration temporary state")
try:
    legacy_fd = open_owned_directory(legacy_path, "legacy OmniRoute state")
    try:
        copy_tree(legacy_fd, temporary_fd)
    finally:
        os.close(legacy_fd)
    reject_database_holders(legacy_database_paths)
    snapshot_database(os.path.join(legacy_path, "storage.sqlite"),
                      os.path.join(temporary_path, "storage.sqlite"))
    env_output = os.open(".env", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=temporary_fd)
    try:
        write_all(env_output, merged_env, "migrated OmniRoute .env")
        os.fsync(env_output)
    finally:
        os.close(env_output)
    os.fsync(temporary_fd)
    marker_output = os.open(marker_name,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                            0o600, dir_fd=temporary_fd)
    try:
        write_all(marker_output, marker_content, "OmniRoute migration marker")
        os.fsync(marker_output)
    finally:
        os.close(marker_output)
    validate_prepared_state(temporary_path, True)
    os.fsync(temporary_fd)
finally:
    os.close(temporary_fd)
fsync_parent()

if safe_exists(destination_path):
    rename_noreplace(destination_path, backup_path)
    fsync_parent()
    validate_backup_tree(backup_path)
rename_noreplace(temporary_path, destination_path)
fsync_parent()
PY
	then
		fatal 'Could not safely migrate legacy OmniRoute state'
	fi
}

harden_omniroute_env() {
	local binding_status
	local durable_dir="$XDG_STATE_HOME/omniroute"
	local durable_env="$XDG_STATE_HOME/omniroute/.env"
	local package_env
	local install_dir
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local owner_uid
	local package_dir

	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	login_uid=$(id -u "$LOGIN_USER")
	[ "$login_uid" != 0 ] || fatal 'OmniRoute setup refuses root as login user'
	[ "$(id -u)" = "$login_uid" ] && [ "$(id -un)" = "$LOGIN_USER" ] ||
		fatal 'OmniRoute setup must run as login user, not through a root shell'
	install_dir=$("$mise_bin" where npm:omniroute) ||
		fatal 'Could not resolve OmniRoute installation'
	case "$install_dir" in
		/*) ;;
		*) fatal 'Mise returned an invalid OmniRoute installation path' ;;
	esac
	[[ "$install_dir" != *$'\n'* ]] || fatal 'Mise returned multiple OmniRoute installation paths'
	[ -d "$install_dir" ] && [ ! -L "$install_dir" ] || fatal 'OmniRoute installation path is not a safe directory'

	package_dir="$install_dir/lib/node_modules/omniroute"
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$package_dir" \
		'OmniRoute package path'
	[ -d "$package_dir" ] && [ ! -L "$package_dir" ] || fatal 'OmniRoute package path is not a safe directory'
	[ "$(realpath "$package_dir")" = "$package_dir" ] || fatal 'OmniRoute package path contains a symlink'
	package_env="$package_dir/.env"
	[ -f "$package_env" ] && [ ! -L "$package_env" ] || fatal 'OmniRoute package .env is not a regular file'
	owner_uid=$(path_owner_uid "$package_env") || fatal 'Could not inspect OmniRoute package .env ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'OmniRoute package .env is not owned by login user'
	chmod 0600 "$package_env"

	case "$XDG_STATE_HOME" in
		/*) ;;
		*) fatal 'XDG_STATE_HOME must be an absolute path' ;;
	esac
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$XDG_STATE_HOME" 'XDG_STATE_HOME path'
	[ -d "$XDG_STATE_HOME" ] && [ ! -L "$XDG_STATE_HOME" ] || fatal 'XDG_STATE_HOME is not a safe directory'
	owner_uid=$(path_owner_uid "$XDG_STATE_HOME") || fatal 'Could not inspect XDG_STATE_HOME ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'XDG_STATE_HOME is not owned by login user'

	[ ! -L "$durable_dir" ] || fatal 'OmniRoute state directory must not be a symlink'
	if [ ! -e "$durable_dir" ]; then
		mkdir "$durable_dir" || fatal 'Could not create OmniRoute state directory'
	fi
	[ -d "$durable_dir" ] && [ ! -L "$durable_dir" ] || fatal 'OmniRoute state path is not a directory'
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$durable_dir" \
		'OmniRoute state directory path'
	owner_uid=$(path_owner_uid "$durable_dir") || fatal 'Could not inspect OmniRoute state directory ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'OmniRoute state directory is not owned by login user'
	chmod 0700 "$durable_dir"

	if [ -e "$durable_env" ] || [ -L "$durable_env" ]; then
		[ -f "$durable_env" ] && [ ! -L "$durable_env" ] || fatal 'Durable OmniRoute .env is not a regular file'
	else
		bash -c \
			'umask 077; set -o noclobber; command cat -- "$1" > "$2"' \
			bash "$package_env" "$durable_env" || fatal 'Could not seed durable OmniRoute .env'
	fi
	[ -f "$durable_env" ] && [ ! -L "$durable_env" ] || fatal 'Durable OmniRoute .env is not a regular file'
	owner_uid=$(path_owner_uid "$durable_env") || fatal 'Could not inspect durable OmniRoute .env ownership'
	[ "$owner_uid" = "$login_uid" ] || fatal 'Durable OmniRoute .env is not owned by login user'
	chmod 0600 "$durable_env"

	if omniroute_binding_works "$mise_bin" "$package_dir"; then
		return 0
	else
		binding_status=$?
	fi
	[ "$binding_status" = 10 ] || fatal 'OmniRoute better-sqlite3 verification failed without a missing binding'
	[ "${OMNIROUTE_REPAIR_ATTEMPTED:-false}" != true ] ||
		fatal 'OmniRoute better-sqlite3 binding is still unavailable after reinstall'
	printf '==> Reinstalling OmniRoute to repair missing better-sqlite3 binding\n'
	"$mise_bin" install --force npm:omniroute || fatal 'Could not reinstall OmniRoute through Mise'
	OMNIROUTE_REPAIR_ATTEMPTED=true harden_omniroute_env
}

write_process_compose_native_environment() {
	local mise_bin="$HOME/.local/bin/mise"
	local native_dir
	local output_path
	local source_path=-

	case "$OS" in
		Darwin)
			native_dir="$XDG_STATE_HOME/process-compose/native"
			output_path="$native_dir/io.sarendipitee.process-compose.plist"
			source_path="$DOTFILES_DIR/packages/launchd/Library/LaunchAgents/io.sarendipitee.process-compose.plist"
			;;
		Linux)
			native_dir="$XDG_CONFIG_HOME/systemd/user/dotfiles-process-compose.service.d"
			output_path="$native_dir/10-xdg-state.conf"
			;;
	esac
	mkdir -p "$native_dir"
	chmod 0700 "$native_dir"
	"$mise_bin" exec -- python - "$OS" "$source_path" "$output_path" "$XDG_STATE_HOME" <<'PY'
import os
import plistlib
import sys
import tempfile

platform, source_path, output_path, state_home = sys.argv[1:]
if not os.path.isabs(state_home) or any(ord(character) < 32 or ord(character) == 127 for character in state_home):
    raise SystemExit("invalid XDG_STATE_HOME for native service")

if platform == "Darwin":
    with open(source_path, "rb") as source:
        service = plistlib.load(source)
    service.setdefault("EnvironmentVariables", {})["XDG_STATE_HOME"] = state_home
    content = plistlib.dumps(service, fmt=plistlib.FMT_XML, sort_keys=False)
else:
    escaped = state_home.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
    content = f'[Service]\nEnvironment="XDG_STATE_HOME={escaped}"\n'.encode()

directory = os.path.dirname(output_path)
descriptor, temporary_path = tempfile.mkstemp(prefix=".native-environment.", dir=directory)
try:
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "wb") as destination:
        destination.write(content)
    os.replace(temporary_path, output_path)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
PY
	printf '%s\n' "$output_path"
}

sanitize_legacy_codex_remote_control_unit() {
	local expected_path="$XDG_CONFIG_HOME/systemd/user/codex-remote-control.service"
	local fragment_path
	local legacy_load_state
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local owner_uid
	local user_systemctl=(systemctl --user)

	login_uid=$(id -u "$LOGIN_USER")
	if [ "$(id -un)" != "$LOGIN_USER" ]; then
		user_systemctl=(
			sudo -u "$LOGIN_USER" env
			"XDG_RUNTIME_DIR=/run/user/$login_uid"
			"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
			systemctl --user
		)
	fi
	legacy_load_state=$("${user_systemctl[@]}" show --property=LoadState --value \
		codex-remote-control.service 2>/dev/null) ||
		fatal 'Could not inspect legacy Codex remote-control service'
	if [ "$legacy_load_state" != not-found ]; then
		[ -n "$legacy_load_state" ] || fatal 'Legacy Codex remote-control service returned empty load state'
		fragment_path=$("${user_systemctl[@]}" show --property=FragmentPath --value \
			codex-remote-control.service 2>/dev/null) ||
			fatal 'Could not locate legacy Codex remote-control unit'
		[ "$fragment_path" = "$expected_path" ] ||
			fatal 'Legacy Codex remote-control unit loaded from unexpected path'
	fi

	if [ ! -e "$expected_path" ] && [ ! -L "$expected_path" ]; then
		return 0
	fi
	[ -f "$expected_path" ] && [ ! -L "$expected_path" ] ||
		fatal 'Legacy Codex remote-control unit is not a regular file'
	converge_path_directories "$mise_bin" "$HOME" "$login_uid" "$(dirname "$expected_path")" \
		'Legacy Codex remote-control unit directory path'
	owner_uid=$(path_owner_uid "$expected_path") ||
		fatal 'Could not inspect legacy Codex remote-control unit ownership'
	[ "$owner_uid" = "$login_uid" ] ||
		fatal 'Legacy Codex remote-control unit is not owned by login user'

	"$mise_bin" exec -- python - "$expected_path" "$login_uid" <<'PY'
import os
import re
import stat
import sys
import tempfile

path, expected_uid = sys.argv[1], int(sys.argv[2])
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != expected_uid or metadata.st_nlink != 1:
        raise OSError
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "r", encoding="utf-8", newline="") as source:
        lines = source.readlines()
except (OSError, UnicodeError):
    raise SystemExit("could not read legacy Codex remote-control unit")

if any("\x00" in line for line in lines):
    raise SystemExit("legacy Codex remote-control unit contains invalid data")

service_indexes = [index for index, line in enumerate(lines) if line.strip() == "[Service]"]
if len(service_indexes) != 1:
    raise SystemExit("legacy Codex remote-control unit must contain one Service section")

environment_file = "EnvironmentFile=%h/.config/hindsight/hindsight.env"
result = []
inserted = False
for index, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r"^Environment\s*=", stripped) and "OMNIROUTER_API_KEY=" in stripped:
        continue
    if stripped == environment_file:
        continue
    result.append(line)
    if index == service_indexes[0]:
        result.append(environment_file + "\n")
        inserted = True

if not inserted:
    raise SystemExit("could not update legacy Codex remote-control unit")
if any("OMNIROUTER_API_KEY=" in line for line in result):
    raise SystemExit("legacy Codex remote-control unit still contains inline key")

directory = os.path.dirname(path)
descriptor, temporary_path = tempfile.mkstemp(prefix=".codex-remote-control.", dir=directory)
try:
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as destination:
        destination.writelines(result)
        destination.flush()
        os.fsync(destination.fileno())
    os.replace(temporary_path, path)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)
PY
}

remove_stale_hindsight_container() {
	local container_id
	local running

	container_id=$(sudo docker ps -aq --filter 'name=^/hindsight$') ||
		fatal 'Could not query stale Hindsight container'
	[ -n "$container_id" ] || return 0
	[[ "$container_id" =~ ^[[:xdigit:]]{12,64}$ ]] ||
		fatal 'Stale Hindsight container query returned invalid identifier'
	running=$(sudo docker container inspect --format '{{.State.Running}}' hindsight 2>/dev/null) ||
		fatal 'Could not inspect stale Hindsight container'
	case "$running" in
		true)
			sudo docker stop -t 30 hindsight >/dev/null ||
				fatal 'Could not stop stale Hindsight container'
			;;
		false) ;;
		*) fatal 'Stale Hindsight container returned invalid running state' ;;
	esac
	container_id=$(sudo docker ps -aq --filter 'name=^/hindsight$') ||
		fatal 'Could not verify stale Hindsight container removal'
	if [ -n "$container_id" ]; then
		sudo docker rm hindsight >/dev/null || fatal 'Could not remove stale Hindsight container'
	fi
}

migrate_system_etserver_service() {
	local exec_start
	local expected_path=${1:-/etc/systemd/system/etserver.service}
	local fragment_path
	local legacy_load_state
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local service_state
	local unit_state
	local unit_user

	[ "$(current_process_compose_profile)" = aorus ] || return 0
	legacy_load_state=$(sudo systemctl show --property=LoadState --value etserver.service 2>/dev/null) ||
		fatal 'Could not inspect legacy system Eternal Terminal service'
	[ "$legacy_load_state" = not-found ] && return 0
	[ "$legacy_load_state" = loaded ] ||
		fatal 'Legacy system Eternal Terminal service returned unexpected load state'
	fragment_path=$(sudo systemctl show --property=FragmentPath --value etserver.service 2>/dev/null) ||
		fatal 'Could not locate legacy system Eternal Terminal unit'
	unit_user=$(sudo systemctl show --property=User --value etserver.service 2>/dev/null) ||
		fatal 'Could not inspect legacy system Eternal Terminal user'
	exec_start=$(sudo systemctl show --property=ExecStart --value etserver.service 2>/dev/null) ||
		fatal 'Could not inspect legacy system Eternal Terminal command'
	[ "$fragment_path" = "$expected_path" ] ||
		fatal 'Legacy system Eternal Terminal unit loaded from unexpected path'
	[ "$unit_user" = "$LOGIN_USER" ] ||
		fatal 'Legacy system Eternal Terminal unit runs as unexpected user'
	[ -x "$mise_bin" ] || fatal "Mise executable is missing or not executable: $mise_bin"
	if ! "$mise_bin" exec -- python - "$expected_path" "$exec_start" <<'PY'
import os
import re
import shlex
import stat
import sys

unit_path, exec_start = sys.argv[1:]


def fail(message):
    raise SystemExit(message)


if unit_path != "/etc/systemd/system/etserver.service" and not unit_path.startswith("/"):
    fail("legacy Eternal Terminal unit path is invalid")

current = "/"
for component in unit_path.split(os.sep)[1:-1]:
    current = os.path.join(current, component)
    try:
        metadata = os.lstat(current)
    except OSError:
        fail("legacy Eternal Terminal unit path could not be inspected")
    if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or
            metadata.st_mode & 0o022):
        fail("legacy Eternal Terminal unit path has unsafe ancestors")

flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    path_metadata = os.lstat(unit_path)
    if stat.S_ISLNK(path_metadata.st_mode):
        fail("legacy Eternal Terminal unit is a symlink")
    descriptor = os.open(unit_path, flags)
    metadata = os.fstat(descriptor)
finally:
    if "descriptor" in locals():
        os.close(descriptor)
if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or
        metadata.st_nlink != 1 or metadata.st_mode & 0o022 or
        (metadata.st_dev, metadata.st_ino) != (path_metadata.st_dev, path_metadata.st_ino)):
    fail("legacy Eternal Terminal unit is unsafe")

structured = re.fullmatch(r"\{\s*path=([^ ;]+)\s*;\s*argv\[\]=(.*?)\s*;.*\}", exec_start)
if structured:
    reported_path = structured.group(1)
    command = shlex.split(structured.group(2))
else:
    command = shlex.split(exec_start)
    reported_path = command[0] if command else ""
if not command or command[0] != reported_path:
    fail("legacy Eternal Terminal command is malformed")

executable = command[0]
match = re.fullmatch(
    r"((?:/home/linuxbrew/\.linuxbrew|/usr/local|/opt/homebrew))"
    r"/(?:opt/et|Cellar/et/[^/]+)/bin/etserver",
    executable,
)
if not match:
    fail("legacy Eternal Terminal command is not the expected Homebrew etserver")
expected_config = match.group(1) + "/etc/et.cfg"
config_paths = []
for index, argument in enumerate(command[1:]):
    if argument == "--cfgfile":
        if index + 2 >= len(command):
            fail("legacy Eternal Terminal cfgfile argument is missing its value")
        config_paths.append(command[index + 2])
    elif argument.startswith("--cfgfile="):
        config_paths.append(argument.split("=", 1)[1])
if config_paths != [expected_config]:
    fail("legacy Eternal Terminal command has unexpected cfgfile")
PY
	then
		fatal 'Could not safely validate legacy system Eternal Terminal unit'
	fi

	sudo systemctl disable --now etserver.service >/dev/null ||
		fatal 'Could not disable and stop legacy system Eternal Terminal service'
	service_state=$(sudo systemctl is-active etserver.service 2>/dev/null || true)
	[ "$service_state" = inactive ] ||
		fatal 'Legacy system Eternal Terminal service remains active'
	unit_state=$(sudo systemctl is-enabled etserver.service 2>/dev/null || true)
	[ "$unit_state" = disabled ] ||
		fatal 'Legacy system Eternal Terminal service remains enabled'
}

migrate_linux_process_compose_services() {
	local codex_stop_output
	local hindsight_ownership=false
	local legacy_load_state
	local legacy_unit
	local login_uid
	local mise_bin="$HOME/.local/bin/mise"
	local user_systemctl=(systemctl --user)

	login_uid=$(id -u "$LOGIN_USER")
	if [ "$(id -un)" != "$LOGIN_USER" ]; then
		user_systemctl=(
			sudo -u "$LOGIN_USER" env
			"XDG_RUNTIME_DIR=/run/user/$login_uid"
			"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
			systemctl --user
		)
	fi

	migrate_system_etserver_service
	sanitize_legacy_codex_remote_control_unit
	for legacy_unit in \
		codex-remote-control.service \
		codex-remote.service \
		hindsight.service \
		homebrew.et.service \
		omniroute.service; do
		legacy_load_state=$("${user_systemctl[@]}" show --property=LoadState --value "$legacy_unit" 2>/dev/null) ||
			fatal "Could not inspect legacy user service: $legacy_unit"
		[ "$legacy_load_state" = not-found ] && continue
		[ -n "$legacy_load_state" ] || fatal "Legacy user service returned an empty load state: $legacy_unit"
		[ "$legacy_unit" != hindsight.service ] || hindsight_ownership=true
		"${user_systemctl[@]}" disable --now "$legacy_unit" >/dev/null 2>&1 ||
			fatal "Could not disable and stop legacy user service: $legacy_unit"
		! "${user_systemctl[@]}" is-active --quiet "$legacy_unit" ||
			fatal "Legacy user service remains active: $legacy_unit"
		! "${user_systemctl[@]}" is-enabled --quiet "$legacy_unit" ||
			fatal "Legacy user service remains enabled: $legacy_unit"
	done

	codex_stop_output=$("$mise_bin" exec -- codex remote-control --json stop) ||
		fatal 'Could not stop detached Codex remote-control daemon'
	case "$codex_stop_output" in
		*'"status":"stopped"'* | *'"status":"notRunning"'*) ;;
		*) fatal 'Codex remote-control stop returned an unexpected status' ;;
	esac
	if "$hindsight_ownership" || [ "$(current_process_compose_profile)" = aorus ]; then
		remove_stale_hindsight_container
	fi
}

current_process_compose_profile() {
	local host_file="$XDG_CONFIG_HOME/process-compose/host"
	local profile
	local profile_line
	local profile_line_count=0

	if [ -n "${DOTFILES_HOST:-}" ]; then
		profile=$DOTFILES_HOST
	elif [ -e "$host_file" ]; then
		[ -f "$host_file" ] || fatal 'Process Compose host profile is not a regular file'
		profile=
		while IFS= read -r profile_line || [ -n "$profile_line" ]; do
			profile_line_count=$((profile_line_count + 1))
			[ "$profile_line_count" -ne 1 ] || profile=$profile_line
		done < "$host_file"
		[ "$profile_line_count" -eq 1 ] && [ -n "$profile" ] ||
			fatal 'Process Compose host profile must contain one non-empty line'
	else
		profile=$(hostname -s)
	fi
	[[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fatal 'Invalid Process Compose host profile'
	printf '%s\n' "$profile"
}

verify_aorus_process_compose() {
	local curl_timeout
	local deadline
	local interval=${PROCESS_COMPOSE_READY_INTERVAL_SECONDS:-5}
	local mise_bin="$HOME/.local/bin/mise"
	local process_json
	local process_ready
	local readiness_diagnostics
	local remaining
	local sleep_seconds
	local socket_dir
	local socket_path
	local timeout_seconds=${PROCESS_COMPOSE_READY_TIMEOUT_SECONDS:-600}

	[ "$(current_process_compose_profile)" = aorus ] || return 0
	if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ] &&
		[ -O "$XDG_RUNTIME_DIR" ] && [ ! -L "$XDG_RUNTIME_DIR" ]; then
		socket_dir="$XDG_RUNTIME_DIR/dpc"
	else
		socket_dir="$XDG_STATE_HOME/process-compose/run"
	fi
	socket_path="$socket_dir/pc.sock"
	[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] ||
		fatal 'PROCESS_COMPOSE_READY_TIMEOUT_SECONDS must be positive integer'
	[[ "$interval" =~ ^[0-9]+$ ]] ||
		fatal 'PROCESS_COMPOSE_READY_INTERVAL_SECONDS must be non-negative integer'
	command_exists timeout || fatal 'timeout command is required for Process Compose readiness checks'
	deadline=$((SECONDS + timeout_seconds))

	while (( SECONDS < deadline )); do
		process_json=
		process_ready=false
		remaining=$((deadline - SECONDS))
		if [ -S "$socket_path" ]; then
			process_json=$(timeout "${remaining}s" "$mise_bin" exec -- process-compose \
				--use-uds --unix-socket "$socket_path" \
				list -o json 2>/dev/null) || process_json=
		fi
		remaining=$((deadline - SECONDS))
		if [ -n "$process_json" ] && (( remaining > 0 )) &&
			printf '%s' "$process_json" | timeout "${remaining}s" "$mise_bin" exec -- jq -e \
				--argjson names '["eternal-terminal","omniroute","codex-remote-control","hindsight"]' '
			map({key: .name, value: .}) | from_entries as $processes |
			all($names[]; $processes[.] != null and $processes[.].is_running == true and
			  ($processes[.].has_ready_probe != true or $processes[.].is_ready == "Ready"))
		' >/dev/null 2>&1; then
			process_ready=true
		fi
		remaining=$((deadline - SECONDS))
		if "$process_ready" && (( remaining > 0 )); then
			curl_timeout=5
			(( remaining >= curl_timeout )) || curl_timeout=$remaining
			if curl -fsS --max-time "$curl_timeout" \
				http://127.0.0.1:18888/health >/dev/null; then
				return 0
			fi
		fi
		remaining=$((deadline - SECONDS))
		(( remaining > 0 )) || break
		sleep_seconds=$interval
		(( remaining >= sleep_seconds )) || sleep_seconds=$remaining
		(( sleep_seconds == 0 )) || sleep "$sleep_seconds"
	done
	if [ -n "$process_json" ]; then
		readiness_diagnostics=$(printf '%s' "$process_json" | timeout 5s "$mise_bin" exec -- jq -r \
			--argjson names '["eternal-terminal","omniroute","codex-remote-control","hindsight"]' '
		map({key: .name, value: .}) | from_entries as $processes |
		$names[] as $name |
		($processes[$name] // {}) as $process |
		[
		  $name,
		  (if $process.is_running == true then "running" else "stopped" end),
		  (if $process.has_ready_probe != true then "no-probe"
		   elif $process.is_ready == "Ready" then "ready" else "not-ready" end),
		  (if ($process.restarts | type) == "number" then ($process.restarts | tostring) else "unknown" end),
		  (if ($process.exit_code | type) == "number" then ($process.exit_code | tostring) else "unknown" end)
		] | @tsv
		' 2>/dev/null) || readiness_diagnostics=
		while IFS=$'\t' read -r process_name process_state process_readiness process_restarts process_exit_code; do
			[ -n "$process_name" ] || continue
			printf 'Process readiness: name=%s state=%s readiness=%s restarts=%s exit_code=%s\n' \
				"$process_name" "$process_state" "$process_readiness" "$process_restarts" "$process_exit_code" >&2
		done <<< "$readiness_diagnostics"
	fi
	fatal 'Aorus Process Compose replacement services did not become ready'
}

setup_process_compose() {
	local launcher="$HOME/.local/bin/dotfiles-process-compose"
	local native_definition
	native_definition=$(write_process_compose_native_environment)
	[ -x "$launcher" ] || fatal "Process Compose launcher is missing or not executable: $launcher"
	"$launcher" --check

	case "$OS" in
		Darwin)
			local domain
			local label=io.sarendipitee.process-compose
			domain="gui/$(id -u)"
			launchctl enable "$domain/$label"
			launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
			launchctl bootstrap "$domain" "$native_definition"
			;;
		Linux)
			local login_uid
			local legacy_unit
			local legacy_unit_path
			local legacy_unit_target
			local user_systemctl=(systemctl --user)
			login_uid=$(id -u "$LOGIN_USER")
			sudo loginctl enable-linger "$LOGIN_USER"
			if [ "$(id -un)" != "$LOGIN_USER" ]; then
				user_systemctl=(
					sudo -u "$LOGIN_USER" env
					"XDG_RUNTIME_DIR=/run/user/$login_uid"
					"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$login_uid/bus"
					systemctl --user
				)
			fi
			"${user_systemctl[@]}" stop dotfiles-process-compose.service >/dev/null 2>&1 || true
			! "${user_systemctl[@]}" is-active --quiet dotfiles-process-compose.service ||
				fatal 'Could not stop existing Process Compose service before migration'
			migrate_linux_process_compose_services
			for legacy_unit in vllm-qwen.service vllm-gemma4.service vllm-step3.service; do
				"${user_systemctl[@]}" disable --now "$legacy_unit" >/dev/null 2>&1 || true
				legacy_unit_path="$XDG_CONFIG_HOME/systemd/user/$legacy_unit"
				legacy_unit_target="$DOTFILES_DIR/packages/systemd/.config/systemd/user/$legacy_unit"
				if [ -L "$legacy_unit_path" ] && [ "$(readlink -f "$legacy_unit_path")" = "$legacy_unit_target" ]; then
					rm -f "$legacy_unit_path"
				fi
			done
			"${user_systemctl[@]}" daemon-reload
			"${user_systemctl[@]}" enable dotfiles-process-compose.service
			"${user_systemctl[@]}" restart dotfiles-process-compose.service
			verify_aorus_process_compose
			;;
	esac
}

setup_ssh_server() {
	printf '==> Configuring OpenSSH server\n'
	if [ "${DOTFILES_SSH_KEY_ONLY:-false}" = true ]; then
		[ -s "$HOME/.ssh/authorized_keys" ] || fatal 'DOTFILES_SSH_KEY_ONLY=true requires ~/.ssh/authorized_keys'
		cat <<'EOF' | sudo tee /etc/ssh/sshd_config.d/99-dotfiles.conf >/dev/null
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
		sudo chmod 0644 /etc/ssh/sshd_config.d/99-dotfiles.conf
	fi

	sudo sshd -t
	sudo systemctl enable --now ssh
	if command_exists ufw && sudo ufw status | grep -q '^Status: active'; then
		sudo ufw allow OpenSSH
	fi
	sudo systemctl is-active --quiet ssh || fatal 'OpenSSH server failed to start'
}

docker_ce_installed() {
	dpkg-query -W -f='${db:Status-Abbrev}' docker-ce 2>/dev/null | grep -q '^ii'
}

setup_docker() {
	local pkg conflicts=()
	printf '==> Configuring Docker Engine\n'

	if ! docker_ce_installed; then
		for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
			if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
				conflicts+=("$pkg")
			fi
		done
		[ "${#conflicts[@]}" -eq 0 ] || sudo apt-get remove -y "${conflicts[@]}"

		sudo install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
			sudo tee /etc/apt/keyrings/docker.asc >/dev/null
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
			"$(dpkg --print-architecture)" "$VERSION_CODENAME" |
			sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	fi

	sudo groupadd -f docker
	if ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -Fxq docker; then
		sudo usermod -aG docker "$LOGIN_USER"
	fi
	if ! id -nG | tr ' ' '\n' | grep -Fxq docker; then RELOGIN_REQUIRED=true; fi
	sudo systemctl enable --now docker
	sudo systemctl is-active --quiet docker || fatal 'Docker service failed to start'
	sudo docker version >/dev/null
}

setup_nvidia() {
	printf '==> Configuring NVIDIA compute stack\n'
	[ "$(uname -m)" = x86_64 ] || fatal "NVIDIA automation supports x86_64 only: $(uname -m)"
	sudo apt-get install -y "linux-headers-$(uname -r)" ubuntu-drivers-common

	if ! command_exists nvidia-smi; then
		sudo ubuntu-drivers install
		REBOOT_REQUIRED=true
	fi
	bash "$DOTFILES_DIR/scripts/install-cuda.sh" --toolkit --container-toolkit
	if ! command_exists nvidia-smi || ! nvidia-smi >/dev/null 2>&1; then
		REBOOT_REQUIRED=true
	fi
}

setup_linuxbrew_ca() {
	local brew="/home/linuxbrew/.linuxbrew/bin/brew"
	local cert="/home/linuxbrew/.linuxbrew/etc/openssl@3/cert.pem"
	[ -x "$brew" ] || return 0
	[ -e "$cert" ] && return 0
	printf '==> Linking Linuxbrew OpenSSL CA certificates\n'
	"$brew" postinstall openssl@3 2>&1 | tail -5 || true
	if [ ! -e "$cert" ]; then
		printf 'WARNING: openssl postinstall did not create %s; falling back to system CA bundle\n' "$cert" >&2
		mkdir -p "$(dirname "$cert")"
		cp -f /etc/ssl/certs/ca-certificates.crt "$cert"
	fi
}

setup_tailscale() {
	printf '==> Configuring Tailscale\n'
	if ! command_exists tailscale; then
		sudo install -d -m 0755 /usr/share/keyrings
		curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" |
			sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
		curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" |
			sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
		sudo apt-get update
		sudo apt-get install -y tailscale
	fi
	sudo systemctl enable --now tailscaled
	sudo systemctl is-active --quiet tailscaled || fatal 'tailscaled failed to start'
}

case "$OS" in
	Darwin) ;;
	Linux)
		[ -r /etc/os-release ] || fatal '/etc/os-release is required'
		# shellcheck disable=SC1091
		source /etc/os-release
		[ "${ID:-}" = ubuntu ] || fatal "Unsupported Linux distribution: ${ID:-unknown}"
		case "${VERSION_ID:-}" in 22.04 | 24.04 | 26.04) ;; *) fatal "Unsupported Ubuntu release: ${VERSION_ID:-unknown}" ;; esac
		;;
	*) fatal "Unsupported operating system: $OS" ;;
esac

migrate_legacy_codex_auth
verify_aorus_codex_login
setup_user_state
migrate_legacy_omniroute_state
harden_omniroute_env

if [ "$OS" = Darwin ]; then
	setup_process_compose
	printf 'macOS system bootstrap complete. Launch installed GUI applications once to finish their setup.\n'
	exit 0
fi

trap cleanup EXIT
keep_sudo_alive

if [ "${DOTFILES_WITH_SSH:-true}" = true ]; then setup_ssh_server; fi
if [ "${DOTFILES_WITH_DOCKER:-true}" = true ]; then setup_docker; fi
if [ "${DOTFILES_WITH_NVIDIA:-auto}" = true ] || { [ "${DOTFILES_WITH_NVIDIA:-auto}" = auto ] && has_nvidia_gpu; }; then
	setup_nvidia
fi
if [ "${DOTFILES_WITH_TAILSCALE:-true}" = true ]; then setup_tailscale; fi
if [ "${DOTFILES_WITH_LINUXBREW_CA:-true}" = true ]; then setup_linuxbrew_ca; fi
if "$RELOGIN_REQUIRED"; then
	fatal 'Docker group membership changed; log out and back in, then rerun provisioning'
fi
setup_process_compose

if [ -e /var/run/reboot-required ]; then REBOOT_REQUIRED=true; fi

printf 'SSH: %s\n' "$(sudo systemctl is-active ssh 2>/dev/null || printf skipped)"
printf 'Docker: %s\n' "$(sudo systemctl is-active docker 2>/dev/null || printf skipped)"
printf 'Tailscale: %s\n' "$(sudo systemctl is-active tailscaled 2>/dev/null || printf skipped)"
if "$RELOGIN_REQUIRED"; then printf 'Action required: log out and back in for Docker group membership.\n'; fi
if "$REBOOT_REQUIRED"; then printf 'Action required: reboot, then verify nvidia-smi and CUDA container access.\n'; fi
if command_exists tailscale && ! tailscale status >/dev/null 2>&1; then
	printf 'Action required: run tailscale up and authenticate.\n'
fi
