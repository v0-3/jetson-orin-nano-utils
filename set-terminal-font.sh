#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2
readonly TARGET_FONT="JetBrains Mono 14"
readonly SCHEMA_PROFILES="org.gnome.Terminal.ProfilesList"
readonly PROFILE_PATH_PREFIX="/org/gnome/terminal/legacy/profiles:/:"

DEFAULT_PROFILE_UUID=""
PROFILE_PATH=""

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

warn_if_snap_terminal_installed() {
  if command -v snap >/dev/null 2>&1 && snap list gnome-terminal >/dev/null 2>&1; then
    log_warn "Detected Snap-based gnome-terminal; settings may not apply as expected."
    log_warn "If needed: sudo snap remove gnome-terminal && sudo apt update && sudo apt install gnome-terminal"
  fi
}

validate_schema() {
  if ! gsettings list-schemas | grep -Fxq "$SCHEMA_PROFILES"; then
    die "Schema '${SCHEMA_PROFILES}' not found. Ensure GNOME Terminal is installed."
  fi
}

resolve_default_profile_uuid() {
  local raw_default=""
  local profile_list_raw=""
  local first_profile_uuid=""

  raw_default="$(gsettings get "$SCHEMA_PROFILES" default)"
  DEFAULT_PROFILE_UUID="$(tr -d "'" <<<"$raw_default")"

  if [[ -n "$DEFAULT_PROFILE_UUID" ]]; then
    return
  fi

  profile_list_raw="$(gsettings get "$SCHEMA_PROFILES" list)"
  first_profile_uuid="$(sed -e "s/^[^']*'//" -e "s/'.*//" <<<"$profile_list_raw" | head -n 1)"

  if [[ -z "$first_profile_uuid" ]]; then
    die "No GNOME Terminal profiles found. Set up a profile first in Terminal preferences."
  fi

  DEFAULT_PROFILE_UUID="$first_profile_uuid"
  gsettings set "$SCHEMA_PROFILES" default "'${DEFAULT_PROFILE_UUID}'"
  log_info "No default profile set; using first profile '${DEFAULT_PROFILE_UUID}'."
}

build_profile_path() {
  PROFILE_PATH="${PROFILE_PATH_PREFIX}${DEFAULT_PROFILE_UUID}/"
}

apply_font_settings() {
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

  trap 'on_err "$LINENO" "$?"' ERR

  require_cmd dconf
  require_cmd gsettings
  require_cmd grep
  require_cmd head
  require_cmd sed
  require_cmd tr

  warn_if_snap_terminal_installed
  validate_schema
  resolve_default_profile_uuid
  build_profile_path
  apply_font_settings
  verify_font_settings

  log_info "GNOME Terminal font set to '${TARGET_FONT}'. Open a new terminal window to see the change."
}

main "$@"
