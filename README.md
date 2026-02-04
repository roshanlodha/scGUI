# scGUI (scanwr), formerly scAnWr

scGUI is a native macOS app (SwiftUI) for building and running single-cell analysis pipelines with [Scanpy](https://scanpy.readthedocs.io/). It talks to a Python JSON-RPC backend (bundled for releases) so end users can run the app without installing Python.

## What’s in this repo

- `mac/ScanwrMac/`: the macOS SwiftUI app + the bundled Python RPC server.
- `src/scanwr/`: a prototype Python GUI + pipeline runner (older / separate from the SwiftUI app).
- `requirements-lock.txt`: pinned Python deps for the backend/runtime.

## Project layout on disk

Each scGUI “project” is just a folder on disk. The app stores state in a single hidden directory:

- `Project/.scanwr/metadata.txt`: sample table (sample, group, path, reader)
- `Project/.scanwr/template.json`: current pipeline canvas workflow
- `Project/.scanwr/checkpoints/`: per-sample `.h5ad` outputs
- `Project/.scanwr/history/`: per-sample cached step signatures (for incremental re-runs)
- `Project/.scanwr/plots/`: saved plots (SVG)
- `Project/.scanwr/templates/`: optional workflow templates

## Development (macOS)

Prereqs:

- Xcode (or Xcode command line tools)
- A Python with `scanpy` installed. This repo includes `venv/` already.

Build/run the SwiftUI app from source:

```bash
cd mac/ScanwrMac
SCANWR_PYTHON=/Users/roshanlodha/Documents/scanwr/venv/bin/python swift run ScanwrMacApp
```

If you’re working in this repo, a convenience helper exists:

```bash
mac/ScanwrMac/scripts/clean_rebuild_dev.sh
mac/ScanwrMac/scripts/clean_rebuild_dev.sh --run
```

What it does:

- clears the scGUI cache (`~/Library/Caches/scGUI` and `/tmp/scgui-cache`)
- rebuilds via SwiftPM
- optionally runs the app

## Explore Data (plots)

Visualization lives in **Explore Data** (not in the pipeline builder). The intended flow is:

1. Run a pipeline (produces per-sample `.h5ad` in `Project/.scanwr/checkpoints/`).
2. Open **Explore Data** → choose a sample → “Load keys”.
3. Pick keys from `obs` or `var_names` and plot (saved as SVG into `Project/.scanwr/plots/`).

SVG is saved with editable text (Matplotlib `svg.fonttype: none`).

## Release packaging

- Current version: `0.1.1`
- Build outputs: `mac/ScanwrMac/dist/scGUI.app` and `mac/ScanwrMac/dist/scGUI-0.1.1.dmg`

Release/packaging docs (including bundling a relocatable Python runtime) are in `mac/ScanwrMac/README.md`.

If you just want a fresh `.app` you can double-click, run:

```bash
./rebuild_app.sh
```
