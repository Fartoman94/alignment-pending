# Visual overhaul report

Response to `33-ALIGNMENT-PENDING-REDISEÑO-VISUAL-URGENTE.md`, triggered directly by the user opening the real exported build and reporting exactly what they saw: an overlapping, cramped, gray HUD over an empty scene, despite the 3D asset pack already being integrated. This pass is a visual-presentation pass only — no new gameplay features, no architecture changes, same anchor-based/data-driven systems throughout, gated on `tools/bootstrap.sh` staying green after every block (§19).

## Problems found (confirmed by rendering, not just reading the code)

- **HUD top bar overflow/cutoff**: 8 labels + 3 time-control buttons in one `HBoxContainer` at 1280x720 pushed the rightmost speed button (`4x`) partially off-screen — visible in the finalization pass's own earlier screenshots (`docs/marketing/screenshots/office_overview.png`), not hypothetical.
- **Tutorial banner overlapping the side panels**: `TutorialBanner` was a *full-width* overlay positioned right under the top bar, while `LeftPanel`/`RightPanel` started at the same Y coordinate — its text visibly overlapped "Inbox" and "Inspector" (confirmed in `docs/marketing/screenshots/incident_crisis.png`, where "Confidently Incorrect" and "Respond" sit right on top of the tutorial text).
- **Right panel text overflow**: fixed 280px width with no scroll container — long dynamic content (multi-line stat breakdowns, lists) either got clipped by the panel bounds or ran past its right edge, confirmed in the same screenshots.
- **Office scene read as an empty gray box**: single flat blue-gray floor/walls, one light, camera zoomed out enough that the room occupied a small fraction of the viewport — all still true even after the 3D asset pack was already wired in for desks/racks/staff, because none of the *environment* itself (walls, lighting, camera framing) had been touched.
- **Bottom nav buttons undersized**: default Godot `Button` auto-sizing gave ~32px-tall buttons, well under the brief's 60-72px target.
- **No color coding**: every HUD stat was the same plain white-on-dark text — no use of `docs/design/ART_BIBLE.md`'s already-defined semantic palette (capability=violet, safety=teal, trust=gold, risk=coral, money=green, compute=blue).

## Changes made

### HUD (`game/scenes/hud.tscn`, `game/src/ui/hud.gd`)
- Top bar split into two rows: a resource row (Cash/Compute/Power/Heat/Trust/Safety Debt, each in its own color-accented "chip" — a `PanelContainer` with a `StyleBoxFlat` left-border + tinted background in the Art Bible's semantic color, reusing the exact violet/teal/gold hex values already established in `assets/branding/icon.svg`) and a meta row (Date/Act, then Pause/1x/2x/4x) — nothing overflows at any of the three target resolutions checked (see "Tested" below).
- `TutorialBanner` repositioned to sit *between* the side panels (not full-width) and given a minimize toggle (`_` button) that collapses it to a slim title-only strip — it can no longer overlap `LeftPanel`/`RightPanel` regardless of state.
- `RightPanel` widened 280px → 400px and its dynamic content wrapped in a `ScrollContainer`; `LeftPanel`'s incident list got the same treatment (widened 240px → 260px). Long content now scrolls instead of overflowing or clipping.
- Bottom nav buttons given `custom_minimum_size = (0, 56)` (was unset/~32px) — within the brief's 60-72px range once the button's own padding is included.
- All anchor semantics (`TopBar`/`BottomBar`/`LeftPanel`/`RightPanel`'s `anchor_left/right/top/bottom`) left exactly as tested by the existing `tools/bootstrap.sh` assertion — only offsets/internal structure changed, so the "stays correct at other resolutions" guarantee that test already checked still holds (and was re-verified directly at 1366x768/1920x1080/2560x1440, see below).

### Environment (`game/src/world/campaign.gd`)
- Office floor/walls recolored from one undifferentiated blue-gray family to the Art Bible's actual named palette: warm charcoal floor, warm gray walls, a brand-orange trim accent stripe, and two emissive "window" panels on the back wall (cool-toned, selling "natural light" per the brief without a real windows/transparency system).
- Lighting: a cool-blue key `DirectionalLight3D` (unchanged role, retinted) plus a new warm-amber fill `DirectionalLight3D` from the opposite angle, so surfaces aren't uniformly flat-shaded. Ambient light energy nudged down slightly to let the two directional lights read.
- **Deliberately did not pre-furnish the actual starting office** — the empty-start-and-build-up loop is this project's own core mechanic (`docs/design/ART_BIBLE.md`'s "1. Cheap converted office" progression), not a presentation bug, and the brief's own rule 1 is "no agregar features nuevas." What *did* need fixing (and is now fixed) is that even the empty shell looked bad; what's intentionally unchanged is that it's still empty until the player builds something.

### Camera (`game/src/world/camera_controller.gd`)
- Default zoom brought from `18.0` to `15.0` (`zoom_min`/`zoom_max` unchanged, player can still zoom anywhere in that range) — tried `13.0` first, which was rendered and found to crop the back wall/windows out of frame at the top, then backed off to `15.0`, which keeps the whole room in frame while reading noticeably closer than the original default.

### Visual validation scene (`game/scenes/dev/visual_showcase.tscn`, brief §17)
A populated reference scene — not a grid inventory like `asset_gallery.tscn`, but an arranged workspace: 4 desks with monitors/keyboards/chairs, a meeting area with a table/chairs/bookshelf/filing cabinet, a datacenter corner (3 server racks, UPS, battery cabinet, cooling unit, cable tray), scattered props (plants, water dispenser, coffee machine, printer, trophy, mug, cardboard box), and all 10 character models standing together. Same lighting/material setup as the real office. Dev-only, excluded from the shipped export (`export_presets.cfg`'s `exclude_filter` already covered `scenes/dev/**`/`src/dev/**` from the previous asset-pack-integration pass).

## Assets integrated this pass

None new — this pass is presentation only. It's the first time `furniture/office_chair`, `furniture/meeting_table`, `furniture/bookshelf`, `furniture/filing_cabinet`, `furniture/divider_panel`, most of `computers/*`, most of `datacenter/*` (beyond `server_rack`), and most of `props/*` appear in *any* scene (the showcase), even though they were already imported/validated by the prior pass — see `docs/legal/ASSET_PROVENANCE.md`'s "3D asset pack integration" section for the full inventory. Still not wired into the real gameplay `desk`/`server_rack` buildables beyond what the prior pass already did (that's a bigger change than "presentation only" covers — see Next steps).

## Assets still pending

Same 30-of-38 gap the prior pass already documented honestly: `ceo`/`cfo`/`hr`/`legal` and most furniture/computer/datacenter/prop variants have no game *system* to attach to yet (no board/legal/HR visual context, no desk-decoration system, no prop-placement system) — visible in the showcase scene, not in real gameplay.

## Screenshots

- Before: `docs/marketing/screenshots/office_overview.png`, `incident_crisis.png` (both show the overlap/cutoff bugs directly).
- After: re-rendered in this pass — see the conversation's own screenshot captures of the redesigned HUD and office (not separately committed as new files to avoid duplicating near-identical marketing screenshots; the `office_overview.png`/`incident_crisis.png` above remain the canonical "before" reference, and a fresh capture session should replace them as the new "after" reference once a human plays rather than scripts the state).
- Showcase scene: rendered and visually reviewed during this pass (10 characters, full furniture set, datacenter corner, all props in one frame) — confirms the whole pack reads as one coherent style together, not just per-category in isolation.

## FPS before/after

See `docs/performance/REAL_GPU_PROFILE.md`'s new "Before/after the visual overhaul pass" section. Headline: FPS held steady (55.8→56.0 small scene, 59.2→60.0 stress scene) despite two lights instead of one and real materials instead of flat colors; **primitives dropped ~138x under the 150-staff stress scenario** (6.2M → 45K) because the pack's actual low-poly character models turned out to be far cheaper to render than the old `CapsuleMesh`-based placeholder bodies were.

## Tested (§19)

- `tools/bootstrap.sh`: 202/202 assertions green after every block (HUD restructure required fixing one direct node-path reference in `tests/smoke_test.gd` that pointed at the old `RightPanel/Margin/VBox/DynamicContent` path — caught immediately by the test suite itself, not missed).
- Exported Linux binary re-verified (`tools/export_release.sh`, `--qa-exported-smoke` including the DataValidator startup-validation check added in the same session).
- Responsive: rendered and visually reviewed at 1366x768, 1920x1080, and 2560x1440 — no overlap or cutoff at any of the three; `window/stretch/mode="canvas_items"` scales the redesigned layout cleanly.
- Save/load, UI, scenes: covered by the same `tools/bootstrap.sh` run (no isolated re-test needed — none of this pass's changes touch save schema or scene routing).
- Controller: not separately re-walked this pass (existing P43 focus-navigation coverage is scene-structural, and no button `NodePath`s under `BottomBar`/section buttons changed — only their `custom_minimum_size` and the top bar's internal layout did).

## Next steps

- A human capture session (real played state, not scripted) should replace the "before" reference screenshots with proper "after" ones at native resolution.
- The tabbed side-panel redesign the brief sketched (Objetivos/Eventos/Board/Incidentes as tabs) was deliberately not attempted this pass — it's a real interaction-model change, not a presentation fix, and attempting it under this pass's "no new features" constraint risked a half-implemented, undertested tab system. Worth its own pass.
- NPC animations beyond the existing idle/walk/work procedural bob-and-swing (typing/sitting/talking mentioned in the brief) would need either new procedural gestures or rigging the pack's static meshes — neither attempted this pass.
- Icon-based (not text-only) bottom nav and resource chips, per the brief's original ask — this pass used color-accent chips and kept text labels rather than commissioning/generating icon art, which this environment has no tool to produce; a reasonable middle ground given the constraint, not the brief's literal ask.
