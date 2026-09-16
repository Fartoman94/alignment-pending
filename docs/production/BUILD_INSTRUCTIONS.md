# Build instructions

## Prerequisites
- **Godot 4.7.2 stable** (exact version — see `CLAUDE.md`'s "Engineering standards"). Other 4.x versions are not verified against this project's smoke tests.
- Linux, macOS, or Windows host for the editor itself (headless Linux is what this project's own CI/verification scripts, `tools/bootstrap.sh`, run against).

## Verify a checkout (no export needed)
```
bash tools/bootstrap.sh
```
This does exactly what a release-candidate gate should: a headless editor import/rescan pass, then a full run of `game/tests/smoke_test.gd` (hundreds of assertions covering every prompt's acceptance criteria). "Bootstrap checks passed" at the end means the checkout is sound.

## Producing a distributable build
`export_presets.cfg` is committed at the repo root of `game/` with two presets, `Linux` and `Windows Desktop` (both release, `x86_64`, single embedded-pck binary, custom icon). Reproducible end-to-end:

```
tools/export_release.sh
```

This runs the bootstrap gate, exports both platforms, smoke-tests the packaged Linux binary in-process (`--qa-exported-smoke`, see `docs/qa/EXPORTED_BUILD_SMOKE.md` — Godot's `--script` flag does not work against an exported binary, only against an editable project, so the packaged build checks itself instead), packages a `.tar.gz`/`.zip`, and writes `dist/CHECKSUMS.sha256.txt`. Needs the matching **export templates** installed first (`~/.local/share/godot/export_templates/4.7.2.stable/` on Linux, downloaded from the same Godot 4.7.2 stable release as the engine and SHA512-verified against its published `SHA512-SUMS.txt`).

Manual equivalent of the export step alone, once templates are installed:
```
godot --headless --path game --export-release "Linux" ../dist/linux/alignment_pending.x86_64
godot --headless --path game --export-release "Windows Desktop" ../dist/windows/alignment_pending.exe
```

Verified end-to-end in this project's own development environment: the Linux binary boots, passes `--qa-exported-smoke`, and runs standalone outside the editor. The Windows `.exe` is built and packaged the same way (cross-exported from Linux using the official Windows export templates) but has never been *run* — that needs a real Windows machine, see `KNOWN_ISSUES.md`.

## Determinism note
Every simulation system in this project is seeded from `GameState.campaign_seed` via `SimClock`'s named RNG streams (see `docs/technical/` and any autoload's own docstring). A given seed plus the same sequence of player actions always reaches the same state — useful for reproducing a reported bug exactly if the seed and action log are known.
