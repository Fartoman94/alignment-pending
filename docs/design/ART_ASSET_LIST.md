# Art asset production list

## Environment MVP
- 3 floor materials, 4 wall modules, 2 doors, glass partition.
- Desk A/B, office chair, meeting table/chairs.
- Workstation monitor/keyboard/cable cluster.
- Server rack A/B, cooling unit, power cabinet.
- Safety lab console, whiteboard, storage cabinet.
- Reception sign, plants, bins, coffee machine, boxes.

## Character MVP
- 3 body archetypes, 8 hair shapes, 12 clothing palettes, 6 accessories.
- Original walk, idle, type, inspect rack, whiteboard, talk, celebrate, stressed idle.

## VFX
- Selection ring, valid/invalid placement grid, research sparkline, rack heat haze (subtle), incident screen pulse.

## UI
- 32 original line icons with consistent 2 px visual language at 32/64 px.
- Resource badges, severity glyphs, role glyphs, research-node shapes.

## Asset naming convention (P39)
- **Node names** (in-scene `MeshInstance3D`/etc.): PascalCase, no spaces —
  `ServerRackBody`, `Torso`, `BackWall`.
- **Data-driven ids** (JSON `id` fields across `data/*.json`): snake_case,
  stable once shipped (referenced by save data and cross-file
  prerequisites) — `server_rack`, `safety_analyst`.
- **Asset files** (once real files exist under `assets/`, per
  `docs/legal/ASSET_PROVENANCE.md`): `assets/<category>/<snake_case_name>.<ext>`,
  category one of `ui`, `audio`, `env` (environment/props), `char`
  (characters), `vfx` — matching this list's sections.
- **Procedural color fields** in data (`color`, `visual_color`): a 6-digit
  hex string, no leading `#` (e.g. `"4c7ea8"`), consistent with how
  `Color(String)` parses it in GDScript.

## Procedural mesh/material helpers (P39)
`game/src/render/procedural_mesh_factory.gd` (`ProceduralMeshFactory`) is
the one place primitive 3D geometry gets built — every "programmer
primitive" (`BoxMesh`/`CapsuleMesh`/`CylinderMesh` + `StandardMaterial3D`)
scene code needs goes through it instead of constructing those inline, so
tinting/roughness stay consistent project-wide. No external mesh/texture
files are ever imported. Everything it produces is procedurally generated
at runtime by project code (see `docs/legal/ASSET_PROVENANCE.md`), not a
static asset file, until P40 replaces the placeholder staff visual with
real character art.

## Rule
Every asset gets a stable ID and provenance entry before it can be marked final.
