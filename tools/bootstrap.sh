#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

printf 'ALIGNMENT PENDING bootstrap\n'
if command -v godot >/dev/null 2>&1; then GODOT=godot
elif command -v godot4 >/dev/null 2>&1; then GODOT=godot4
else
  echo 'Godot not found in PATH. Install Godot 4.7.2 stable, then rerun.'
  exit 2
fi
"$GODOT" --version
# P47: tools/generate_audio.py (offline placeholder .wav generation) is
# superseded by the real, in-engine procedural audio system (P41's
# AudioSynth) — nothing loads its output, so no longer run it here; see
# docs/legal/ASSET_PROVENANCE.md.
# Re-import + rescan global class_name scripts first: running the smoke
# test script directly does not reliably refresh the class cache, so a
# newly added `class_name` (e.g. CameraController, Hud) can resolve as
# "Could not find type" on the very run that introduces it.
"$GODOT" --headless --editor --quit --path game
"$GODOT" --headless --path game --script res://tests/smoke_test.gd
printf '\nBootstrap checks passed. Open project: %s/game/project.godot\n' "$ROOT"
