# Jetson Orin Nano Setup

Utility scripts for setting up a Jetson Orin Nano development environment.

## Scripts

### `install-pytorch.sh`
Installs a Jetson-compatible PyTorch stack with CUDA dependencies.

What it does:
- Requires `sudo` (must be run from a non-root user via `sudo`)
- Installs base build and Python dependencies needed for `pyenv` + PyTorch wheels
- Installs cuSPARSELt (`libcusparselt0`, `libcusparselt-dev`) for Torch 2.5.0 dependency support
- Downloads cached wheel files for `torch` and `torchvision`
- Installs `onnxruntime-gpu 1.23.0` (Python 3.10, ARM64 wheel)
- Installs `torch`, `torchvision`, and `numpy<2.0`
- Verifies CUDA availability from Python

Usage:
```bash
sudo bash install-pytorch.sh
```

Options:
```bash
sudo bash install-pytorch.sh --venv
sudo bash install-pytorch.sh --clean-cache
sudo bash install-pytorch.sh --venv --clean-cache
sudo bash install-pytorch.sh --help
```

Notes:
- `--venv` creates/uses `<sudo-user-home>/Workspace/.venv`
- Wheel cache directory: `<sudo-user-home>/.cache/pytorch_wheels`
- Script fails fast if runtime Python is not the expected pyenv interpreter (or a venv based on it)
- Script checks for pyenv shell init in `<sudo-user-home>/.bashrc` and prints manual setup commands if missing

### `install-vscode.sh`
Downloads and installs the latest stable ARM64 `.deb` build of Visual Studio Code.

What it does:
- Requires root (`sudo`)
- Installs dependencies (`wget`, `apt-transport-https`)
- Downloads latest VS Code ARM64 package
- Installs with `dpkg` and fixes dependencies if needed
- Verifies install by checking `code --version`

Usage:
```bash
sudo bash install-vscode.sh
sudo bash install-vscode.sh --help
```

### `revert-snap.sh`
Downloads and reinstalls a specific `snapd` revision, then places it on hold.

Usage:
```bash
sudo bash revert-snap.sh
```

Specify a revision:
```bash
sudo bash revert-snap.sh 24724
sudo bash revert-snap.sh --revision 24724
sudo bash revert-snap.sh --help
```

What it does:
- `snap download snapd --revision=<REVISION>`
- `snap ack ...`
- `snap install ...`
- `snap refresh --hold snapd`

### `camera.py`
Simple OpenCV CSI camera test script for Jetson.

What it does:
- Builds a GStreamer pipeline for CSI camera capture
- Displays live camera frames
- Exits when the window closes, `Esc` is pressed, or `q` is pressed

Usage:
```bash
python3 camera.py
```

## Requirements

- NVIDIA Jetson Orin Nano (JetPack 6 / Ubuntu 22.04 environment expected)
- Internet access for package/wheel downloads
- `sudo` privileges for system package installation
