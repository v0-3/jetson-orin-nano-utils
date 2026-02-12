# Jetson Orin Nano Setup

Utility scripts for setting up a Jetson Orin Nano development environment.

## Scripts

### `install-pytorch.sh`
Installs a Jetson-compatible PyTorch stack with CUDA dependencies.

What it does:
- Installs base packages (`python3-pip`, `python3-venv`, `libopenblas-dev`, `wget`)
- Installs cuSPARSELt (`libcusparselt0`, `libcusparselt-dev`) for Torch 2.5.0 dependency support
- Downloads cached wheel files for `torch` and `torchvision`
- Installs `onnxruntime-gpu 1.23.0` (Python 3.10, ARM64 wheel)
- Installs `torch`, `torchvision`, and `numpy<2.0`
- Verifies CUDA availability from Python

Usage:
```bash
bash install-pytorch.sh
```

Options:
```bash
bash install-pytorch.sh --venv
bash install-pytorch.sh --clean-cache
bash install-pytorch.sh --venv --clean-cache
```

Notes:
- `--venv` creates/uses `~/Workspace/.venv`
- Wheel cache directory: `~/.cache/pytorch_wheels`

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
```

### `revert-snap.sh`
Downloads and reinstalls a specific `snapd` revision, then places it on hold.

Usage:
```bash
bash revert-snap.sh
```

Specify a revision:
```bash
bash revert-snap.sh 24724
```

What it does:
- `snap download snapd --revision=<REVISION>`
- `sudo snap ack ...`
- `sudo snap install ...`
- `sudo snap refresh --hold snapd`

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
