#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[INFO] ROOT_DIR: $ROOT_DIR"

# -------------------------
# Logging
# -------------------------
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/run_artifact.$(date +%Y%m%d_%H%M%S).log"

# -------------------------
# Helpers
# -------------------------
die()  { echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2; exit 1; }
info() { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn() { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }

on_err() {
  local ec=$?
  warn "Command failed (exit=$ec) at line ${BASH_LINENO[0]}:"
  warn "  ${BASH_COMMAND}"
  warn "See log: $LOG_FILE"
  exit "$ec"
}
trap on_err ERR

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --check-only           Only validate prerequisites; do not build/run.
  --install-system       Attempt to install missing system deps (Ubuntu/Debian via apt-get).
  --skip-llvm            Skip LLVM build step.
  --skip-benchmarks      Skip benchmark fetch/build steps.
  --skip-pin-tools       Skip PIN tool validation/rebuild checks.
  --install-python       Install minimal python deps (pandas,numpy) with pip.
  -h, --help             Show help.

Notes:
- Runs sub-steps from repo root to avoid CWD-relative failures.
- Logs: $LOG_FILE
EOF
}

CHECK_ONLY=0
INSTALL_SYSTEM=0
SKIP_LLVM=0
SKIP_BENCH=0
SKIP_PIN=0
INSTALL_PY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    --install-system) INSTALL_SYSTEM=1; shift ;;
    --skip-llvm) SKIP_LLVM=1; shift ;;
    --skip-benchmarks) SKIP_BENCH=1; shift ;;
    --skip-pin-tools) SKIP_PIN=1; shift ;;
    --install-python) INSTALL_PY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

info "Logging to $LOG_FILE"
info "ROOT_DIR = $ROOT_DIR"

# -------------------------
# 0) FIRST STEP: Make scripts executable
# -------------------------
info "Making all .sh and .py files executable under repo root ..."
find "$ROOT_DIR" -type f \( -name "*.sh" -o -name "*.py" \) -print0 \
  | xargs -0 chmod +x
info "chmod step complete."

# -------------------------
# System installer (Ubuntu/Debian only)
# -------------------------
apt_install_if_requested() {
  local pkgs=("$@")
  if [[ "$INSTALL_SYSTEM" -ne 1 ]]; then
    return 0
  fi

  have apt-get || die "--install-system was requested but apt-get is not available on this machine."

  # We need sudo/root
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    have sudo || die "--install-system requires sudo (or run as root). sudo not found."
    info "Installing missing system deps via apt-get (sudo) ..."
    sudo apt-get update |& tee -a "$LOG_FILE"
    sudo apt-get install -y "${pkgs[@]}" |& tee -a "$LOG_FILE"
  else
    info "Installing missing system deps via apt-get (root) ..."
    apt-get update |& tee -a "$LOG_FILE"
    apt-get install -y "${pkgs[@]}" |& tee -a "$LOG_FILE"
  fi
}

# -------------------------
# 1) Pre-flight checks (with optional auto-install)
# -------------------------
missing_pkgs=()

# These commands are *required* for LLVM build workflow
for c in git cmake ninja python3; do
  if ! have "$c"; then
    warn "Missing command: $c"
    case "$c" in
      git)    missing_pkgs+=("git") ;;
      cmake)  missing_pkgs+=("cmake") ;;
      ninja)  missing_pkgs+=("ninja-build") ;;
      python3) missing_pkgs+=("python3") ;;
    esac
  fi
done

# pip requirement
if ! python3 -m pip --version >/dev/null 2>&1; then
  warn "Missing pip for python3 (python3 -m pip)."
  missing_pkgs+=("python3-pip")
fi

# Recommended tools
if ! have gdb; then
  warn "Missing: gdb (recommended)."
  missing_pkgs+=("gdb")
fi

# perf tool is distro/kernel dependent; install best-effort common packages
if ! have perf; then
  warn "Missing: perf (linux-tools). Some profiling steps will fail."
  # ubuntu generally needs these; linux-tools-$(uname -r) often needed too
  missing_pkgs+=("linux-tools-common")
  missing_pkgs+=("linux-tools-$(uname -r)")
fi

# Dedup package list
dedup_pkgs=()
for p in "${missing_pkgs[@]}"; do
  skip=0
  for q in "${dedup_pkgs[@]}"; do
    [[ "$p" == "$q" ]] && skip=1 && break
  done
  [[ "$skip" -eq 0 ]] && dedup_pkgs+=("$p")
done

if [[ "${#dedup_pkgs[@]}" -gt 0 ]]; then
  if [[ "$INSTALL_SYSTEM" -eq 1 ]]; then
    info "Attempting to install missing system deps: ${dedup_pkgs[*]}"
    apt_install_if_requested "${dedup_pkgs[@]}"
  fi
fi

# Re-check required commands after optional install
MISSING=0
for c in git cmake ninja python3; do
  if ! have "$c"; then
    warn "Still missing command: $c"
    MISSING=1
  fi
done
if ! python3 -m pip --version >/dev/null 2>&1; then
  warn "Still missing pip for python3."
  MISSING=1
fi

if [[ "$MISSING" -eq 1 ]]; then
  cat <<EOF | tee -a "$LOG_FILE"
[HINT] On Ubuntu/Debian you can install common prerequisites with:
  sudo apt-get update
  sudo apt-get install -y build-essential git cmake ninja-build python3 python3-pip python3-venv gdb linux-tools-common linux-tools-\$(uname -r)
Or re-run this script with:
  $0 --install-system
EOF
  die "Prerequisites missing. Install dependencies and re-run."
fi

info "Core system deps OK."

# -------------------------
# 2) Python deps
# -------------------------
if [[ "$INSTALL_PY" -eq 1 ]]; then
  info "Installing minimal Python deps (user site): pandas, numpy"
  python3 -m pip install --user -U pip |& tee -a "$LOG_FILE"
  python3 -m pip install --user -U pandas numpy |& tee -a "$LOG_FILE"
fi

python3 - <<'PY' >/dev/null 2>&1
import pandas, numpy
PY
if [[ $? -ne 0 ]]; then
  die "Python deps missing (pandas/numpy). Run: python3 -m pip install --user pandas numpy  (or re-run with --install-python)"
fi
info "Python deps OK (pandas/numpy import succeeded)."

# (Continue with the rest of your script here: PIN_ROOT checks, LLVM build, etc.)
info "Pre-flight stage finished successfully."


sudo apt-get update
sudo apt-get install -y g++ libstdc++-14-dev libc6-dev
sudo apt-get install -y \
  build-essential git \
  cmake ninja-build \
  python3 python3-pip python3-venv \
  gdb \
  linux-tools-common linux-tools-$(uname -r) \
  binutils pkg-config \
  curl wget ca-certificates \
  g++ libc6-dev libstdc++-14-dev \
  unzip rsync time bc jq \
  clang lld make

python3 -m pip install --user -U pip
python3 -m pip install --user -U pandas numpy matplotlib scikit-learn

echo "[OK] System + Python deps installed."
echo "[OK] perf: $(perf --version 2>/dev/null || echo 'not found')"
echo "[OK] python: $(python3 --version)"

echo " START RIFS"
./run_all_steps.sh
