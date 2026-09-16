# Asset provenance ledger

| Asset | Origin | License/ownership | Final? |
|---|---|---|---|
| assets/ui/alignment_pending_logo.svg | Created specifically for project as vector primitives | Project-owned working asset | No |
| assets/ui/dashboard_mockup.svg | Created specifically for project as vector primitives | Project-owned working asset | No |
| game/src/render/procedural_mesh_factory.gd (all office/staff 3D geometry it produces) | Procedurally generated at runtime by project code (BoxMesh/CapsuleMesh/CylinderMesh + StandardMaterial3D) — no imported mesh/texture files, nothing downloaded | Project-owned working code | No |
| game/data/staff_roles.json `visual_color` field (staff placeholder body tint) | Original per-role color values authored for this project | Project-owned working asset | No |
| game/src/audio/audio_synth.gd + game/src/autoload/audio_manager.gd (all SFX/music the game plays) | Procedurally generated PCM at runtime by project code (waveform synthesis + integer-ratio chord loops) — no imported/downloaded sound files | Project-owned working code | No |
| game/src/localization/pseudo_locale.gd (the QA pseudo-locale text) | Algorithmically generated at lookup time from the real English source text — not authored translation content | Project-owned working code | No |
| game/assets/branding/icon.svg (+ rasterized icon*.png, icon.ico) | Created specifically for this project: two triangles + a circle, palette matched to `assets/ui/alignment_pending_logo.svg`'s existing mark, rasterized in-engine via `tools/render_branding.gd` (no external image tool/download) | Project-owned working asset | Yes — shipped app icon (`project.godot` `config/icon`, `export_presets.cfg` Windows `application/icon`) |
| game/data/locale_es.json (the real "es" Spanish translation, 703 entries) | Authored by Claude (this project's AI pair-programmer) as a first-pass translation of the existing English source content; not a translation-memory import or third-party dataset | Project-owned working asset | No — see `docs/design/LOCALIZATION_CONTENT.md`'s "Known limitation": needs a native-speaker review pass before treating it as shipping-final |

Every new player-facing asset must be added here before merge.

## Notes
- `assets/ui/*.svg` are store-page/marketing concept art, not loaded by any game code (verified P47: no reference in `game/src/` or `game/scenes/`) — kept for store-page use, not part of the shipped game build.
- P47 removed the 11 placeholder `.wav` files under `assets/audio/` and stopped `tools/bootstrap.sh` from regenerating them (it called `tools/generate_audio.py`, an offline Python synth script bundled with the original devkit template, `bbc8d69`, before any numbered prompt). Confirmed via a project-wide reference search that no game code ever loaded these files — P41's real audio system (`AudioSynth`, above) took a different, in-engine runtime-synthesis approach instead, making the offline-generated files pure dead weight (regenerated every bootstrap run, shipped in the build, loaded by nothing). `tools/generate_audio.py` itself is left in place as harmless, unused reference tooling.
