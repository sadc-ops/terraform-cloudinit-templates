#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SCRIPT_NAME" "$1"
}

install_docker() {
  log "Installing Docker Engine..."

  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl

  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${codename} stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -qq
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  log "Docker installed successfully."
}

has_nvidia_driver() {
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    return 0
  fi
  return 1
}

install_nvidia_docker() {
  log "Installing NVIDIA Container Toolkit..."

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
    sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

  sudo apt-get update -qq
  sudo apt-get install -y nvidia-container-toolkit

  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker

  log "NVIDIA Container Toolkit installed and Docker runtime configured."
}

main() {
  install_docker

  if has_nvidia_driver; then
    install_nvidia_docker
  else
    log "NVIDIA driver not detected — skipping GPU support installation."
  fi
}

main "$@"