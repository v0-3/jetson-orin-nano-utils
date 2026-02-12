#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2

readonly DOWNLOAD_DIR="/tmp"
readonly DOWNLOAD_URL="https://update.code.visualstudio.com/latest/linux-deb-arm64/stable"
readonly FALLBACK_FILENAME="vscode_latest_arm64.deb"

DEB_FILE=""
CURRENT_USER=""

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

die() {
  log_error "$1"
  exit "$EXIT_RUNTIME_ERROR"
}

die_usage() {
  log_error "$1"
  log_error "Run '${SCRIPT_NAME} --help' for usage."
  exit "$EXIT_USAGE_ERROR"
}

usage() {
  cat <<USAGE
Usage: sudo bash ${SCRIPT_NAME}

Download and install the latest stable ARM64 Visual Studio Code .deb package.

Options:
  -h, --help  Show this help message
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die_usage "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run this script with sudo."
  fi

  if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    die "Please run this script via sudo from your non-root user account."
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Required command not found: $cmd"
  fi
}

on_err() {
  local line_no="$1"
  local exit_code="$2"
  log_error "Command failed at line ${line_no} with exit code ${exit_code}."
  exit "$exit_code"
}

on_exit() {
  if [[ -n "$DEB_FILE" && -f "$DEB_FILE" ]]; then
    log_info "Cleaning up downloaded package..."
    rm -f "$DEB_FILE"
  fi
}

determine_filename() {
  local filename
  filename="$(wget --spider "$DOWNLOAD_URL" 2>&1 | grep -oP 'filename="\K[^"]+' || true)"

  if [[ -z "$filename" ]]; then
    log_warn "Could not determine server filename. Using fallback '$FALLBACK_FILENAME'."
    filename="$FALLBACK_FILENAME"
  fi

  printf '%s\n' "$filename"
}

download_vscode() {
  local filename
  filename="$(determine_filename)"
  DEB_FILE="${DOWNLOAD_DIR}/${filename}"

  log_info "Fetching latest Visual Studio Code ARM64 .deb package..."
  wget -O "$DEB_FILE" "$DOWNLOAD_URL"

  if [[ ! -s "$DEB_FILE" ]]; then
    die "Failed to download the .deb package."
  fi

  log_info "Downloaded file saved as: $DEB_FILE"
}

install_dependencies() {
  log_info "Updating package lists..."
  apt-get update

  log_info "Installing required dependencies..."
  apt-get install -y wget apt-transport-https
}

install_vscode() {
  log_info "Installing Visual Studio Code..."
  if ! dpkg -i "$DEB_FILE"; then
    log_warn "Fixing missing dependencies..."
    apt-get install -f -y
  fi
}

verify_installation() {
  log_info "Verifying installation..."

  if sudo -u "$CURRENT_USER" bash -lc 'command -v code >/dev/null 2>&1'; then
    log_info "VS Code version:"
    sudo -u "$CURRENT_USER" bash -lc 'code --version'
    log_info "Visual Studio Code installed successfully."
    return
  fi

  die "Visual Studio Code installation failed."
}

main() {
  parse_args "$@"
  require_root

  trap 'on_err "$LINENO" "$?"' ERR
  trap on_exit EXIT

  require_cmd apt-get
  require_cmd dpkg
  require_cmd grep
  require_cmd sudo
  require_cmd wget

  CURRENT_USER="$SUDO_USER"
  log_info "Target user: $CURRENT_USER"

  install_dependencies
  download_vscode
  install_vscode
  verify_installation
}

main "$@"
