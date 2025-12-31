# RIFS-LLVM-Passes — Artifact / Reproducibility README

This repository contains LLVM passes, PIN-based profiling tooling, and benchmark build/run scripts.

## What you must run manually:
chmod +x run_artifact.sh
./run_artifact.sh --install-system --install-python
## What is required to download:

1) **Benchmarks**  
   - Download / place the benchmark sources under `benchmarks/` as expected by the scripts.
   - Some benchmark suites require separate registration / licensing (e.g., PARSEC). Follow their official instructions.

2) **Intel PIN**  
   - Download Intel PIN and set:
     ```bash
     export PIN_ROOT=/abs/path/to/pin
     ```
   - A working `PIN_ROOT` must contain `pin` (e.g., `$PIN_ROOT/pin`).

3) **Machine environment**  
   - You need a Linux machine with build tools, Python tooling, and `perf` available.

---

## Supported / tested platform
This artifact is intended for **Linux** (Ubuntu-style packages assumed in examples).

---

## Dependencies (install first)
If you are on Ubuntu/Debian, the following are required.

### System packages
```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git wget curl ca-certificates \
  cmake ninja-build \
  python3 python3-pip python3-venv \
  gdb \
  linux-tools-common
