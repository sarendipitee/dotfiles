#!/usr/bin/env bash

set -Eeo pipefail

OS=$(uname -s)

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

is_non_zero_string() {
	! test -z "${1}"
}

is_directory() {
	is_non_zero_string "${1}" && test -d "${1}"
}

command_exists() {
	command -v "${1}" >/dev/null 2>&1
}

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
DOTFILES_DIR=$(realpath "${SCRIPT_DIR}/..")

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export PROJECTS_BASE_DIR="${PROJECTS_BASE_DIR:-$HOME/projects}"
export PERSONAL_BIN_DIR="${PERSONAL_BIN_DIR:-$HOME/.my/bin}"
export PERSONAL_AUTOLOAD_DIR="${PERSONAL_AUTOLOAD_DIR:-$HOME/.my/autoload}"
export HISTFILE="${HISTFILE:-$XDG_STATE_HOME/zsh/history}"

ARCH=$(uname -m)
if [[ "${ARCH}" == arm* ]]; then
	export HOMEBREW_PREFIX="/opt/homebrew"
else
	export HOMEBREW_PREFIX="/usr/local"
fi

source "${DOTFILES_DIR}/packages/shell/.config/zsh/colors.sh"
source "${DOTFILES_DIR}/packages/shell/.config/zsh/functions.sh"

script_start_time=$(date +%s)
echo "==> Script started at: $(date)"

#############################################################
# Utility funcs used only within this script #
#############################################################

section_header() {
  echo "$(blue '==>') $(purple "${1}")"
}

keep_sudo_alive() {
	section_header 'Keeping sudo alive till this script has finished'
	sudo -v
	while true; do
		sudo -n true
		sleep 60
		kill -0 "$$" || exit
	done 2>/dev/null &
}

###############################################################################################
# Ask for the administrator password upfront and keep it alive until this script has finished #
###############################################################################################

keep_sudo_alive

###############################
# Do not allow rootless login #
###############################
# Note: Commented out since I am not sure if we need to do this on the office MBP or not
# section_header 'Verifying rootless status'
# [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]] && error "csrutil ('rootless') is enabled. Please disable in boot screen and run again!"

##################################
# Install command line dev tools #
##################################
if [[ $OS == Darwin ]]; then
  section_header 'Installing xcode command-line tools'
  if ! is_directory '/Library/Developer/CommandLineTools/usr/bin'; then
    # install using the non-gui cmd-line alone
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    sudo softwareupdate -ia --agree-to-license --force
    rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    success 'Successfully installed xcode command-line tools'
  else
    warn 'skipping installation of xcode command-line tools since its already present'
  fi
fi

section_header "Provisioning dotfiles from '$(yellow "${DOTFILES_DIR}")'"

#####################################
# Install system bootstrap packages #
#####################################
if [[ $OS == Linux ]]; then
	section_header 'Installing Ubuntu system packages'
	sudo apt-get update
	sudo apt-get install -y \
		avahi-daemon \
		ca-certificates \
		clang \
		curl \
		g++ \
		git-lfs \
		libpq-dev \
		llvm \
		make \
		openssh-server \
		software-properties-common \
		sudo \
		ubuntu-drivers-common \
		watchman \
		zsh

	sudo chsh -s "$(command -v zsh)" "$USER"

	section_header 'Setting up OpenSSH server'
	sudo sshd -t
	sudo systemctl enable --now ssh
	if command_exists ufw && sudo ufw status | grep -q '^Status: active'; then
		sudo ufw allow OpenSSH
	fi
	sudo systemctl is-active --quiet ssh || error 'OpenSSH server failed to start'
	success 'OpenSSH server is enabled and running'
fi

####################
# Install Flox #
####################
section_header "Installing Flox"
if ! command_exists flox; then
  bash "${DOTFILES_DIR}/scripts/install-flox.sh"
  success 'Successfully installed Flox'
else
  warn "skipping installation of Flox since it's already installed"
fi

command_exists flox || error 'Flox installation completed without a usable flox command'

GLOBAL_FLOX_ENV="${DOTFILES_DIR}/packages/flox/envs/global"
is_file "${GLOBAL_FLOX_ENV}/.flox/env/manifest.toml" || \
	error "Global Flox environment missing: ${GLOBAL_FLOX_ENV}"

section_header "Activating global Flox environment"
export FLOX_SHELL=bash
if ! flox_activation=$(flox activate -d "${GLOBAL_FLOX_ENV}" -m run); then
	error 'Failed to activate global Flox environment'
fi
eval "$flox_activation"
unset flox_activation
command_exists stow || error "Global Flox environment activated without required 'stow' command"
success 'Successfully activated global Flox environment'

section_header 'Creating symlinks in home folder'
bash "${DOTFILES_DIR}/scripts/create-links.sh"

####################
# Install homebrew #
####################
if [[ $OS == Darwin ]]; then

  section_header "Installing homebrew into '$(yellow "${HOMEBREW_PREFIX}")'"
  if ! command_exists brew; then
    # Prep for installing homebrew
    sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
    sudo chown -fR "$(whoami)":admin "${HOMEBREW_PREFIX}"
    chmod u+w "${HOMEBREW_PREFIX}"

    NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success 'Successfully installed homebrew'

    eval "$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
  else
    warn "skipping installation of homebrew since it's already installed"
  fi

  # Install only Homebrew-only packages (GUI apps, displayplacer, etc.)
  # Flox handles most CLI tools now
  section_header "Installing Homebrew-only packages (GUI apps, etc.)"
  brew bundle check --file="${DOTFILES_DIR}/packages/homebrew/.config/homebrew/Brewfile" || \
    brew bundle --file="${DOTFILES_DIR}/packages/homebrew/.config/homebrew/Brewfile" || true
  success 'Successfully installed homebrew-only packages'

fi

if [[ $OS == Linux ]]; then
		section_header 'Installing Docker'
		for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
			sudo apt-get remove -y "$pkg" || true
		done
		sudo apt-get update
		sudo install -m 0755 -d /etc/apt/keyrings -y
		sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc

		# Add the repository to Apt sources:
		echo \
			"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
			$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
			sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update

		sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

		# Add the login user to Docker without making the daemon socket world-writable.
		sudo groupadd -f docker
		sudo usermod -aG docker "$USER"
		sudo systemctl enable --now docker

		section_header 'Installing GPU compute stack'
		if ! command_exists nvidia-smi; then
			sudo ubuntu-drivers install --gpgpu nvidia:570-server || sudo ubuntu-drivers install
		fi
		if ! command_exists nvcc; then
			bash "${DOTFILES_DIR}/scripts/install-cuda.sh" --toolkit
		fi
		bash "${DOTFILES_DIR}/scripts/install-cuda.sh" --container-toolkit

fi

#########################
# Setup Tailscale #
#########################
section_header 'Setting up Tailscale'

if [[ $OS == Darwin ]]; then
  if ! command_exists tailscale; then
    section_header 'Installing Tailscale via Homebrew'
    brew install tailscale
    success 'Tailscale installed'
  fi

  section_header 'Starting tailscaled via launchd'
  sudo brew services start tailscale 2>/dev/null || true
  success 'tailscaled service started'

elif [[ $OS == Linux ]]; then
  if ! command_exists tailscale; then
    section_header 'Installing Tailscale'
    sh <(curl -fsSL https://tailscale.com/install.sh)
    success 'Tailscale installed'
  fi
fi

if command_exists tailscale; then
  if ! tailscale status 2>/dev/null >/dev/null; then
    warn 'Tailscale installed but not authenticated. Run: tailscale up'
  else
    success 'Tailscale is authenticated and running'
  fi
fi

#################################################################################
# Ensure that some of the directories corresponding to the env vars are created #
#################################################################################
section_header 'Creating config/cache directories'
ensure_dir_exists "${DOTFILES_DIR}"
ensure_dir_exists "${PROJECTS_BASE_DIR}"
ensure_dir_exists "${PERSONAL_BIN_DIR}"
ensure_dir_exists "${XDG_CACHE_HOME}"
ensure_dir_exists "${XDG_CONFIG_HOME}"
ensure_dir_exists "${XDG_DATA_HOME}"
ensure_dir_exists "${XDG_STATE_HOME}"

ensure_dir_exists "${XDG_CACHE_HOME}/zsh"
ensure_dir_exists "${XDG_STATE_HOME}/zsh"

printf 'Creating zsh HISTFILE %s\n' "$HISTFILE"
touch "$HISTFILE"

################################
# Recreate the zsh completions #
################################
section_header 'Recreate zsh completions'
zsh -lic 'rm -f "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"; autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"'

section_header 'Validating Zsh, Flox, Stow, and Antidote'
zsh -lic 'command -v flox >/dev/null && command -v stow >/dev/null && command -v antidote >/dev/null'
success 'Zsh loaded with Flox, Stow, and Antidote'

#################################
# Setup ssh scripts/directories #
#################################
section_header 'Setting ssh config file permissions'
set_ssh_folder_permissions

###################
# Setup cron jobs #
###################
section_header 'Setup cron jobs'
if command_exists recron; then
	recron
	success 'Successfully setup cron jobs'
else
	warn "skipping setting up of cron jobs since 'recron' couldn't be found in the PATH; Please set it up manually"
fi

###############################
# Cleanup temp functions, etc #
###############################
# unfunction clone_omz_plugin_if_not_present

printf '\n\n'
success '** Finished auto installation process: MANUALLY QUIT AND RESTART iTerm2 and Terminal apps **'
yellow "Remember to set the 'RAYCAST_SETTINGS_PASSWORD' env var, and then run the 'capture-raycast-configs.sh' script to import your Raycast configuration into the new machine."
printf '\n'

script_end_time=$(date +%s)
echo "==> Script completed at: $(date)"
echo "==> Total execution time: $((script_end_time - script_start_time)) seconds"
