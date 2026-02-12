#!/bin/bash

# Script to download and install the latest Visual Studio Code for NVIDIA Jetson Orin Nano (ARM64)
# Saves the .deb file with the same name as on the server

set -euo pipefail

DOWNLOAD_DIR="/tmp"
DOWNLOAD_URL="https://update.code.visualstudio.com/latest/linux-deb-arm64/stable"
FALLBACK_FILENAME="vscode_latest_arm64.deb"
DEB_FILE=""

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
  fi
  if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "Please run this script via sudo from your current non-root user account."
    exit 1
  fi
}

install_dependencies() {
  echo "Updating package lists..."
  apt-get update

  echo "Installing required dependencies..."
  apt-get install -y wget apt-transport-https
}

determine_filename() {
  local filename
  filename=$(wget --spider "$DOWNLOAD_URL" 2>&1 | grep -oP 'filename="\K[^"]+' || true)

  if [ -z "$filename" ]; then
    echo "Warning: Could not determine server filename. Using fallback name '$FALLBACK_FILENAME'."
    filename="$FALLBACK_FILENAME"
  fi

  printf '%s\n' "$filename"
}

download_vscode() {
  local filename
  filename=$(determine_filename)
  DEB_FILE="$DOWNLOAD_DIR/$filename"

  echo "Fetching the latest Visual Studio Code ARM64 .deb package..."
  wget -O "$DEB_FILE" "$DOWNLOAD_URL"

  if [ ! -s "$DEB_FILE" ]; then
    echo "Error: Failed to download the .deb package."
    exit 1
  fi

  echo "Downloaded file saved as: $DEB_FILE"
}

cleanup_download() {
  if [ -n "${DEB_FILE:-}" ] && [ -f "$DEB_FILE" ]; then
    echo "Cleaning up..."
    rm -f "$DEB_FILE"
  fi
}

install_vscode() {
  echo "Installing Visual Studio Code..."
  dpkg -i "$DEB_FILE" || {
    echo "Fixing missing dependencies..."
    apt-get install -f -y
  }
}

verify_installation() {
  local current_user="$1"

  echo "Verifying installation..."
  if sudo -u "$current_user" bash -lc 'command -v code >/dev/null 2>&1'; then
    echo "VS Code version:"
    sudo -u "$current_user" bash -lc 'code --version'
    echo "Visual Studio Code installed successfully!"
    return
  fi

  echo "Error: Visual Studio Code installation failed."
  exit 1
}

main() {
  local current_user

  require_root
  current_user="$SUDO_USER"
  echo "Current sudo user: $current_user"

  trap cleanup_download EXIT

  install_dependencies
  download_vscode
  install_vscode
  verify_installation "$current_user"
}

main "$@"
