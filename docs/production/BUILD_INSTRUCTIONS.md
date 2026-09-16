# Build instructions

## Prerequisites
- **Godot 4.7.2 stable** (exact version — see `CLAUDE.md`'s "Engineering standards"). Other 4.x versions are not verified against this project's smoke tests.
- Linux, macOS, or Windows host for the editor itself (headless Linux is what this project's own CI/verification scripts, `tools/bootstrap.sh`, run against).

## Verify a checkout (no export needed)
```
bash tools/bootstrap.sh
```
This does exactly what a release-candidate gate should: a headless editor import/rescan pass, then a full run of `game/tests/smoke_test.gd` (hundreds of assertions covering every prompt's acceptance criteria). "Bootstrap checks passed" at the end means the checkout is sound. This is the only build step verified end-to-end in the environment this project has been developed in so far — see `docs/production/KNOWN_ISSUES.md` for why the actual binary export below is not.

## Producing a distributable build
1. Install the matching **export templates** for Godot 4.7.2 stable (Editor menu: Editor > Manage Export Templates > Download and Install, or place them manually under `~/.local/share/godot/export_templates/4.7.2.stable/` on Linux / the equivalent per-OS path).
2. Open `game/project.godot` in the Godot 4.7.2 editor once, so it creates/updates `export_presets.cfg` (this repository does not commit one yet — see Known Issues).
3. Project > Export..., add a preset per target platform (Linux/X11, Windows Desktop; macOS requires a signing/notarization setup this project has not configured), and export.
4. Headless/CI equivalent, once presets exist and templates are installed:
   ```
   godot --headless --path game --export-release "Linux/X11" build/alignment_pending.x86_64
   godot --headless --path game --export-release "Windows Desktop" build/alignment_pending.exe
   ```
5. Smoke-test the exported binary directly (not just the editor-run project) before shipping: launch it, reach the main menu, start a campaign, save, and reload — the automated suite above only ever runs the project through the editor/`--script` runner, never the packaged export.

## Determinism note
Every simulation system in this project is seeded from `GameState.campaign_seed` via `SimClock`'s named RNG streams (see `docs/technical/` and any autoload's own docstring). A given seed plus the same sequence of player actions always reaches the same state — useful for reproducing a reported bug exactly if the seed and action log are known.
