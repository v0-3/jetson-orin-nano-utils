#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2

readonly TORCH_WHL="torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
readonly TORCHVISION_WHL="torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"
readonly ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.23.0-cp310-cp310-linux_aarch64.whl"
readonly TORCH_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/${TORCH_WHL}"
readonly TORCHVISION_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/${TORCHVISION_WHL}"
readonly CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
readonly CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/${CUDA_KEYRING_DEB}"

CLEAN_CACHE=false
TARGET_USER=""
TARGET_HOME=""
WHEEL_CACHE=""
TMP_DIR=""
CUDA_KEYRING_DEB_PATH=""
PYTHON_CMD=(python3)

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
Usage: sudo bash ${SCRIPT_NAME} [--clean-cache]

Install Jetson-compatible PyTorch/TorchVision wheels with CUDA dependencies
using the system Python.

Options:
  --clean-cache  Remove cached .whl files before downloading
  -h, --help     Show this help message
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --clean-cache)
        CLEAN_CACHE=true
        ;;
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

run_as_target() {
  sudo -H -u "$TARGET_USER" "$@"
}

run_python() {
  "${PYTHON_CMD[@]}" "$@"
}

run_pip() {
  run_python -m pip "$@"
}

configure_target_context() {
  local passwd_entry=""

  TARGET_USER="$SUDO_USER"
  passwd_entry="$(getent passwd "$TARGET_USER" || true)"
  [[ -n "$passwd_entry" ]] || die "Could not resolve passwd entry for user '$TARGET_USER'."
  TARGET_HOME="$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"

  if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    die "Could not determine home directory for user '$TARGET_USER'."
  fi

  WHEEL_CACHE="${TARGET_HOME}/.cache/pytorch_wheels"
}

assert_system_python_compatibility() {
  local py_version=""

  py_version="$(python3 - <<'PYCODE'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PYCODE
)"

  if [[ "$py_version" != "3.10" ]]; then
    die "System python3 version must be 3.10 for cp310 wheels; found ${py_version}."
  fi

  log_info "Using system python3 ${py_version}."
}

download_if_missing() {
  local -r filepath="$1"
  local -r url="$2"

  if run_as_target test -s "$filepath"; then
    return
  fi

  run_as_target wget "$url" -O "$filepath"
  run_as_target test -s "$filepath" || die "Downloaded wheel is missing or empty: $filepath"
}

install_system_packages() {
  log_info "Updating system packages..."
  apt-get update
  apt-get install -y \
    build-essential \
    ca-certificates \
    libopenblas-dev \
    python3 \
    python3-pip \
    wget
}

install_cuda_dependencies() {
  log_info "Installing cuSPARSELt (required by torch 2.5.0)..."
  wget "$CUDA_KEYRING_URL" -O "$CUDA_KEYRING_DEB_PATH"
  dpkg -i "$CUDA_KEYRING_DEB_PATH"
  apt-get update
  apt-get install -y libcusparselt0 libcusparselt-dev
}

prepare_wheels() {
  run_pip uninstall -y torch torchvision || true
  run_as_target mkdir -p "$WHEEL_CACHE"
  run_as_target test -d "$WHEEL_CACHE" || die "Could not create wheel cache directory: $WHEEL_CACHE"

  if [[ "$CLEAN_CACHE" == true ]]; then
    log_info "Cleaning wheel cache..."
    run_as_target find "$WHEEL_CACHE" -maxdepth 1 -type f -name '*.whl' -delete
  fi

  log_info "Downloading missing wheels (if any)..."
  download_if_missing "$WHEEL_CACHE/$TORCH_WHL" "$TORCH_URL"
  download_if_missing "$WHEEL_CACHE/$TORCHVISION_WHL" "$TORCHVISION_URL"
}

install_python_packages() {
  log_info "Upgrading pip..."
  run_pip install --upgrade pip

  log_info "Installing ONNX Runtime GPU 1.23.0..."
  run_pip install "$ONNXRUNTIME_GPU_WHL_URL"

  log_info "Installing PyTorch and TorchVision..."
  run_pip install --force-reinstall \
    "$WHEEL_CACHE/$TORCH_WHL" \
    "$WHEEL_CACHE/$TORCHVISION_WHL" \
    "numpy<2.0"
}

verify_install() {
  run_python - <<'PYCODE'
import numpy, torch, torchvision

print('Torch:', torch.__version__)
print('TorchVision:', torchvision.__version__)
print('NumPy:', numpy.__version__)
print('PyTorch CUDA version:', torch.version.cuda)
print('CUDA available:', torch.cuda.is_available())

if int(numpy.__version__.split('.')[0]) >= 2:
    raise RuntimeError('NumPy must be < 2.0 for this setup.')

if torch.cuda.is_available():
    name = torch.cuda.get_device_name(0)
    major, minor = torch.cuda.get_device_capability(0)
    capability = f'{major}.{minor}'

    arch_map = {
        '5.3': 'Maxwell (Jetson TX1)',
        '6.2': 'Pascal (Jetson TX2)',
        '7.2': 'Volta (Jetson Xavier NX, AGX Xavier)',
        '8.7': 'Ampere (Jetson Orin Series)',
        '8.9': 'Ada Lovelace',
        '9.0': 'Hopper',
    }

    arch_name = arch_map.get(capability, 'Unknown or future architecture')

    print(f'CUDA device name: {name}')
    print(f'CUDA device capability: {capability} -> {arch_name}')
PYCODE
}

setup_environment() {
  require_root
  setup_traps
  require_cmds apt-get cut dpkg find getent mktemp python3 sudo wget
  TMP_DIR="$(mktemp -d)"
  CUDA_KEYRING_DEB_PATH="${TMP_DIR}/${CUDA_KEYRING_DEB}"
  configure_target_context

  log_info "Installing PyTorch for Jetson Orin Nano"
  log_info "Target user: ${TARGET_USER}"
}

final_checks() {
  log_info "Verifying installation..."
  verify_install
  log_info "Done."
}

main() {
  parse_args "$@"
  setup_environment
  install_system_packages
  assert_system_python_compatibility
  install_cuda_dependencies
  prepare_wheels
  install_python_packages
  final_checks
}

main "$@"
