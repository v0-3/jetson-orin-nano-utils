#!/usr/bin/env bash

set -euo pipefail

readonly SNAP_NAME="snapd"
readonly REVISION="${1:-24724}"
readonly ASSERT_FILE="${SNAP_NAME}_${REVISION}.assert"
readonly SNAP_FILE="${SNAP_NAME}_${REVISION}.snap"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

main() {
  require_cmd snap
  require_cmd sudo

  snap download "$SNAP_NAME" --revision="$REVISION"
  sudo snap ack "$ASSERT_FILE"
  sudo snap install "$SNAP_FILE"
  sudo snap refresh --hold "$SNAP_NAME"
}

main "$@"
