#!/usr/bin/env zsh

is_non_zero_string() {
	! test -z "${1}"
}

# Remove trailing slash if present
strip_trailing_slash() {
	echo "${1%\/}"
}

extract_last_segment() {
	local without_trailing_slash="$(strip_trailing_slash "${1}")"
	echo "${without_trailing_slash##*/}"
	unset without_trailing_slash
}

is_file() {
	is_non_zero_string "${1}" && test -f "${1}"
}

is_executable() {
	is_non_zero_string "${1}" && test -e "${1}"
}

is_directory() {
	is_non_zero_string "${1}" && test -d "${1}"
}

dir_has_children() {
	is_directory "${1}" && test -n "$(ls -A "${1}")"
}

ensure_dir_exists() {
	if is_non_zero_string "${1}"; then
		mkdir -p "${1}"
	else
		warn "Skipping creation of the directory since '${1}' is not defined"
	fi
}

is_git_repo() {
	is_directory "${1}/.git"
}

load_file_if_exists() {
	# shellcheck disable=SC2015
	# shellcheck disable=SC1090
	is_file "${1}" && source "${1}"
}

delete_directory_if_exists() {
	is_directory "${1}" && echo "$(red 'Deleting') '$(green "${1}")'" && sudo rm -rf "${1}"
}

command_exists() {
	type "${1}" &>/dev/null 2>&1
}

# Note: This function is kind of equivalent to 'omz reload', but that doesn't seem to work when installing on a vanilla OS
load_zsh_configs() {
	local file_list=('.zshenv' '.zshrc' '.zlogin')
	for file in "${file_list[@]}"; do
		load_file_if_exists "${ZDOTDIR}/${file}"
	done
	unset file
	unset file_list
}

append_to_path_if_dir_exists() {
	is_directory "${1}" && path+="${1}"
}

append_to_fpath_if_dir_exists() {
	is_directory "${1}" && fpath+="${1}"
}

prepend_to_path_if_dir_exists() {
	is_directory "${1}" && export PATH="${1}:${PATH+:${PATH}}"
}

prepend_to_manpath_if_dir_exists() {
	is_directory "${1}" && export MANPATH="${1}:${MANPATH+:${MANPATH}}"
}

prepend_to_ldflags_if_dir_exists() {
	is_directory "${1}" && export LDFLAGS="-L${1} ${LDFLAGS+ ${LDFLAGS}}"
}

prepend_to_cppflags_if_dir_exists() {
	is_directory "${1}" && export CPPFLAGS="-I${1} ${CPPFLAGS+ ${CPPFLAGS}}"
}

prepend_to_pkg_config_path_if_dir_exists() {
	is_directory "${1}" && export PKG_CONFIG_PATH="${1}${PKG_CONFIG_PATH+:${PKG_CONFIG_PATH}}"
}

is_macos() {
	[[ "${OSTYPE}" =~ 'darwin' ]]
}

is_linux() {
	[[ "${OSTYPE}" =~ 'Linux' ]]
}

is_windows() {
	[[ "${OSTYPE}" =~ 'MINGW' ]]
}

folder_size() {
	echo $(cyan "$(\du -sh "${1}" | cut -f1)")
}

clone_repo_into() {
	local target_folder="${2}"
	ensure_dir_exists "${target_folder}"
	if ! is_git_repo "${target_folder}"; then
		local tmp_folder="$(mktemp -d)"
		git -C "${tmp_folder}" clone -q "${1}" .
		mv "${tmp_folder}/.git" "${target_folder}"
		git -C "${target_folder}" checkout .
		git -C "${target_folder}" submodule update --init --recursive --remote --rebase --force
		rm -rf "${tmp_folder}"
		success "Successfully cloned '$(yellow "${1}")$(green "' into '")$(yellow "${target_folder}")$(green "'")"

		local target_branch="${3}"
		if is_non_zero_string "${target_branch}"; then
			git -C "${target_folder}" switch "${target_branch}"
			local checked_out_branch="$(git -C "${target_folder}" branch --show-current)"
			[[ "${checked_out_branch}" != "${target_branch}" ]] && error "'${target_branch}' is not equal to the branch that was checked out: '${checked_out_branch}'; something is wrong. Please correct before retrying!"
			unset checked_out_branch
		fi
		unset tmp_folder
		unset target_branch
	else
		warn "Skipping cloning of '${1}' since '${target_folder}' is already a git repo"
	fi
	unset target_folder
}

set_ssh_folder_permissions() {
	local target_folder="${HOME}/.ssh"
	ensure_dir_exists "${target_folder}"
	if dir_has_children "${target_folder}"; then
		chmod -R 600 "${target_folder}"/*
		success "Successfully set permissions for all files in '${target_folder}'"
	else
		warn "Couldn't find any files in '${target_folder}' to set permissions for"
	fi
	unset target_folder
}

# if is_macos; then
# Uninstall and reinstall xcode (useful immediately after upgrade or if reinstalling the OS)
# TODO: Kept for reference purposes
# reinstall_xcode() {
#   # delete if already present
#   delete_directory_if_exists '/Applications/Xcode.app'

#   xcode-select --install
#   sudo xcodebuild -license accept -quiet || true
#   success 'Successfully installed xcode'
# }
# fi

# Wireshark
sshdump() {
	export SSLKEYLOGFILE="/Users/JD/.ssh/sslkeylog.log"
	open -a Firefox
	ssh "$1" "tcpdump -U -s0 -w - 'not port 22 $2'" | tee tcpdump.cap | wireshark -k -i -
}

gitFixModeChanges() {
	git diff --summary | grep --color 'mode change 100755 => 100644' | cut -d' ' -f7- | xargs chmod +x
	git diff --summary | grep --color 'mode change 100644 => 100755' | cut -d' ' -f7- | xargs chmod -x
}

watchhttp() {
	sudo tcpdump -i en0 -n -s 0 -w - | grep -a -o -E "Host\: .*|GET \/.*"
}

# Tar up folder
tarup() {
	tar -zcvf $1
}

# Search Replace
function sr() {
	sed -i "" s/$1/$2/g $3
}

# Checks port number to see what service is attached
port2service() {
	lsof -i -P | grep $1
}

# take this repo and copy it to somewhere else minus the .git stuff.
gitexport() {
	mkdir -p "$1"
	git archive master | tar -x -C "$1"
}

zip_dir() {
	zip -r ${1%.*} $1
}

# All the dig info
digga() {
	dig +nocmd "$1" any +multiline +noall +answer
}

syslog() {
	tail -f /var/log/system.log
}

dpg() {
	echo $(docker ps | grep $1 | cut -f1 -d' ')
}

dkill() {
	docker kill $(dpg $1)
}

dsh() {
	docker exec -it $(dpg $1) /bin/sh
}

dlog() {
	docker logs -f $(docker ps | \grep "$1" | cut -f1 -d" ")
}

docker_image_sha() {
	if [[ -z $1 ]]; then
		echo 'Please provide container name'
	else
		docker container inspect $(docker ps -f Name=$1 -q) | jq -r .[0].Image
	fi
}

listening() {
	if [ $# -eq 0 ]; then
		sudo lsof -iTCP -sTCP:LISTEN -n -P
	elif [ $# -eq 1 ]; then
		sudo lsof -iTCP -sTCP:LISTEN -n -P | grep -i --color $1
	else
		echo "Usage: listening [pattern]"
	fi
}

open_ports() {
	lsof -nP -iTCP:$1 | grep LISTEN
}

# iterm2 integration looks for this function 
# on every command and echos
# a not found string if not defined
iterm2_print_user_vars() { }

#yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
