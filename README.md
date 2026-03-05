# Jetson Orin Nano Utils

Utility scripts for setting up a Nvidia Jetson Orin Nano development environment.

## Scripts

### `install-pytorch.sh`
Installs a Jetson-compatible PyTorch stack with CUDA dependencies.

What it does:
- Requires `sudo` (must be run from a non-root user via `sudo`)
- Uses system `python3` and installs required Python packages globally
- Installs cuSPARSELt (`libcusparselt0`, `libcusparselt-dev`) required by the Jetson PyTorch packages
- Installs `onnxruntime-gpu==1.23.0`, `torch==2.10.0`, and `torchvision==0.25.0`
- Sources those three packages from the Jetson AI Lab index: `https://pypi.jetson-ai-lab.io/jp6/cu126`
- Installs `numpy<2.0`
- Verifies CUDA availability from Python

Usage:
```bash
sudo bash install-pytorch.sh
```

Options:
```bash
sudo bash install-pytorch.sh --help
```

Notes:
- System `python3` must be version `3.10` (required by `cp310` wheels)
- No `pyenv` or virtual environment is used
- `--clean-cache` is no longer supported

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

### `set-terminal-font.sh`
Sets GNOME Terminal font for the default profile.

What it does:
- Must be run as a regular user (not `sudo`)
- Validates required commands (`gsettings`, `dconf`)
- Resolves the default GNOME Terminal profile UUID (or falls back to the first profile)
- Sets terminal font to `JetBrains Mono 14`
- Verifies the font settings after applying
- Warns if Snap `gnome-terminal` is installed (settings may not apply as expected)

Usage:
```bash
bash set-terminal-font.sh
bash set-terminal-font.sh --help
```

### `csi-camera.py`
Simple OpenCV CSI camera test script for Jetson.

What it does:
- Builds a GStreamer pipeline for CSI camera capture
- Displays live camera frames
- Exits when the window closes, `Esc` is pressed, or `q` is pressed

Usage:
```bash
python3 csi-camera.py
```

## Requirements

- NVIDIA Jetson Orin Nano (JetPack 6 / Ubuntu 22.04 environment expected)
- Internet access for package/wheel downloads
- `sudo` privileges for system package installation
