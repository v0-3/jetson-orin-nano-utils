#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2

readonly PYENV_VERSION="3.10.12"
readonly TORCH_WHL="torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
readonly TORCHVISION_WHL="torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"
readonly ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.23.0-cp310-cp310-linux_aarch64.whl"
readonly TORCH_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/${TORCH_WHL}"
readonly TORCHVISION_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/${TORCHVISION_WHL}"
readonly CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
readonly CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/${CUDA_KEYRING_DEB}"
readonly CUDA_KEYRING_DEB_PATH="/tmp/${CUDA_KEYRING_DEB}"

USE_VENV=false
CLEAN_CACHE=false
TARGET_USER=""
TARGET_HOME=""
PYENV_ROOT=""
WHEEL_CACHE=""
WORKSPACE_DIR=""
PYTHON_CMD=(python3)

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
Usage: sudo bash ${SCRIPT_NAME} [--venv] [--clean-cache]

Install Jetson-compatible PyTorch/TorchVision wheels with CUDA dependencies.

Options:
  --venv         Create and use TARGET_HOME/Workspace/.venv before installing
  --clean-cache  Remove cached .whl files before downloading
  -h, --help     Show this help message
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --venv)
        USE_VENV=true
        ;;
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
  if [[ -f "$CUDA_KEYRING_DEB_PATH" ]]; then
    rm -f "$CUDA_KEYRING_DEB_PATH"
  fi
}

run_as_target() {
  sudo -H -u "$TARGET_USER" "$@"
}

run_pyenv() {
  run_as_target env \
    PYENV_ROOT="$PYENV_ROOT" \
    PATH="$PYENV_ROOT/bin:$PATH" \
    "$PYENV_ROOT/bin/pyenv" "$@"
}

run_python() {
  "${PYTHON_CMD[@]}" "$@"
}

run_pip() {
  run_python -m pip "$@"
}

configure_target_context() {
  TARGET_USER="$SUDO_USER"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

  if [[ -z "$TARGET_HOME" ]]; then
    die "Could not determine home directory for user '$TARGET_USER'."
  fi

  PYENV_ROOT="${TARGET_HOME}/.pyenv"
  WHEEL_CACHE="${TARGET_HOME}/.cache/pytorch_wheels"
  WORKSPACE_DIR="${TARGET_HOME}/Workspace"
}

setup_pyenv() {
  log_info "Installing pyenv and Python ${PYENV_VERSION}..."

  if ! run_as_target test -d "$PYENV_ROOT"; then
    run_as_target git clone https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
  fi

  run_pyenv install -s "$PYENV_VERSION"
  run_pyenv global "$PYENV_VERSION"

  PYTHON_CMD=(
    sudo -H -u "$TARGET_USER"
    env "PYENV_ROOT=$PYENV_ROOT" "PATH=$PYENV_ROOT/bin:$PATH"
    "$PYENV_ROOT/bin/pyenv" exec python
  )
}

download_if_missing() {
  local filepath="$1"
  local url="$2"

  if ! run_as_target test -f "$filepath"; then
    run_as_target wget "$url" -O "$filepath"
  fi
}

create_venv_if_requested() {
  if [[ "$USE_VENV" == false ]]; then
    log_info "Using pyenv Python (no virtual environment)."
    return
  fi

  log_info "Creating virtual environment..."
  run_as_target mkdir -p "$WORKSPACE_DIR"
  run_python -m venv "${WORKSPACE_DIR}/.venv"

  PYTHON_CMD=(sudo -H -u "$TARGET_USER" "${WORKSPACE_DIR}/.venv/bin/python")
}

verify_install() {
  run_python - <<'PYCODE'
import torch, torchvision

print('Torch:', torch.__version__)
print('TorchVision:', torchvision.__version__)
print('PyTorch CUDA version:', torch.version.cuda)
print('CUDA available:', torch.cuda.is_available())

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

main() {
  parse_args "$@"
  require_root

  trap 'on_err "$LINENO" "$?"' ERR
  trap on_exit EXIT

  require_cmd apt-get
  require_cmd cut
  require_cmd dpkg
  require_cmd getent
  require_cmd git
  require_cmd wget

  configure_target_context

  log_info "Installing PyTorch for Jetson Orin Nano"
  log_info "Target user: ${TARGET_USER}"
  log_info "Updating system packages..."

  apt-get update
  apt-get install -y \
    build-essential \
    ca-certificates \
    git \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libopenblas-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    make \
    tk-dev \
    wget \
    xz-utils \
    zlib1g-dev

  setup_pyenv

  log_info "Installing cuSPARSELt (required by torch 2.5.0)..."
  wget "$CUDA_KEYRING_URL" -O "$CUDA_KEYRING_DEB_PATH"
  dpkg -i "$CUDA_KEYRING_DEB_PATH"
  apt-get update
  apt-get install -y libcusparselt0 libcusparselt-dev

  run_pip uninstall -y torch torchvision || true

  run_as_target mkdir -p "$WHEEL_CACHE"

  if [[ "$CLEAN_CACHE" == true ]]; then
    log_info "Cleaning wheel cache..."
    run_as_target find "$WHEEL_CACHE" -maxdepth 1 -type f -name '*.whl' -delete
  fi

  log_info "Downloading missing wheels (if any)..."
  download_if_missing "$WHEEL_CACHE/$TORCH_WHL" "$TORCH_URL"
  download_if_missing "$WHEEL_CACHE/$TORCHVISION_WHL" "$TORCHVISION_URL"

  create_venv_if_requested

  log_info "Upgrading pip..."
  run_pip install --upgrade pip

  log_info "Installing ONNX Runtime GPU 1.23.0..."
  run_pip install "$ONNXRUNTIME_GPU_WHL_URL"

  log_info "Installing PyTorch and TorchVision..."
  run_pip install --force-reinstall \
    "$WHEEL_CACHE/$TORCH_WHL" \
    "$WHEEL_CACHE/$TORCHVISION_WHL" \
    "numpy<2.0"

  log_info "Verifying installation..."
  verify_install

  log_info "Done."
}

main "$@"
