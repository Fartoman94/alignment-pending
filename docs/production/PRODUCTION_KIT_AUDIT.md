# Production kit audit — ALIGNMENT_PENDING_COMPLETE_PRODUCTION_KIT

Audit of `/home/mate/Descargas/ALIGNMENT_PENDING_COMPLETE_PRODUCTION_KIT` (the kit's own manifest: 250 `.glb`, 52 `.svg`, 22 `.wav`, 13 `.gd`, 2 `.gdshader`, 11 JSON data packs, 23 numbered prompts, plus 88 legacy markdown prompts and 4 old bundle zips under `12_PREVIOUS_PROMPTS_AND_BUNDLES/`) against the real repo state, per the kit's own `02_PROMPTS/01_AUDIT_AND_MAP.md`. Written before further integration, kept updated as work lands.

## Two reference images are not usable

`01_VISUAL_TARGET/CURRENT_BAD_STATE_1.png` and `_2.png` are full-desktop screenshots, not game captures — most of the frame is the project owner's own desktop (WhatsApp chats, unrelated browser tabs/repos). Not used as reference for anything; the real current-build baseline used throughout this audit is `tools/bootstrap.sh`'s real rendered output and `docs/art/screenshots/*` instead.

The remaining reference images (`TARGET_VISUAL_REFERENCE.png`, `ART_BIBLE.png`, `UI_KIT.png`, `NPC_ROSTER.png`, etc.) are AI-generated concept/mood art — a painterly semi-realistic style with a light-theme rounded-card UI kit. They're directional (composition, information hierarchy, "believable inhabited space" mood), not literal specs: the actual deliverable geometry (low-poly stylized `.glb`s) and the actual existing HUD (dark theme, already shipped and tested) can't and shouldn't try to pixel-match a different rendering style. Treated as inspiration, not a pixel target.

## `12_PREVIOUS_PROMPTS_AND_BUNDLES/` is legacy, already largely actioned

The 88 markdown prompts and 4 zips here (`ALIGNMENT_PENDING_MEGA_ASSET_PACK.zip`, `ALIGNMENT_PENDING_FINALIZATION_COMPLETE.zip`, etc.) are the same numbered briefs (`33-...REDISENO-VISUAL...`, `34-...REDISENO-NPCS...`, `35-...GARAGE-PROGRESION...`, `39-...GALERIA...`, and the `01-31` finalization pack) that the repo's own commit history already implements — cross-checked against `git log --oneline`: every one of those numbers has a matching shipped commit (visual overhaul, NPC visual rework, real-estate progression, MEGA_ASSET_PACK integration, the finalization pass P01-P47). Not re-actioned. Only `00-11` (the new numbered prompts) and the net-new asset folders are in scope going forward.

## Asset overlap: what's genuinely new vs. already shipped

`03_ASSETS_3D/_previous_pack/` is a byte-identical copy of the already-integrated `ALIGNMENT_PENDING_MEGA_ASSET_PACK` (98 files, matches `game/assets/models/mega/` exactly by filename). Not re-copied.

The kit's live `03_ASSETS_3D/` (excluding `_previous_pack/`) has 152 `.glb` files; 46 share a filename with something already in `game/assets/models/mega/` (treated as likely-redundant alternates, not re-copied without a concrete reason to prefer them). **106 are genuinely new** filenames, grouped by what they unlock:

| Group | Count | Status |
|---|---|---|
| `architecture/garage/*` detail props | 10 | **Done** — 8 wired (`docs/legal/ASSET_PROVENANCE.md` "Garage art pass"), 2 imported not yet placed |
| `architecture/office/*` (column, glass door/wall, carpet/wood floor, reception wall) | 7 | **Done (partial)** — `door_glass`+`reception_wall` wired for `premium_office`/`hq_building`, plus the original mega-pack's own unwired `support_column`; `floor_carpet`/`floor_wood` imported, not wired (would mean replacing the single-mesh procedural floor, a bigger change) |
| `architecture/city/*` (buildings, road, sidewalk, cars, tree, bench, lamp) | 10 | Not started — no city layer exists at all (kit prompt `10_CITY_AND_REAL_ESTATE.md`); real estate today (`RealEstateManager`) is menu/data-driven with no explorable exterior |
| `kitchen/*` (coffee machine, fridge, microwave, sink, table, chair, vending machine) | 7 | Not started — current ambient decoration has `water_dispenser`+`trash_bin`+plants only, no real break-room corner |
| `research/*` (lab bench, oscilloscope, research terminal, GPU test rig, whiteboard, tablet) | 5 (1 name-dupe) | **Done (partial)** — `research_terminal` wired to `safety_lab` (closed the documented procedural-box-fallback gap); the other 5 imported, orientation-verified, not yet wired (no second research buildable exists yet) |
| `vehicles/*` | 4 | Not started — depends on the city layer existing first |
| `characters/variants/*_{1,2,3}.glb` (10 roles × 3) | 30 | **Done** — all 30 wired into `StaffRoleCatalog.character_model_pool`, verified through the real `StaffAgent` pipeline |
| `rooms/*_complete.glb` (3 pre-built rooms) | 3 | **Not recommended as-is** — a monolithic pre-dressed room mesh conflicts with the existing per-tier, per-prop, data-driven office system (`Campaign._rebuild_office_visuals()`); adopting it would mean maintaining two competing ways to build a room. Kept available as a visual reference only. |
| `computers/*`, `datacenter/*`, `furniture/*`, `props/*` | ~30 | Same status as the original 2019-era pack: importable, but no per-desk decoration or general prop-placement system exists to place most of them (`ASSET_PROVENANCE.md` line 25) — unchanged gap, not this kit's to fix alone |

## Code templates (`06_CODE_GODOT/`) — reference only, not a drop-in

Per the kit's own `11_TOOLS/IMPORT_MAP.md`: *"integrate by domain, do not blindly overwrite existing managers."* Every one of these 13 scripts already has a real, tested, shipped counterpart in the repo:

| Kit template | Existing repo equivalent |
|---|---|
| `npc/NPCBrain.gd`, `NPCNeeds.gd`, `Workstation.gd`, `WorkRegistry.gd` | `src/world/staff_agent.gd` (state machine) + `src/autoload/task_manager.gd` (work-order assignment/reservation) — different design: player-assigned work orders, not autonomous need-driven AI |
| `npc/NPCSpawner.gd`, `ProceduralNPCVisual.gd` | `Campaign._spawn_staff_agent()` + `StaffAgent._build_visual()` (real `.glb` models, not procedural meshes — superseded twice over, see `docs/art/*_REWORK_REPORT.md`) |
| `environment/GarageBuilder.gd`, `CityBuilder.gd` | `Campaign._build_office()`/`_rebuild_office_visuals()`; no city equivalent exists yet |
| `progression/RealEstateManager.gd` | `src/autoload/real_estate_manager.gd` — already shipped, real (`docs/design/REAL_ESTATE_PROGRESSION_REPORT.md`) |
| `ui/HUDController.gd`, `MainMenuController.gd` | `src/ui/hud.gd`, `src/menu/main_menu.gd` — already shipped, tested, integrated with `EventBus`/localization/accessibility settings the templates know nothing about |
| `audio/AudioManager.gd` | `src/autoload/audio_manager.gd` + `src/audio/audio_synth.gd` — **architecturally different on purpose**: P47 deliberately removed static `.wav` playback in favor of real-time procedural synthesis (`ASSET_PROVENANCE.md`'s "Notes" section). The kit template plays static files. |
| `vfx/SelectionRing.gd`, `shaders/*.gdshader` | No exact equivalent; genuinely a gap — worth mining for the selection-outline shader specifically (current selection feedback is simpler) |

Mined for ideas where a real gap exists (see "NPC purposeful movement" below), never copy-pasted wholesale.

## `05_AUDIO/*.wav` (22 files) — not integrated, by design

Conflicts directly with the documented P47 decision to drop static placeholder audio for real-time procedural synthesis (`AudioSynth`). Re-introducing static `.wav` assets here would be a regression against a decision this project already made and recorded. Not integrated; flagged instead of silently skipped.

## `07_GAME_DATA/*.json` (11 files) — mostly parallel/incompatible schemas, not drop-in

Cross-checked each against its closest existing `game/data/*.json`:
- `incidents_80.json`, `worldwire_news.json`: the existing `news_templates.json` + narrative-event systems already cover this ground with a different, already-integrated schema (`data/events_seed.json`, `WorldStateManager`). Worth a **content** pass (mining incident text/variety) but not a schema swap.
- `npc_roles.json`, `npc_traits.json`: existing `data/staff_roles.json` + `data/staff_traits.json` already do this, wired end-to-end (skills, hiring, mechanical effects). Not replaced.
- `company_progression.json`, `office_upgrades.json`, `real_estate.json`: existing `data/company_tiers.json` + `data/office_upgrades.json` + `data/districts.json`/`buildings.json` already implement and ship this (today's real-estate progression pass). Not replaced.
- `schedules.json`, `tutorial.json`, `ui_layout.json`, `names.json`: not cross-checked line-by-line yet — lowest priority, smallest blast radius either way.

## `08_GODOT_RESOURCES/materials/*.tres` (10 files) — not integrated

The existing office palette (`Campaign._office_palette()`) already gives a deliberate per-tier material progression (garage grime → HQ polish), documented and rendered. These `.tres` files are flat, tier-agnostic materials that would need the same per-tier treatment to not be a downgrade; not worth the churn for a straight swap.

## `04_ASSETS_VECTOR/*.svg` (52 files) — usable, not yet wired

Real, directly usable SVGs (icons, role portraits, posters, signage) that don't conflict with anything existing. Not yet checked against `src/ui/hud.gd`'s current icon usage to find concrete swap-in points — next candidate for a focused UI pass.

## `09_LANDING/` (`index.html` + `style.css`) — reference only

The project's landing page is a published Claude Artifact (`ASSET_PROVENANCE.md`'s "Landing page" row), not a repo-shipped static site — this kit's HTML/CSS has no natural home in `game/` and duplicates work already done a different way. Kept as inspiration for the next landing-page iteration, not integrated as files.

## Done this pass

- **Garage art pass** (`69ca19e`): 8 new clutter props wired, verified by rendering (see `docs/legal/ASSET_PROVENANCE.md`).
- **Break-room + purposeful NPC movement**: real break-room corner (5 of 7 new kitchen models) placed in `BuildGrid.ROUTE_ROW`; `StaffAgent` idle wander now has a 30% chance to head there instead of a uniform-random point. Verified behaviorally (a real agent reaches the spot in a scripted real-campaign run), not just by code review. See `docs/legal/ASSET_PROVENANCE.md`'s "Break-room + purposeful NPC movement" note for the full honest-scope statement.
- **Safety lab model**: `research_terminal.glb` wired to the `safety_lab` buildable, closing a gap flagged since the original 3D asset pack integration.
- **Office-tier architecture pass**: real glass entrance + reception wall + flanking support columns for `premium_office`/`hq_building`, replacing the palette-only treatment those tiers had.
- **Character-variant pool expansion**: 30 new mesh variants (10 roles × 3) wired into `character_model_pool`, including `data_ops`'s first-ever variants (previously a single fixed model, no variety at all).

## Recommended next priorities (highest value / best-scoped first)

1. ~~NPC purposeful movement~~ — **done**, see above.
2. ~~Kitchen/break-room prop pass~~ — **done**, see above.
3. ~~Research lab asset~~ — **done**, `research_terminal` wired to `safety_lab`.
4. ~~Office-tier architecture pass~~ — **done**, entrance/reception/columns for `premium_office`/`hq_building`.
5. ~~SVG icon audit~~ — **checked, not integrated, by design**: both candidate spots (`hud.gd`'s resource-chip icons AND its employee-card avatar) turned out to be the same deliberate, consistently-applied choice — procedurally styled (a colored dot / a colored circle-plus-initial), explicitly documented as "no external icon image/font glyph... same 'procedurally generated, not imported' discipline as ProceduralMeshFactory's 3D geometry." Forcing the kit's SVGs into either would regress that decision the same way the static-audio pack would have. No non-conflicting UI integration point found this pass; the 52 SVGs stay available but unused, same honest-gap treatment as everything else in this ledger.
6. City layer + character-variant mesh pool — largest, least-scoped items remaining; the kit's own master prompt gates further large work on the vertical slice already being solid, which items 1-4 above now establish.

## Honest scope statement

This kit is a multi-week production program condensed into 22 numbered prompts, not a single-pass task. Each item above gets the same treatment already established in this repo's history: real implementation, verified by actual rendering (not just "it imports"), a written report, and its own commit — never a bulk unverified dump of 250 assets. Items not listed as "Done" are open, tracked here, not silently dropped.
