#!/usr/bin/env bash
# Reproducible release export: Linux + Windows release binaries, packaged
# and checksummed into dist/. Requires Godot 4.7.2 stable plus its matching
# export templates (see docs/production/BUILD_INSTRUCTIONS.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v godot >/dev/null 2>&1; then GODOT=godot
elif command -v godot4 >/dev/null 2>&1; then GODOT=godot4
else
  echo 'Godot not found in PATH. Install Godot 4.7.2 stable, then rerun.'
  exit 2
fi

echo "== bootstrap gate =="
bash tools/bootstrap.sh

rm -rf dist
mkdir -p dist/linux dist/windows

echo "== export: Linux release =="
"$GODOT" --headless --path game --export-release "Linux" ../dist/linux/alignment_pending.x86_64
chmod +x dist/linux/alignment_pending.x86_64

echo "== export: Windows Desktop release =="
"$GODOT" --headless --path game --export-release "Windows Desktop" ../dist/windows/alignment_pending.exe

echo "== smoke: exported Linux binary =="
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
HOME="$TMP_HOME" timeout 60 "$ROOT/dist/linux/alignment_pending.x86_64" \
  --headless --display-driver headless --audio-driver Dummy -- --qa-exported-smoke

echo "== package =="
( cd dist/windows && zip -q -9 alignment_pending_windows_x86_64.zip alignment_pending.exe && rm alignment_pending.exe )
( cd dist/linux && tar -czf ../alignment_pending_linux_x86_64.tar.gz alignment_pending.x86_64 )

echo "== checksums =="
( cd dist && sha256sum linux/alignment_pending.x86_64 alignment_pending_linux_x86_64.tar.gz windows/alignment_pending_windows_x86_64.zip > CHECKSUMS.sha256.txt )
cat dist/CHECKSUMS.sha256.txt

printf '\nRelease export complete: %s/dist\n' "$ROOT"
