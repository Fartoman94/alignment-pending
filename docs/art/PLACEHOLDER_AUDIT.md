# Placeholder audit

Response to the garage vertical-slice recovery package's `01_STOP_PLACEHOLDERS.md`. Inventories what's actually placeholder geometry today vs. real authored assets, and what scenes still fall back to procedural shapes.

## What's placeholder today

- **`safety_lab` buildable, before this session**: procedural box (`ProceduralMeshFactory.make_box()`), no matching asset in either 3D pack. Resolved this session — `research_terminal.glb` now wired (`docs/legal/ASSET_PROVENANCE.md`).
- **Every buildable other than `desk`/`server_rack`/`safety_lab`**: doesn't exist yet — `BuildableCatalog` only has 3 entries total. Not a placeholder problem so much as "the buildable roster is small"; out of this pass's scope.
- **HUD resource-chip icons and employee-card avatars**: intentionally procedural (a colored dot / a colored circle-plus-initial), not a placeholder — a deliberate, documented design choice (see `src/ui/hud.gd`'s own doc comments), confirmed this session when auditing the production kit's SVG icon set against it. Not something to "fix" by importing images.

## What has real, sufficient-quality assets

Every character role (10/10), the 3 wired buildables, all garage/office/kitchen/research/city set dressing placed so far (this session's production-kit integration passes), the 3 starting desks + chairs/monitors this pass adds. None of this is procedural-box placeholder — all real, authored low-poly `.glb` geometry from the two supplied asset packs, oriented and scaled correctly (verified by rendering, not assumed).

## What must be replaced (and the fix, this pass)

The real problem `01_STOP_PLACEHOLDERS.md` is pointing at wasn't placeholder *geometry* — it was an **empty room**: a new campaign started with zero buildings placed (`GameState.reset_to_defaults()` → `buildings = []`), so the garage rendered as a big empty floor with 3 wandering NPCs and nothing to look at, regardless of asset quality. Fixed this pass (`MainMenu._seed_starting_workstations()`): 3 real desks placed, 3 real work orders assigned, real chairs/monitors/desktop towers/whiteboard/sofa/coffee table/box clutter added around them (see `docs/design/GARAGE_VERTICAL_SLICE_REPORT.md` for the full density pass).

## Scenes that fall back to procedural shapes

- `BuildController._make_mesh()` — the **ghost preview** while placing a building is always a plain translucent tinted box, on purpose (`_make_real_mesh()`'s own doc comment: "a plain tinted silhouette is clearer valid/invalid placement feedback than a detailed model would be"). Not a placeholder to fix — a deliberate UX choice, unrelated to the garage's day-one appearance.
- Any future buildable added with no `model` field in `data/buildables.json` — `_make_real_mesh()`'s fallback path, by design (keeps the game running instead of crashing on a missing asset).

## No other placeholder geometry found

Searched for remaining procedural-only game objects: staff character bodies (real models since the original pack integration), every wired buildable, every tier's office architecture (garage through hq_building, this session), the break room, the city-view window backdrop. Nothing else currently ships as an unauthored primitive that reads as "final art."
