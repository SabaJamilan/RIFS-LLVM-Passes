#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if need gdb; then
  echo "[INFO] gdb is already installed: $(command -v gdb)"
  gdb --version | head -n 1 || true
  exit 0
fi

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if need sudo; then
    SUDO="sudo"
  else
    echo "[ERROR] gdb not installed and sudo not available. Run as root." >&2
    exit 1
  fi
fi

if need apt-get; then
  echo "[INFO] Installing gdb via apt-get..."
  $SUDO apt-get update
  $SUDO apt-get install -y gdb
elif need dnf; then
  echo "[INFO] Installing gdb via dnf..."
  $SUDO dnf install -y gdb
elif need yum; then
  echo "[INFO] Installing gdb via yum..."
  $SUDO yum install -y gdb
elif need pacman; then
  echo "[INFO] Installing gdb via pacman..."
  $SUDO pacman -Sy --noconfirm gdb
elif need zypper; then
  echo "[INFO] Installing gdb via zypper..."
  $SUDO zypper --non-interactive install gdb
else
  echo "[ERROR] Unsupported package manager. Install gdb manually." >&2
  exit 1
fi

echo "[INFO] Done. gdb is now: $(command -v gdb)"
gdb --version | head -n 1 || true
