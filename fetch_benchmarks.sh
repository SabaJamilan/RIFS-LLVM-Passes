#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "ROOT_DIR: " $ROOT_DIR
BENCH_ROOT="${BENCH_ROOT:-$ROOT_DIR/benchmarks}"
BENCH_ROOT="$(mkdir -p "$BENCH_ROOT" && cd "$BENCH_ROOT" && pwd)"

PARSEC_REPO="${PARSEC_REPO:-https://github.com/connorimes/parsec-3.0.git}"
PARSEC_REF="${PARSEC_REF:-master}"

RODINIA_REPO="${RODINIA_REPO:-https://github.com/HPC-FAIR/rodinia_3.1.git}"
RODINIA_REF="${RODINIA_REF:-main}"

### SPEC CPU 2017 is a licensed product from the Standard Performance Evaluation Corporation (SPEC) and  it has an ISO file (e.g., cpu2017-1.1.9.iso) containing benchmarks, source code, data, and tools for performance evaluation. You need to obtain " the ISO from SPEC's website "https://www.spec.org/cpu2017/releases/" "

SPEC_ISO="${SPEC_ISO:-}"                  # e.g., /abs/path/cpu2017-1.1.9.iso
SPEC_INSTALL_DIR="${SPEC_INSTALL_DIR:-$BENCH_ROOT/spec2017}"

CORTEX_TARBALL="${CORTEX_TARBALL:-}"      # e.g., /abs/path/cortexsuite.tar.gz
CORTEX_DIR="${CORTEX_DIR:-$BENCH_ROOT/cortexsuite}"

mkdir -p "$BENCH_ROOT"

clone_or_update() {
  local url="$1" dir="$2" ref="$3"

  if [[ -d "$dir/.git" ]]; then
    echo "[+] Updating $dir"
    git -C "$dir" fetch --all --tags
  else
    echo "[+] Cloning $url -> $dir"
    git clone "$url" "$dir"
  fi

  echo "[+] Checkout $ref"
  git -C "$dir" checkout "$ref"
}

echo "============================================================"
echo "Bench root: $BENCH_ROOT"
echo "============================================================"

echo
echo "         ----- PARSEC-3.0 -----"
clone_or_update "$PARSEC_REPO" "$BENCH_ROOT/parsec-3.0" "$PARSEC_REF"
echo "PARSEC location: $BENCH_ROOT/parsec-3.0"
echo "Repo: $PARSEC_REPO"
# PARSEC repo reference: https://github.com/connorimes/parsec-3.0 :contentReference[oaicite:0]{index=0}

echo
echo "         ----- Rodinia -----"
clone_or_update "$RODINIA_REPO" "$BENCH_ROOT/rodinia" "$RODINIA_REF"
echo "Rodinia location: $BENCH_ROOT/rodinia"
echo "Repo: $RODINIA_REPO"
# Rodinia fork reference: https://github.com/JuliaParallel/rodinia :contentReference[oaicite:1]{index=1}

echo
echo "         ----- SPEC CPU2017 (LICENSED; NOT auto-downloaded) -----"
if [[ -n "$SPEC_ISO" ]]; then
  echo "[+] SPEC_ISO provided: $SPEC_ISO"
  echo "[+] Installing SPEC into: $SPEC_INSTALL_DIR"
  mkdir -p "$SPEC_INSTALL_DIR"

  if command -v sudo >/dev/null 2>&1 && command -v mount >/dev/null 2>&1; then
    MNT="$BENCH_ROOT/.spec_mnt"
    mkdir -p "$MNT"
    echo "[+] Attempting to mount ISO (may prompt for sudo password)..."
    sudo mount -o loop "$SPEC_ISO" "$MNT"
    echo "[+] Running install.sh (interactive prompts may appear)..."
    bash "$MNT/install.sh" -d "$SPEC_INSTALL_DIR"
    echo "[+] Unmounting ISO..."
    sudo umount "$MNT"
  else
    echo "[!] Cannot auto-mount ISO (missing sudo/mount)."
    echo "    Please mount ISO manually and run install.sh as per SPEC docs."
  fi
else
  echo "[!] SPEC_ISO not provided."
  echo "    Action required (manual):"
  echo "    1) Obtain SPEC CPU2017 ISO via your SPEC license from "https://www.spec.org/cpu2017/releases/""
  echo "    2) Provide it to this script via: SPEC_ISO=/abs/path/to/cpu2017.iso"
  echo "    3) Or mount & install manually following SPEC's install guide."
fi

echo
echo "         ----- CortexSuite (GATED DOWNLOAD; NOT auto-downloaded) -----"
if [[ -n "$CORTEX_TARBALL" ]]; then
  echo "[+] Cortex tarball provided: $CORTEX_TARBALL"
  echo "[+] Extracting into: $CORTEX_DIR"
  mkdir -p "$CORTEX_DIR"
  tar -xf "$CORTEX_TARBALL" -C "$CORTEX_DIR" || {
    echo "[!] tar extraction failed. If it's a .zip, use: unzip file.zip -d $CORTEX_DIR"
    exit 1
  }
else
  echo "[!] CORTEX_TARBALL not provided."
  echo "    Action required (manual):"
  echo "    1) Download CortexSuite from the official site "https://michaeltaylor.org/cortexsuite/""
  echo "    2) Place the tarball somewhere on disk."
  echo "    3) Re-run with: CORTEX_TARBALL=/abs/path/to/cortexsuite.tar.gz"
fi

echo
echo "============================================================"
echo "[+] Done fetching benchmarks."
echo "============================================================"


