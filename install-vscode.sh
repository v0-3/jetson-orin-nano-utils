#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2

readonly DOWNLOAD_URL="https://update.code.visualstudio.com/latest/linux-deb-arm64/stable"
readonly VSCODE_DEB_FILENAME="vscode_latest_arm64.deb"

DEB_FILE=""
TARGET_USER=""
TMP_DIR=""

log_info() {
  local -r message="$1"
  printf '[INFO] %s\n' "$message"
}

log_warn() {
  local -r message="$1"
  printf '[WARN] %s\n' "$message"
}

log_error() {
  local -r message="$1"
  printf '[ERROR] %s\n' "$message" >&2
}

die() {
  local -r message="$1"
  log_error "$message"
  exit "$EXIT_RUNTIME_ERROR"
}

die_usage() {
  local -r message="$1"
  log_error "$message"
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

require_cmds() {
  local cmd=""
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Required command not found: $cmd"
    fi
  done
}

on_err() {
  local -r line_no="$1"
  local -r exit_code="$2"
  local -r failed_command="$3"
  log_error "Command failed at line ${line_no} with exit code ${exit_code}: ${failed_command}"
  exit "$exit_code"
}

on_exit() {
  if [[ -n "${DEB_FILE:-}" && -f "${DEB_FILE}" ]]; then
    log_info "Cleaning up downloaded package..."
    rm -f -- "${DEB_FILE}"
  fi

  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]]; then
    rm -rf -- "${TMP_DIR}"
  fi
}

setup_traps() {
  trap 'on_err "$LINENO" "$?" "$BASH_COMMAND"' ERR
  trap on_exit EXIT
  trap 'log_error "Interrupted by SIGINT."; exit 130' SIGINT
  trap 'log_error "Interrupted by SIGTERM."; exit 143' SIGTERM
}

install_dependencies() {
  log_info "Updating package lists..."
  apt-get update

  log_info "Installing required dependencies..."
  apt-get install -y wget apt-transport-https
}

download_vscode() {
  TMP_DIR="$(mktemp -d)"
  DEB_FILE="${TMP_DIR}/${VSCODE_DEB_FILENAME}"

  log_info "Fetching latest Visual Studio Code ARM64 .deb package..."
  wget -O "$DEB_FILE" "$DOWNLOAD_URL"

  if [[ ! -s "$DEB_FILE" ]]; then
    die "Failed to download the .deb package."
  fi

  log_info "Downloaded file saved as: $DEB_FILE"
}

install_vscode() {
  log_info "Installing Visual Studio Code..."
  if ! dpkg -i "$DEB_FILE"; then
    log_warn "Fixing missing dependencies..."
    apt-get install -f -y
  fi
}

verify_package_installation() {
  local package_status=""
  package_status="$(dpkg-query -W -f='${Status}' code 2>/dev/null || true)"
  [[ "$package_status" == "install ok installed" ]] || die "Visual Studio Code package is not installed."
}

verify_installation() {
  log_info "Verifying installation..."
  verify_package_installation

  if sudo -u "$TARGET_USER" bash -lc 'command -v code >/dev/null 2>&1'; then
    log_info "VS Code version:"
    sudo -u "$TARGET_USER" bash -lc 'code --version'
    log_info "Visual Studio Code installed successfully."
    return
  fi

  die "Visual Studio Code installation failed."
}

main() {
  parse_args "$@"
  require_root
  setup_traps
  require_cmds apt-get dpkg dpkg-query mktemp sudo wget

  TARGET_USER="$SUDO_USER"
  log_info "Target user: $TARGET_USER"

  install_dependencies
  download_vscode
  install_vscode
  verify_installation
}

main "$@"
