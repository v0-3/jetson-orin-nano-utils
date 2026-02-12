#!/usr/bin/env bash
set -Eeuo pipefail

USE_VENV=false
CLEAN_CACHE=false

for arg in "$@"; do
  case "$arg" in
    --venv)
      USE_VENV=true
      ;;
    --clean-cache)
      CLEAN_CACHE=true
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: install-pytorch.sh [--venv] [--clean-cache]

Options:
  --venv         Create and use ~/Workspace/.venv before installing
  --clean-cache  Remove cached .whl files before downloading
  -h, --help     Show this help message
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

readonly WHEEL_CACHE="$HOME/.cache/pytorch_wheels"
readonly WORKSPACE_DIR="$HOME/Workspace"

readonly TORCH_WHL="torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
readonly TORCHVISION_WHL="torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"
readonly ONNXRUNTIME_GPU_WHL_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/onnxruntime_gpu-1.23.0-cp310-cp310-linux_aarch64.whl"

readonly TORCH_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torch-2.5.0a0+872d972e41.nv24.08-cp310-cp310-linux_aarch64.whl"
readonly TORCHVISION_URL="https://github.com/ultralytics/assets/releases/download/v0.0.0/torchvision-0.20.0a0+afc54f7-cp310-cp310-linux_aarch64.whl"

announce() {
  echo "$1"
}

download_if_missing() {
  local filename="$1"
  local url="$2"

  if [[ ! -f "$filename" ]]; then
    wget "$url" -O "$filename"
  fi
}

create_venv_if_requested() {
  if ! $USE_VENV; then
    announce "Using system Python (no virtual environment)."
    return
  fi

  announce "Creating virtual environment..."
  mkdir -p "$WORKSPACE_DIR"
  cd "$WORKSPACE_DIR"
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
}

verify_install() {
  python3 - <<'PYCODE'
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

announce "Installing PyTorch for Jetson Orin Nano"
announce "Updating system packages..."

sudo apt-get update
sudo apt-get install -y python3-pip python3-venv libopenblas-dev wget

announce "Installing cuSPARSELt (required by torch 2.5.0)..."
readonly CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
wget "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/${CUDA_KEYRING_DEB}" -O "$CUDA_KEYRING_DEB"
sudo dpkg -i "$CUDA_KEYRING_DEB"
sudo apt-get update
sudo apt-get -y install libcusparselt0 libcusparselt-dev

python3 -m pip uninstall -y torch torchvision || true

mkdir -p "$WHEEL_CACHE"
cd "$WHEEL_CACHE"

if $CLEAN_CACHE; then
  announce "Cleaning wheel cache..."
  rm -f "$WHEEL_CACHE"/*.whl
fi

announce "Downloading missing wheels (if any)..."
download_if_missing "$TORCH_WHL" "$TORCH_URL"
download_if_missing "$TORCHVISION_WHL" "$TORCHVISION_URL"

create_venv_if_requested

announce "Upgrading pip..."
python3 -m pip install --upgrade pip

announce "Installing ONNX Runtime GPU 1.23.0..."
python3 -m pip install "$ONNXRUNTIME_GPU_WHL_URL"

announce "Installing PyTorch and TorchVision..."
python3 -m pip install --force-reinstall \
  "$WHEEL_CACHE/$TORCH_WHL" \
  "$WHEEL_CACHE/$TORCHVISION_WHL" \
  "numpy<2.0"

announce "Verifying installation..."
verify_install

announce "Done."
