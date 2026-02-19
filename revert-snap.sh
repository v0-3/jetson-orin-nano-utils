#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2
readonly SNAP_NAME="snapd"
readonly DEFAULT_REVISION="24724"

REVISION="$DEFAULT_REVISION"
ASSERT_FILE=""
SNAP_FILE=""
ASSERT_FILE_PREEXISTED=false
SNAP_FILE_PREEXISTED=false

log_info() {
  local -r message="$1"
  printf '[INFO] %s\n' "$message"
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
Usage: sudo bash ${SCRIPT_NAME} [REVISION]
       sudo bash ${SCRIPT_NAME} --revision REVISION

Download and install a specific snapd revision, then place it on hold.

Options:
  --revision REVISION  snapd revision to install (default: ${DEFAULT_REVISION})
  -h, --help           Show this help message
USAGE
}

parse_args() {
  local positional_revision=""

  while (($#)); do
    case "$1" in
      --revision)
        shift
        if [[ $# -eq 0 ]]; then
          die_usage "Missing value for --revision."
        fi
        REVISION="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -* )
        die_usage "Unknown option: $1"
        ;;
      *)
        if [[ -n "$positional_revision" ]]; then
          die_usage "Too many positional arguments."
        fi
        positional_revision="$1"
        ;;
    esac
    shift
  done

  if [[ -n "$positional_revision" ]]; then
    REVISION="$positional_revision"
  fi
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
  if [[ "${ASSERT_FILE_PREEXISTED:-false}" == false && -n "${ASSERT_FILE:-}" && -f "${ASSERT_FILE}" ]]; then
    rm -f -- "${ASSERT_FILE}"
  fi

  if [[ "${SNAP_FILE_PREEXISTED:-false}" == false && -n "${SNAP_FILE:-}" && -f "${SNAP_FILE}" ]]; then
    rm -f -- "${SNAP_FILE}"
  fi
}

setup_traps() {
  trap 'on_err "$LINENO" "$?" "$BASH_COMMAND"' ERR
  trap on_exit EXIT
  trap 'log_error "Interrupted by SIGINT."; exit 130' SIGINT
  trap 'log_error "Interrupted by SIGTERM."; exit 143' SIGTERM
}

validate_revision() {
  if [[ ! "$REVISION" =~ ^[0-9]+$ ]]; then
    die_usage "Revision must be a numeric value."
  fi
}

prepare_files() {
  ASSERT_FILE="${SNAP_NAME}_${REVISION}.assert"
  SNAP_FILE="${SNAP_NAME}_${REVISION}.snap"
  [[ -e "$ASSERT_FILE" ]] && ASSERT_FILE_PREEXISTED=true
  [[ -e "$SNAP_FILE" ]] && SNAP_FILE_PREEXISTED=true
}

verify_downloaded_files() {
  [[ -s "$ASSERT_FILE" ]] || die "Downloaded assertion file is missing or empty: ${ASSERT_FILE}"
  [[ -s "$SNAP_FILE" ]] || die "Downloaded snap file is missing or empty: ${SNAP_FILE}"
}

main() {
  parse_args "$@"
  validate_revision
  require_root
  setup_traps
  require_cmds snap

  prepare_files

  log_info "Downloading ${SNAP_NAME} revision ${REVISION}..."
  snap download "$SNAP_NAME" --revision="$REVISION"
  verify_downloaded_files

  log_info "Acknowledging assertion file ${ASSERT_FILE}..."
  snap ack "$ASSERT_FILE"

  log_info "Installing snap package ${SNAP_FILE}..."
  snap install "$SNAP_FILE"

  log_info "Placing ${SNAP_NAME} on hold..."
  snap refresh --hold "$SNAP_NAME"

  log_info "Done."
}

main "$@"
