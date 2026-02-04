#!/usr/bin/env bash
set -euo pipefail

# Build a fresh scGUI .app bundle you can double-click to open.
#
# This script:
# - clears scGUI caches
# - builds (or reuses) an embedded Python runtime (Scanpy + deps)
# - builds the SwiftUI app and packages dist/scGUI.app
#
# Usage:
#   ./rebuild_app.sh
#   ./rebuild_app.sh --open
#   ./rebuild_app.sh --no-dmg
#   ./rebuild_app.sh --reuse-runtime
#
# Notes:
# - For offline-friendly builds, this repo prefers SCANWR_PY_MODE=venv (copy from ./venv).
# - Outputs:
#   mac/ScanwrMac/dist/scGUI.app
#   mac/ScanwrMac/dist/scGUI-<version>.dmg

OPEN_APP="0"
CREATE_DMG="1"
REUSE_RUNTIME="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_APP="1"; shift ;;
    --no-dmg) CREATE_DMG="0"; shift ;;
    --reuse-runtime) REUSE_RUNTIME="1"; shift ;;
    -h|--help)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$REPO_ROOT/mac/ScanwrMac"
DIST="$MAC_ROOT/dist"
RUNTIME_DIR="$DIST/python-runtime/python"
APP_PATH="$DIST/scGUI.app"

echo "==> Clearing app cache…"
rm -rf "$HOME/Library/Caches/scGUI" 2>/dev/null || true
rm -rf "/tmp/scgui-cache" 2>/dev/null || true

if [[ "$REUSE_RUNTIME" == "1" && -x "$RUNTIME_DIR/bin/python3" ]]; then
  echo "==> Reusing existing embedded Python runtime…"
else
  echo "==> (Re)building embedded Python runtime…"
  export SCANWR_PY_MODE="${SCANWR_PY_MODE:-venv}"
  "$MAC_ROOT/scripts/build_python_runtime.sh"
fi

if [[ ! -x "$RUNTIME_DIR/bin/python3" ]]; then
  echo "ERROR: embedded runtime not found/executable at: $RUNTIME_DIR/bin/python3" >&2
  exit 3
fi

echo "==> Packaging .app…"
export SCANWR_PY_RUNTIME_DIR="$RUNTIME_DIR"
"$MAC_ROOT/scripts/make_app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: expected .app at: $APP_PATH" >&2
  exit 4
fi

echo "==> OK: $APP_PATH"

if [[ "$CREATE_DMG" == "1" ]]; then
  echo "==> Creating .dmg…"
  "$MAC_ROOT/scripts/make_dmg.sh"
  DMG_PATH="$(ls -t "$DIST"/scGUI-*.dmg 2>/dev/null | head -n 1 || true)"
  if [[ -n "$DMG_PATH" ]]; then
    echo "==> OK: $DMG_PATH"
  else
    echo "WARN: DMG creation finished, but no scGUI-*.dmg found in: $DIST" >&2
  fi
fi

if [[ "$OPEN_APP" == "1" ]]; then
  echo "==> Opening…"
  open "$APP_PATH"
fi
