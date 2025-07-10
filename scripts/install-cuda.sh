# TF compat chart
# https://www.tensorflow.org/install/source#gpu

purge_cuda() {
	sudo apt-get --purge remove "cuda*" "nvidia*"
	sudo rm -r /usr/local/cuda*
}

#https://developer.nvidia.com/cuda-12-5-0-download-archive?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=22.04&target_type=deb_network
install_cuda_12_5_drivers_ubuntu() {

	wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
	sudo dpkg -i cuda-keyring_1.1-1_all.deb
	sudo apt-get update
	sudo apt-get -y install cuda-toolkit-12-5

	sudo apt-get install -y nvidia-driver-555-open
}

install_nvidia_drivers_unbutu() {
	sudo ubuntu-drivers install --gpgpu nvidia:570-server
}

install_cudnn_() {

}

# https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=24.04&target_type=deb_network
install_cuda_12_8_drivers_ubuntu() {
	wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb

	sudo dpkg -i cuda-keyring_1.1-1_all.deb
	sudo apt-get update
	sudo apt-get install -y cuda-toolkit-12-8
	sudo apt-get install -y nvidia-open
	sudo apt-get install -y cudnn-cuda-12

}

#
#https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
install_nvidia_docker_toolkit_() {
	curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
		curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
		sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
			sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
	sudo apt-get update
	sudo apt-get install -y nvidia-container-toolkit

	# this wasn't in docks but needed to generate CDI for docker to know how
	# to pass through GPUs to container
	sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

	sudo nvidia-ctk runtime configure --runtime=docker

	# sudo systemctl restart docker
	sudo snap restart docker

	# Might want to reboot whole machine
	sudo reboot

}

install_docker() {
	# Add Docker's official GPG key:
	sudo apt-get update
	sudo apt-get install ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	# Add the repository to Apt sources:
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |
		sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	sudo apt-get update

	sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

verify() {
	# Verify this
	sudo nvidia-ctk cdi list
	# returns...
	#
	# INFO[0000] Found 3 CDI devices
	# nvidia.com/gpu=0
	# nvidia.com/gpu=GPU-ef035dbe-50a2-c079-a6c5-df8d7886d96b
	# nvidia.com/gpu=all

	#
	docker run --rm --runtime=nvidia --gpus=all nvcr.io/nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04 nvidia-smi
}

install_nvidia_???() {
	sudo apt-get update
	sudo apt-get install ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r docker pull nvidia/cuda/etc/apt/keyrings/docker.asc
}
