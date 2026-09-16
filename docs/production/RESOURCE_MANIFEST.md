# Resource manifest — what must ship in a release build

Generated against commit at the time of writing. Regenerate by re-running the `find` commands below from `game/` if this drifts.

## Scenes (7) — `res://scenes/*.tscn`
`boot`, `campaign`, `credits`, `ending`, `hud`, `main_menu`, `settings`. All 7 are asserted loadable both by `tests/smoke_test.gd` (source) and `tests/exported_build_smoke.gd` (packaged build, 4 of the 7 — `boot` is excluded from the instantiate check because it self-navigates away in `_ready()`, and `credits`/`ending` are exercised by other smoke-test assertions instead).

## Data catalogs (26) — `res://src/data/*.gd`
Every `.gd` file under `src/data/` is a data-driven catalog (`AchievementCatalog`, `IncidentCatalog`, `StaffRoleCatalog`, `ResearchNodeCatalog`, etc. — full list via `find game/src/data -maxdepth 1 -name "*.gd"`) plus `DataValidator`. `tests/exported_build_smoke.gd` walks this directory at runtime via `DirAccess` inside the packaged build (not a hardcoded list), so it cannot silently stop covering a catalog added later.

## Autoloads (31) — declared in `project.godot`'s `[autoload]` section
Every manager (`GameState`, `SaveManager`, `IncidentManager`, `RivalManager`, ... — see `project.godot` for the authoritative list). `tests/smoke_test.gd` and `tests/exported_build_smoke.gd` both assert a subset of these are present in the live tree; `project.godot` itself (which is always packaged) is the source of truth for the full set, since Godot refuses to boot at all if a listed autoload script is missing from the export.

## Audio — none baked
`docs/design/AUDIO_BIBLE.md` and `AudioSynth`/`AudioManager` (P41) generate every SFX/music cue **procedurally at runtime**. There are zero `.wav`/`.ogg`/`.mp3` files anywhere under `game/` (`find game -name "*.wav" -o -name "*.ogg" -o -name "*.mp3"` returns nothing) — so there is no baked audio asset that could go missing from a build. This is a real, verified property of the current audio pipeline, not an oversight.

## Branding (this pass) — `res://assets/branding/`
`icon.svg` (source, original — two triangles + a circle, palette from the existing wordmark in `assets/ui/alignment_pending_logo.svg`), rasterized via `tools/render_branding.gd` into `icon.png` (app icon, `project.godot`'s `config/icon`) and `icon.ico` (Windows executable icon, `export_presets.cfg`'s `application/icon`). Both are referenced by name from `project.godot`/`export_presets.cfg`, so a missing file fails the export outright rather than silently shipping without an icon — already verified once (see `LEAK_INVESTIGATION.md` sibling doc's export re-run log: the very first `.ico` build was missing sizes and Godot's export step printed explicit `WARNING: Modificación de Recursos: Falta un ícono de tamaño "N"` for each, which is exactly the kind of failure this manifest exists to make visible instead of silent).

## UI source art — `res://assets/ui/`
`alignment_pending_logo.svg` (wordmark), `dashboard_mockup.svg` (reference mockup, not currently instantiated by any scene — a design reference asset, not a shipped one; flagged here rather than silently included).

## Character models (10) — `res://assets/models/characters/*.glb`
`junior`, `engineer`, `researcher`, `safety`, `legal`, `ops`, `hr`, `manager`, `ceo`, `cfo` — see `docs/legal/ASSET_PROVENANCE.md` for origin. 6 are wired: `StaffRoleCatalog`'s `character_model` field maps each of the 6 playable staff roles to one of these files, loaded by `StaffAgent._build_visual()` in place of the old P39/P40 procedural capsule body. `ceo`/`cfo`/`hr`/`legal` are imported and validated (`DataValidator` confirms every `character_model` path that IS referenced by a role resolves to a real file, and `scenes/dev/asset_gallery.tscn` displays all 10) but have no game system wired to them yet. The pack's authored orientation is Z-up in local mesh space, not Godot's Y-up — confirmed by rendering one and looking at the pixels before assuming — so every loader applies a `-90°` X correction; see `StaffAgent`'s class-level doc comment for the full reasoning, including why the correction has to be on a dedicated wrapper node and not the agent itself.

## What's explicitly excluded from the shipped export
`export_presets.cfg`'s `exclude_filter` strips `tools/**` (dev-only asset-rendering scripts), `scenes/dev/**`/`src/dev/**` (the asset gallery QA scene), and `tests/smoke_test.gd`(`.uid`) — the ~200-assertion source suite is meaningless without the editable project tree it inspects, and isn't needed at runtime. `tests/exported_build_smoke.gd` is deliberately **not** excluded — `src/boot/boot.gd` `preload()`s it, so the packaged game needs it present to honor `--qa-exported-smoke`.

## Automated verification
- Source-tree scene/catalog/autoload existence: `tests/smoke_test.gd` (`tools/bootstrap.sh`).
- Packaged-build scene/catalog/autoload loadability: `tests/exported_build_smoke.gd` (`--qa-exported-smoke`, run automatically by `tools/export_release.sh`).
- No real-world AI-company marks in any data file, no orphaned placeholder audio, no third-party addons: `DataValidator`'s release-candidate content gate (P47), also part of `tools/bootstrap.sh`.
