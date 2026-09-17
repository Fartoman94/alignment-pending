# Phase 01 — Garage real

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_01_GARAGE.md`. Audited the running garage scene against the phase's own composition checklist before touching anything — most items were already real, from prior passes (this session's earlier `REAL_GAME_VISUAL_OVERHAUL` pass and before). Only implemented the genuine gaps.

## Composition checklist

| Item | Status | Where |
|---|---|---|
| 3 workstations completos | Already done | `Campaign._rebuild_office_visuals()` — chair/monitor/tower or laptop/mug per desk |
| 1 desk de team leader | **Partial** — see below | n/a |
| Coffee corner | Already done | `Campaign._build_break_room()` — fridge, vending machine, coffee machine, table, chair |
| Whiteboard | Already done | `PlanningWhiteboard` |
| Storage + cajas | Already done | Storage shelf + 3 cardboard boxes + file box + pallet |
| Sofá / lounge | Already done | `LoungeSofa` + `LoungeTable` + pizza box |
| Plantas | Already done | `_build_ambient_decoration()` |
| Garage door | Already done | Real modeled `garage_door_closed.glb` |
| Ductos / pipes / breaker | **Fixed this phase** | Breaker panel already existed; added `air_duct.glb` + `wall_pipe.glb` (previously imported, never placed) |
| Posters / señalética | **Fixed this phase** | Added `pinboard.glb` (previously imported, never placed) on the back wall |
| Clutter pequeño | Already done, extended | Toolbox/pallet/extension cord/broom/mugs/pizza box already existed; added `fire_extinguisher.glb` near the garage door for real safety-clutter realism |

**"1 desk de team leader" is honestly PARCIAL, not done**: the garage's 3 starting desks (`MainMenu.STARTING_DESK_CELLS`) are all visually and mechanically identical — there's no team-leader role concept at the garage tier in the actual data model (`StaffRoleCatalog`), so a visually-distinct 4th desk would be decoration with no real referent. Not faked; flagged here per the execution contract's Regla 6 ("no inventar completo").

## Changes made

`game/src/world/campaign.gd`'s garage-tier art block (`_rebuild_office_visuals()`) gained 4 new fixed-position props, all previously-imported-but-unused mega-pack assets (no new asset files):
- `air_duct.glb` — ceiling-mounted, back wall, right of the desk cluster.
- `wall_pipe.glb` — vertical pipe on the left wall, near the garage door.
- `pinboard.glb` — back wall, "posters/señalética" stand-in (a pinboard with pinned notes reads the same narrative role — "someone put things up on this wall" — without a real text-poster-rendering system, which doesn't exist here).
- `fire_extinguisher.glb` — floor-standing, near the garage door.

Same fixed-spot set-dressing discipline the rest of this block already uses (not a general prop-placement system — see `docs/production/KNOWN_ISSUES.md`).

## Verification

Real windowed render (`godot4 --path game --script`, Forward+/Vulkan), not a static code read:
- Default camera framing, before vs. after (`phase-01-before.png` / `phase-01-after.png`) — same seed, same 3-desk garage.
- A pulled-back back-wall framing (`phase-01-backwall-detail.png`) to confirm nothing clips through walls.
- Individual close-up shots of all 4 new props (camera focused directly on each one) confirming correct orientation and no floating/clipping: the air duct reads as a ceiling-mounted rectangular box, the pinboard as a flat board with pinned colored markers, the wall pipe as a vertical cylinder against the wall, and the fire extinguisher as a small red cylinder on the floor by the door.
- `tools/bootstrap.sh` full smoke suite, run after the change — green.

## Gate assessment

"No más de ~25% de piso visualmente muerto" — qualitative, not measured by floor-area script, but the real render shows a densely furnished room with very little open floor beyond the mandatory NPC route aisle (`BuildGrid.ROUTE_ROW`, which has to stay clear by design). Judged as passing on visual inspection.
