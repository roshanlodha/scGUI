#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="scGUI"
BUNDLE_ID="com.roshanlodha.scanwr"
VERSION="0.3.2"

PY_RUNTIME_DIR="${SCANWR_PY_RUNTIME_DIR:-$DIST/python-runtime/python}"

echo "Clearing scGUI cache…"
rm -rf "$HOME/Library/Caches/scGUI" 2>/dev/null || true
rm -rf "/tmp/scgui-cache" 2>/dev/null || true

if [[ -z "$PY_RUNTIME_DIR" ]]; then
  echo "ERROR: Set SCANWR_PY_RUNTIME_DIR to a relocatable Python runtime directory to bundle." >&2
  echo "Expected layout: \$SCANWR_PY_RUNTIME_DIR/bin/python3 (and its adjacent libs)." >&2
  echo "Example: export SCANWR_PY_RUNTIME_DIR=/path/to/python-runtime" >&2
  exit 2
fi

if [[ ! -x "$PY_RUNTIME_DIR/bin/python3" ]]; then
  echo "ERROR: Not executable: $PY_RUNTIME_DIR/bin/python3" >&2
  exit 2
fi

mkdir -p "$DIST"

echo "Building release binary via SwiftPM…"
cd "$ROOT"
export TMPDIR="${TMPDIR:-/tmp}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/scanwr-clang-cache}"
rm -rf "$TMPDIR/scanwr-swift-scratch" "$TMPDIR/scanwr-swift-cache" || true
swift build -c release \
  --disable-sandbox \
  --scratch-path "$TMPDIR/scanwr-swift-scratch" \
  --cache-path "$TMPDIR/scanwr-swift-cache" \
  --manifest-cache local

# For Apple Silicon only (arm64), SwiftPM emits into this bin dir when using the scratch path above.
BIN="$TMPDIR/scanwr-swift-scratch/arm64-apple-macosx/release/ScanwrMacApp"

if [[ ! -f "$BIN" ]]; then
  echo "ERROR: Build output not found: $BIN" >&2
  exit 3
fi

APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "Creating app bundle at: $APP"
cp "$BIN" "$MACOS/$APP_NAME"

# Put the python server script in Resources (Swift looks in Bundle.main first).
cp "$ROOT/Sources/ScanwrMacApp/Resources/scanwr_rpc_server.py" "$RES/scanwr_rpc_server.py"

echo "Bundling Python runtime…"
rm -rf "$RES/python"
mkdir -p "$RES"
ditto --noqtn "$PY_RUNTIME_DIR" "$RES/python"

# Bundle CellTypist models into the app so end users can annotate offline.
# Priority:
# 1) SCANWR_CELLTYPIST_MODELS_DIR: directory that contains .pkl files (or has data/models/)
# 2) Otherwise, download models using the bundled Python runtime (requires internet).
#
# If you want to skip bundling, set SCANWR_SKIP_CELLTYPIST_MODELS=1.
# If you want to allow packaging to proceed without models, set SCANWR_REQUIRE_CELLTYPIST_MODELS=0.
SKIP_CELLTYPIST_MODELS="${SCANWR_SKIP_CELLTYPIST_MODELS:-0}"
REQUIRE_CELLTYPIST_MODELS="${SCANWR_REQUIRE_CELLTYPIST_MODELS:-1}"
CELLTYPIST_MODELS_DIR="${SCANWR_CELLTYPIST_MODELS_DIR:-}"

_bundle_celltypist_from_dir() {
  local src_dir="$1"
  if [[ ! -d "$src_dir" ]]; then
    return 1
  fi
  if ! ls -1 "$src_dir"/*.pkl >/dev/null 2>&1; then
    return 1
  fi
  echo "Bundling CellTypist models from: $src_dir"
  rm -rf "$RES/celltypist_models"
  mkdir -p "$RES/celltypist_models"
  ditto --noqtn "$src_dir" "$RES/celltypist_models"
  # Ensure there is at least one .pkl in the app bundle.
  ls -1 "$RES/celltypist_models"/*.pkl >/dev/null 2>&1
}

if [[ "$SKIP_CELLTYPIST_MODELS" != "1" ]]; then
  SRC=""
  if [[ -n "$CELLTYPIST_MODELS_DIR" ]]; then
    if [[ -d "$CELLTYPIST_MODELS_DIR/data/models" ]] && ls -1 "$CELLTYPIST_MODELS_DIR/data/models"/*.pkl >/dev/null 2>&1; then
      SRC="$CELLTYPIST_MODELS_DIR/data/models"
    else
      SRC="$CELLTYPIST_MODELS_DIR"
    fi

    if ! _bundle_celltypist_from_dir "$SRC"; then
      echo "WARN: SCANWR_CELLTYPIST_MODELS_DIR provided but no .pkl models found: $CELLTYPIST_MODELS_DIR" >&2
      SRC=""
    fi
  fi

  if [[ -z "$SRC" ]]; then
    EMBED_PY="$RES/python/bin/python3"
    if [[ -x "$EMBED_PY" ]]; then
      echo "Downloading CellTypist models using bundled Python (force_update=True)…"
      TMP_CT="$(mktemp -d "${TMPDIR:-/tmp}/scanwr-celltypist.XXXXXX")"
      # Ensure CellTypist writes into a staging dir we control.
      export CELLTYPIST_FOLDER="$TMP_CT/celltypist"
      export MPLBACKEND="Agg"
      export MPLCONFIGDIR="$TMP_CT/mpl"
      export XDG_CACHE_HOME="$TMP_CT/xdg"
      export NUMBA_CACHE_DIR="$TMP_CT/numba"
      mkdir -p "$CELLTYPIST_FOLDER" "$MPLCONFIGDIR" "$XDG_CACHE_HOME" "$NUMBA_CACHE_DIR" >/dev/null 2>&1 || true

      set +e
      DL_OUT="$("$EMBED_PY" - <<'PY'
from celltypist import models
models.download_models(force_update=True)
print(models.models_path)
PY
)"
      DL_STATUS=$?
      set -e

      if [[ "$DL_STATUS" -eq 0 ]]; then
        MODELS_PATH="$(printf '%s\n' "$DL_OUT" | tail -n 1)"
        if _bundle_celltypist_from_dir "$MODELS_PATH"; then
          echo "OK: Bundled CellTypist models."
        else
          echo "WARN: CellTypist download succeeded but no .pkl found at: $MODELS_PATH" >&2
          if [[ "$REQUIRE_CELLTYPIST_MODELS" == "1" ]]; then
            echo "ERROR: Required CellTypist models missing (set SCANWR_REQUIRE_CELLTYPIST_MODELS=0 to continue)." >&2
            exit 4
          fi
        fi
      else
        echo "WARN: Failed to download CellTypist models using bundled Python." >&2
        echo "$DL_OUT" >&2
        if [[ "$REQUIRE_CELLTYPIST_MODELS" == "1" ]]; then
          echo "ERROR: Required CellTypist models missing." >&2
          echo "Set SCANWR_CELLTYPIST_MODELS_DIR to a folder containing the .pkl files, or set SCANWR_REQUIRE_CELLTYPIST_MODELS=0 to continue." >&2
          exit 4
        fi
      fi
    else
      echo "WARN: Bundled Python not executable; cannot download CellTypist models during packaging." >&2
      if [[ "$REQUIRE_CELLTYPIST_MODELS" == "1" ]]; then
        echo "ERROR: Required CellTypist models missing (set SCANWR_CELLTYPIST_MODELS_DIR, or set SCANWR_REQUIRE_CELLTYPIST_MODELS=0)." >&2
        exit 4
      fi
    fi
  fi
fi

# Minimal Info.plist
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "OK: $APP"
