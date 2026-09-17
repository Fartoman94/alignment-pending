# Phase 07 — Polish + QA

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_07_POLISH_QA.md`.

## Checklist

| Item | Status |
|---|---|
| Audio ambience | Already done — `AudioManager`'s adaptive music system keeps a synthesized calm pad loop (`AudioSynth.generate_pad_loop()`) playing continuously from boot, crossfading to a tense bed during incidents. A persistent, always-on background bed genuinely satisfies "ambience," even though it was built under the "adaptive music" label rather than a separate system — checked, not re-implemented |
| Feedback selección | **Real, pre-existing gap, not fixed this pass** — see below |
| Doors/use feedback | Not applicable in the same sense the bundle's own `DOOR_AUTO_OPEN.gd` template implies — this project has no animated doors (the garage door is a static mesh); object-use feedback exists via the contextual animations (Phases 2/3: typing/talk/sit) |
| Shadows/material polish | Already covered by the `REAL_GAME_VISUAL_OVERHAUL` pass (SSAO/SSIL) and this pass's fog tuning |
| Collision hunt | Covered by existing `tools/bootstrap.sh` assertions (`BuildGrid occupancy, overlap prevention, and mandatory-route blocking work`) |
| Navigation deadlock hunt | Covered by existing smoke tests (`20 StaffAgents all made movement progress with no obvious deadlock`, the 150-agent stress block) |
| Traffic overlap hunt | Covered by construction — each of the 3 vehicles has its own dedicated lane line, verified in `phase-05-report.md` |
| Save/load smoke | Covered by existing smoke tests (corrupted-autosave fallback, real estate state persistence, and dozens more) |
| 1080p / 1366x768 | **Verified this pass** — see below |
| Before/after final | See `docs/visual-progress/`'s full set, and the summary below |

## Real gap found, not fixed: no click-to-select feedback

`EventBus.selection_changed(kind, entity_id)` exists and `Hud._on_selection_changed()` is fully wired to react to it (updates the Inspector panel) — but **nothing in the codebase ever emits it**. There is no click-to-select system in the 3D world at all: no raycast-from-mouse, no building/staff-agent picking, no highlight/outline. This is dead plumbing, not a missing coat of polish on an existing feature.

Building this properly (3D picking, a real selection state, a visual highlight — the bundle's own `SELECTION_OUTLINE.gdshader` would be the right tool for the highlight half of it) is a genuine new interaction system, not a "polish" fix, and implementing one for the first time this late in a QA pass risked shipping something half-tested. Flagged honestly here and in `docs/production/KNOWN_ISSUES.md` rather than either silently skipped or hastily bolted on.

## Multi-resolution check

Real windowed renders at 1366×768 and 1920×1080, with the Staff panel open (the densest real panel content in the game) — both render cleanly, no text overflow, no overlapping elements, panel widths scale correctly. See `phase-07-res-1366x768.png` / `phase-07-res-1920x1080.png`.

## Verification

`tools/bootstrap.sh` full smoke suite — green after every change this masterpack's phases made. `tools/export_release.sh` (Linux+Windows export + packaged-binary `--qa-exported-smoke`) run once more before the final commit.
