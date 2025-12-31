#!/usr/bin/env bash
set -euo pipefail

PIN_URL="https://software.intel.com/sites/landingpage/pintool/downloads/pin-external-3.31-98869-gfa6f126a8-gcc-linux.tar.gz"

# Where to store and extract PIN
DEST_BASE="${1:-$HOME/tools}"
PIN_DIR="${DEST_BASE}/pin"
TARBALL="${DEST_BASE}/pin-external-3.31-gcc-linux.tar.gz"
ENV_FILE="${DEST_BASE}/env_pin.sh"

mkdir -p "$DEST_BASE" "$PIN_DIR"

echo "[INFO] Downloading PIN tarball..."
if command -v curl >/dev/null 2>&1; then
  curl -L --fail --retry 3 --retry-delay 2 -o "$TARBALL" "$PIN_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TARBALL" "$PIN_URL"
else
  echo "[ERROR] Need curl or wget to download PIN." >&2
  exit 1
fi

echo "[INFO] Extracting to: $PIN_DIR"
tar -xzf "$TARBALL" -C "$PIN_DIR"

# Find the extracted directory that contains the 'pin' executable
PIN_ROOT_CANDIDATE="$(find "$PIN_DIR" -maxdepth 2 -type f -name pin -perm -111 -print -quit | xargs -r dirname || true)"

if [[ -z "$PIN_ROOT_CANDIDATE" ]]; then
  echo "[ERROR] Could not find 'pin' executable after extraction in: $PIN_DIR" >&2
  echo "[HINT] Inspect extracted contents: ls -lah \"$PIN_DIR\"" >&2
  exit 1
fi

export PIN_ROOT="$PIN_ROOT_CANDIDATE"

# Sanity check
if [[ ! -x "$PIN_ROOT/pin" ]]; then
  echo "[ERROR] PIN_ROOT doesn't contain an executable pin binary: $PIN_ROOT/pin" >&2
  exit 1
fi

echo "[INFO] PIN_ROOT set to: $PIN_ROOT"
echo "[INFO] PIN version check (first line):"
"$PIN_ROOT/pin" -h 2>/dev/null | head -n 1 || true

# Write an env file for later reuse
cat > "$ENV_FILE" <<EOF
# Source this file to reuse Intel PIN
export PIN_ROOT="$PIN_ROOT"
export PATH="\$PIN_ROOT:\$PATH"
EOF

chmod +x "$ENV_FILE"

echo "[INFO] Wrote: $ENV_FILE"
echo "[INFO] To reuse later: source \"$ENV_FILE\""

