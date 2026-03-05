#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_ERROR=2

readonly JETSON_AI_LAB_INDEX_URL="https://pypi.jetson-ai-lab.io/jp6/cu126"
readonly TORCH_VERSION="2.10.0"
readonly TORCHVISION_VERSION="0.25.0"
readonly ONNXRUNTIME_GPU_VERSION="1.23.0"
readonly CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
readonly CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/${CUDA_KEYRING_DEB}"
readonly CUDSS_LIB_DIR="/usr/lib/aarch64-linux-gnu/libcudss/12"
readonly CUDSS_LDCONF_PATH="/etc/ld.so.conf.d/libcudss.conf"
readonly CUDSS_SYSTEM_LINK="/usr/lib/aarch64-linux-gnu/libcudss.so.0"

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
Usage: sudo bash ${SCRIPT_NAME}

Install Jetson-compatible PyTorch, TorchVision, and ONNX Runtime GPU packages
from the Jetson AI Lab package index using the system Python.

Options:
  -h, --help     Show this help message
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

run_python() {
  if [[ -d "$CUDSS_LIB_DIR" ]]; then
    LD_LIBRARY_PATH="${CUDSS_LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" "${PYTHON_CMD[@]}" "$@"
    return
  fi

  "${PYTHON_CMD[@]}" "$@"
}

run_pip() {
  run_python -m pip "$@"
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
  log_info "Installing cuSPARSELt and cuDSS dependencies for Jetson PyTorch packages..."
  wget "$CUDA_KEYRING_URL" -O "$CUDA_KEYRING_DEB_PATH"
  dpkg -i "$CUDA_KEYRING_DEB_PATH"
  apt-get update
  apt-get install -y \
    libcudss0-cuda-12 \
    libcusparselt0 \
    libcusparselt-dev
}

configure_dynamic_linker() {
  log_info "Registering cuDSS runtime library path with ldconfig..."
  [[ -f "${CUDSS_LIB_DIR}/libcudss.so.0" ]] || die "cuDSS runtime library not found in ${CUDSS_LIB_DIR}."

  printf '%s\n' "$CUDSS_LIB_DIR" > "$CUDSS_LDCONF_PATH"
  ln -sfn "${CUDSS_LIB_DIR}/libcudss.so.0" "$CUDSS_SYSTEM_LINK"
  ldconfig

  "${PYTHON_CMD[@]}" - <<'PYCODE'
import ctypes

ctypes.CDLL("libcudss.so.0")
PYCODE
}

install_python_packages() {
  local -a index_args=(--index-url "$JETSON_AI_LAB_INDEX_URL")

  log_info "Upgrading pip..."
  run_pip install --upgrade pip

  log_info "Removing existing Jetson ML packages..."
  run_pip uninstall -y onnxruntime-gpu torch torchvision || true

  log_info "Installing ONNX Runtime GPU ${ONNXRUNTIME_GPU_VERSION} from Jetson AI Lab..."
  run_pip install --force-reinstall \
    "${index_args[@]}" \
    "onnxruntime-gpu==${ONNXRUNTIME_GPU_VERSION}"

  log_info "Installing PyTorch ${TORCH_VERSION} and TorchVision ${TORCHVISION_VERSION} from Jetson AI Lab..."
  run_pip install --force-reinstall \
    "${index_args[@]}" \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}"
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

setup_environment() {
  require_root
  setup_traps
  require_cmds apt-get dpkg ldconfig ln mktemp python3 wget
  TMP_DIR="$(mktemp -d)"
  CUDA_KEYRING_DEB_PATH="${TMP_DIR}/${CUDA_KEYRING_DEB}"

  log_info "Installing PyTorch for Jetson Orin Nano"
  log_info "Installing from package index: ${JETSON_AI_LAB_INDEX_URL}"
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
  configure_dynamic_linker
  install_python_packages
  final_checks
}

main "$@"
