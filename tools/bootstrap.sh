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
python3 tools/generate_audio.py
"$GODOT" --headless --path game --script res://tests/smoke_test.gd
printf '\nBootstrap checks passed. Open project: %s/game/project.godot\n' "$ROOT"
