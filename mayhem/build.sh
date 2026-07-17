#!/usr/bin/env bash
#
# georinex — Python/atheris commit-image build. Air-gapped + idempotent (SPEC §6.2 item 9 / §6.5):
# the FIRST (online) run bakes a pip wheelhouse (atheris + georinex + its full dep closure: numpy,
# xarray, netcdf4, hatanaka, ncompress, python-dateutil, …); every later run — including the offline
# PATCH-tier re-run (`docker run --network none … bash mayhem/build.sh`) — installs from that
# wheelhouse with `pip --no-index`, so it never reaches PyPI.
#
# What it builds:
#   1. atheris + georinex's runtime deps installed from the baked wheelhouse; georinex itself is
#      imported from the source tree ($SRC/src, via a .pth), so a patch reaches both launchers.
#   2. /mayhem/parse-load    — ELF libFuzzer launcher for mayhem/fuzz_load.py (the Mayhem target).
#   3. /mayhem/georinex-test — ELF launcher for the functional KAT (run by mayhem/test.sh).
set -euo pipefail

SRC="${SRC:-/mayhem}"
cd "$SRC"

# An empty SOURCE_DATE_EPOCH (passed through as an ARG) breaks clang — drop it if blank.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}"

# Debug-info contract (§6.2 item 10): the native ELF launchers must carry DWARF < 4 so Mayhem's
# triage can read them. clang's plain `-g` emits DWARF-5 — pin DWARF-3 explicitly.
DEBUG_FLAGS="${DEBUG_FLAGS:--gdwarf-3}"

# georinex is PURE Python: the fuzzed code runs under atheris coverage instrumentation, not native
# $SANITIZER_FLAGS (which instruments C/C++). Referenced here for the build contract — there are no
# native project objects to sanitize.
: "${SANITIZER_FLAGS:=}"

# ---- air-gapped Python deps: a pip wheelhouse under /opt/toolchains (§6.5) -----------------------
WHEELHOUSE="${PIP_WHEELHOUSE:-/opt/toolchains/pip/wheelhouse}"
ATHERIS_VERSION="${ATHERIS_VERSION:-3.1.0}"
mkdir -p "$WHEELHOUSE"

# Populate the wheelhouse exactly ONCE (first, online build). The offline re-run finds it already
# populated and skips straight to the --no-index install below.
if ! ls "$WHEELHOUSE"/atheris-*.whl >/dev/null 2>&1; then
  echo "build.sh: populating wheelhouse at $WHEELHOUSE (online, first build)"
  pip wheel --wheel-dir "$WHEELHOUSE" "atheris==${ATHERIS_VERSION}"
  # georinex + its full runtime dep closure (numpy, xarray, netcdf4, hatanaka, ncompress, …),
  # built/downloaded from the local source tree.
  pip wheel --wheel-dir "$WHEELHOUSE" "$SRC"
fi

# Install from the wheelhouse ONLY — never reach PyPI. Install georinex BY NAME (not "$SRC") so pip
# picks the prebuilt wheel instead of rebuilding from source offline.
# The interpreter + packages live in a venv under /opt/toolchains (§6.2 item 8), NOT in the
# per-user ~/.local: the target runs under another identity with another $HOME (and /home/mayhem is
# 0700), where a user-site install is invisible. The launchers below exec the venv's python by
# absolute path, so nothing depends on $HOME or the environment.
VENV="${PY_VENV:-/opt/toolchains/python/venv}"
# --without-pip: the base python has no ensurepip; the system pip installs into the venv via --python.
[ -x "$VENV/bin/python3" ] || python3 -m venv --without-pip "$VENV"
pip --python "$VENV/bin/python3" install --no-index --find-links="$WHEELHOUSE" \
  "atheris==${ATHERIS_VERSION}" georinex

# Import georinex from the source tree, not from the wheel just installed. The wheel is built once, on
# the first online build, so the PATCH tier's offline re-run finds it "already satisfied" and a patch to
# src/georinex would never reach parse-load or georinex-test. Keep the wheel's dependency closure, drop
# the installed copy and point the venv at $SRC/src. georinex sets __version__ statically, so nothing
# reads the installed metadata.
pip --python "$VENV/bin/python3" uninstall -y georinex
SITE="$("$VENV/bin/python3" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
printf '%s\n' "$SRC/src" > "$SITE/georinex-src.pth"

"$VENV/bin/python3" -c 'import atheris, georinex; print("build.sh: deps OK (atheris + georinex importable)")'
SRC="$SRC" "$VENV/bin/python3" -c 'import os, sys, georinex; f = georinex.__file__
sys.exit(0 if f.startswith(os.environ["SRC"] + "/src/") else "georinex imported from " + f + ", not the source tree")'

# ---- ELF libFuzzer launchers --------------------------------------------------------------------
PYBIN="$VENV/bin/python3"

# Mayhem fuzz target: launcher -> python3 mayhem/fuzz_load.py, forwarding libFuzzer argv.
$CC $DEBUG_FLAGS \
    -DPYTHON="\"$PYBIN\"" \
    -DSCRIPT="\"$SRC/mayhem/fuzz_load.py\"" \
    -o "$SRC/parse-load" "$SRC/mayhem/pylauncher.c"

# Functional-oracle runner: launcher -> python3 mayhem/test_kat.py. A non-system ELF (so the
# anti-reward-hack sabotage check can neuter it and the oracle is provably behavioral).
$CC $DEBUG_FLAGS \
    -DPYTHON="\"$PYBIN\"" \
    -DSCRIPT="\"$SRC/mayhem/test_kat.py\"" \
    -o "$SRC/georinex-test" "$SRC/mayhem/pylauncher.c"

chmod +x "$SRC/parse-load" "$SRC/georinex-test"
echo "build.sh: done — /mayhem/parse-load, /mayhem/georinex-test"
