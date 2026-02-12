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
EXPECTED_PYENV_PYTHON=""
EXPECTED_VENV_PYTHON=""
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
Fails fast if runtime Python is not pyenv-managed (or a venv based on it).

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
  EXPECTED_PYENV_PYTHON="${PYENV_ROOT}/versions/${PYENV_VERSION}/bin/python"
  EXPECTED_VENV_PYTHON="${WORKSPACE_DIR}/.venv/bin/python"
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

python_runtime_metadata() {
  run_python - <<'PYCODE'
import os
import sys

print(f"executable={os.path.realpath(sys.executable)}")
print(f"prefix={os.path.realpath(sys.prefix)}")
print(f"base_prefix={os.path.realpath(sys.base_prefix)}")
PYCODE
}

assert_python_provenance() {
  local pyenv_which_python=""
  local runtime_executable=""
  local runtime_prefix=""
  local runtime_base_prefix=""
  local key=""
  local value=""
  local expected_pyenv_prefix="${PYENV_ROOT}/versions/${PYENV_VERSION}"
  local expected_venv_prefix="${WORKSPACE_DIR}/.venv"

  pyenv_which_python="$(run_pyenv which python)"
  if [[ "$pyenv_which_python" != "$EXPECTED_PYENV_PYTHON" ]]; then
    die "pyenv resolved python to '$pyenv_which_python' but expected '$EXPECTED_PYENV_PYTHON'."
  fi

  while IFS='=' read -r key value; do
    case "$key" in
      executable)
        runtime_executable="$value"
        ;;
      prefix)
        runtime_prefix="$value"
        ;;
      base_prefix)
        runtime_base_prefix="$value"
        ;;
    esac
  done < <(python_runtime_metadata)

  if [[ -z "$runtime_executable" || -z "$runtime_prefix" || -z "$runtime_base_prefix" ]]; then
    die "Could not determine Python runtime metadata for provenance checks."
  fi

  if [[ "$USE_VENV" == false ]]; then
    if [[ "$runtime_executable" != "$EXPECTED_PYENV_PYTHON" ]]; then
      die "Python executable mismatch. Expected '$EXPECTED_PYENV_PYTHON' but got '$runtime_executable'."
    fi
    if [[ "$runtime_base_prefix" != "$expected_pyenv_prefix" ]]; then
      die "Python base prefix mismatch. Expected '$expected_pyenv_prefix' but got '$runtime_base_prefix'."
    fi
  else
    if [[ "$runtime_executable" != "$EXPECTED_VENV_PYTHON" ]]; then
      die "Venv executable mismatch. Expected '$EXPECTED_VENV_PYTHON' but got '$runtime_executable'."
    fi
    if [[ "$runtime_prefix" != "$expected_venv_prefix" ]]; then
      die "Venv prefix mismatch. Expected '$expected_venv_prefix' but got '$runtime_prefix'."
    fi
    if [[ "$runtime_base_prefix" != "$expected_pyenv_prefix" ]]; then
      die "Venv base interpreter mismatch. Expected '$expected_pyenv_prefix' but got '$runtime_base_prefix'."
    fi
  fi

  log_info "Python provenance check passed: $runtime_executable"
}

has_pyenv_shell_markers() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return 1

  grep -Eq 'pyenv init' "$rc_file" || return 1
  grep -Eq 'PYENV_ROOT|\.pyenv/bin' "$rc_file" || return 1
}

check_pyenv_shell_init() {
  local bashrc="${TARGET_HOME}/.bashrc"
  local zshrc="${TARGET_HOME}/.zshrc"

  if has_pyenv_shell_markers "$bashrc" || has_pyenv_shell_markers "$zshrc"; then
    log_info "Detected pyenv shell initialization for interactive shells."
    return
  fi

  log_warn "No pyenv shell initialization detected in '$bashrc' or '$zshrc'."
  log_warn "To use pyenv Python interactively as ${TARGET_USER}, add these lines:"
  log_warn "  export PYENV_ROOT=\"\$HOME/.pyenv\""
  log_warn "  export PATH=\"\$PYENV_ROOT/bin:\$PATH\""
  log_warn "  eval \"\$(pyenv init - bash)\"   # bash"
  log_warn "  eval \"\$(pyenv init - zsh)\"    # zsh"
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
  require_cmd grep
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
  assert_python_provenance

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
  assert_python_provenance

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

  log_info "Runtime commands were executed with pyenv-managed Python."
  check_pyenv_shell_init

  log_info "Done."
}

main "$@"
