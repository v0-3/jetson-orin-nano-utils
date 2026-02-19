#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2
readonly TARGET_FONT="JetBrains Mono 14"
readonly SCHEMA_PROFILES="org.gnome.Terminal.ProfilesList"
readonly PROFILE_PATH_PREFIX="/org/gnome/terminal/legacy/profiles:/:"

DEFAULT_PROFILE_UUID=""
PROFILE_PATH=""

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
Usage: bash ${SCRIPT_NAME}

Set GNOME Terminal font to '${TARGET_FONT}' for the default profile.
Run this script as your normal user (not with sudo).

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

require_non_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "Run this script directly as your regular user, not with sudo."
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

setup_traps() {
  trap 'on_err "$LINENO" "$?" "$BASH_COMMAND"' ERR
  trap 'log_error "Interrupted by SIGINT."; exit 130' SIGINT
  trap 'log_error "Interrupted by SIGTERM."; exit 143' SIGTERM
}

warn_if_snap_terminal_installed() {
  if command -v snap >/dev/null 2>&1 && snap list gnome-terminal >/dev/null 2>&1; then
    log_warn "Detected Snap-based gnome-terminal; settings may not apply as expected."
    log_warn "If needed: sudo snap remove gnome-terminal && sudo apt update && sudo apt install gnome-terminal"
  fi
}

validate_schema() {
  if ! gsettings get "$SCHEMA_PROFILES" default >/dev/null 2>&1; then
    die "Schema '${SCHEMA_PROFILES}' not found. Ensure GNOME Terminal is installed."
  fi
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_single_quotes() {
  local value="$1"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

resolve_default_profile_uuid() {
  local raw_default=""
  local profile_list_raw=""
  local profile_list=""

  raw_default="$(gsettings get "$SCHEMA_PROFILES" default)"
  DEFAULT_PROFILE_UUID="$(strip_single_quotes "$raw_default")"
  DEFAULT_PROFILE_UUID="$(trim_whitespace "$DEFAULT_PROFILE_UUID")"

  if [[ -n "$DEFAULT_PROFILE_UUID" ]]; then
    return
  fi

  profile_list_raw="$(gsettings get "$SCHEMA_PROFILES" list)"
  profile_list_raw="${profile_list_raw#@as }"
  profile_list="${profile_list_raw#[}"
  profile_list="${profile_list%]}"
  profile_list="$(trim_whitespace "$profile_list")"

  if [[ -z "$profile_list" ]]; then
    die "No GNOME Terminal profiles found. Set up a profile first in Terminal preferences."
  fi

  DEFAULT_PROFILE_UUID="${profile_list%%,*}"
  DEFAULT_PROFILE_UUID="$(trim_whitespace "$DEFAULT_PROFILE_UUID")"
  DEFAULT_PROFILE_UUID="$(strip_single_quotes "$DEFAULT_PROFILE_UUID")"
  DEFAULT_PROFILE_UUID="$(trim_whitespace "$DEFAULT_PROFILE_UUID")"

  if [[ -z "$DEFAULT_PROFILE_UUID" ]]; then
    die "No GNOME Terminal profiles found. Set up a profile first in Terminal preferences."
  fi

  gsettings set "$SCHEMA_PROFILES" default "'${DEFAULT_PROFILE_UUID}'"
  log_info "No default profile set; using first profile '${DEFAULT_PROFILE_UUID}'."
}

build_profile_path() {
  PROFILE_PATH="${PROFILE_PATH_PREFIX}${DEFAULT_PROFILE_UUID}/"
}

apply_font_settings() {
  local current_font=""
  local current_use_sys=""

  current_font="$(dconf read "${PROFILE_PATH}font")"
  current_use_sys="$(dconf read "${PROFILE_PATH}use-system-font")"

  if [[ "$current_font" == "'${TARGET_FONT}'" && "$current_use_sys" == "false" ]]; then
    log_info "GNOME Terminal font already set to '${TARGET_FONT}'."
    return
  fi

  dconf write "${PROFILE_PATH}use-system-font" "false"
  dconf write "${PROFILE_PATH}font" "'${TARGET_FONT}'"
}

verify_font_settings() {
  local final_font=""
  local final_use_sys=""

  final_font="$(dconf read "${PROFILE_PATH}font")"
  final_use_sys="$(dconf read "${PROFILE_PATH}use-system-font")"

  if [[ "$final_font" != "'${TARGET_FONT}'" || "$final_use_sys" != "false" ]]; then
    die "Verification failed after applying terminal font settings."
  fi
}

main() {
  parse_args "$@"
  require_non_root
  setup_traps
  require_cmds dconf gsettings

  warn_if_snap_terminal_installed
  validate_schema
  resolve_default_profile_uuid
  build_profile_path
  apply_font_settings
  verify_font_settings

  log_info "GNOME Terminal font set to '${TARGET_FONT}'. Open a new terminal window to see the change."
}

main "$@"
