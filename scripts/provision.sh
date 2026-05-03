#!/usr/bin/env zsh

OS=$(uname)

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

is_non_zero_string() {
	! test -z "${1}"
}

is_directory() {
	is_non_zero_string "${1}" && test -d "${1}"
}

DOTFILES_DIR="$HOME/projects/dotfiles"

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

keep_sudo_alive()

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

####################
# Install dotfiles #
####################
section_header "Installing dotfiles into '$(yellow "${DOTFILES_DIR}")'"
if is_non_zero_string "${DOTFILES_DIR}" && ! is_directory "${DOTFILES_DIR}"; then
	
	# Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
	rm -rf "${HOME}/.zshrc"

	# Note: Cloning with https since the ssh keys will not be present at this time
	clone_repo_into "https://github.com/jondum/dotfiles" "${DOTFILES_DIR}"

else
	warn "skipping cloning the dotfiles repo since '${DOTFILES_DIR}' is either not defined or is already a git repo"
fi

####################
# Install Flox #
####################
section_header "Installing Flox"
if ! command_exists flox; then
  sh "${DOTFILES_DIR}/scripts/install-flox.sh"
  success 'Successfully installed Flox'
else
  warn "skipping installation of Flox since it's already installed"
fi

# Activate Flox environment (installs packages from manifest.toml)
if command_exists flox; then
  section_header "Activating Flox environment"
  source "${DOTFILES_DIR}/packages/shell/.config/zsh/env.sh"
  eval "$(flox activate -d $XDG_DATA_HOME/flox -m run)"
  success 'Successfully activated Flox environment'
fi

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
  brew bundle check --file="${DOTFILES_DIR}/packages/homebrew/.config/homebrew/Brewfile.homebrew-only" || \
    brew bundle --file="${DOTFILES_DIR}/packages/homebrew/.config/homebrew/Brewfile.homebrew-only" || true
  success 'Successfully installed homebrew-only packages'

fi

if [[ $OS == Linux ]]; then

	section_header 'Installing basic utils (Flox handles most packages)'
	
	# Flox activation will handle most packages via manifest.toml
	# Install only system-level packages via apt
	sudo apt update

  sudo apt install -y \
    avahi-daemon \
    g++ \
		clang \
    make \
    llvm \
		ca-certificates \
		curl \
    git-lfs \
    libpq-dev \
    watchman \
		software-properties-common \
    zsh \
    sudo

		section_header 'Installing Docker'
		for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
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

		sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

		# add user to docker grouput
		sudo groupadd docker
		sudo usermod -aG docker $USER
		sudo chmod 666 /var/run/docker.sock

		sudo service docker start

		sudo chsh $USER -s $(which zsh)

fi

section_header 'Creating symlinks in home folder'

sh "${DOTFILES_DIR}/scripts/create-links.sh"

# Grab rest of env vars and config
source "${DOTFILES_DIR}/packages/shell/.zshenv"

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

echo Creating zsh HISTFILE $HISTFILE
touch $HISTFILE


section_header 'Installing proto (node + more)'
curl -fsSL https://moonrepo.dev/install/proto.sh | bash
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
proto install node
proto pin node --global
proto install npm
proto install pnpm

section_header 'Installing uv (python)'
curl -LsSf https://astral.sh/uv/install.sh | sh
source $
uv python install


################################
# Recreate the zsh completions #
################################
section_header 'Recreate zsh completions'
rm -rf "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"
autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"

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

echo "\n"
success '** Finished auto installation process: MANUALLY QUIT AND RESTART iTerm2 and Terminal apps **'
echo "$(yellow "Remember to set the 'RAYCAST_SETTINGS_PASSWORD' env var, and then run the 'capture-raycast-configs.sh' script to import your Raycast configuration into the new machine.")"

script_end_time=$(date +%s)
echo "==> Script completed at: $(date)"
echo "==> Total execution time: $((script_end_time - script_start_time)) seconds"
