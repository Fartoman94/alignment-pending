# Garage vertical-slice recovery report

Response to `ALIGNMENT_PENDING_GARAGE_VERTICAL_SLICE_RECOVERY`, whose own brief opens with: *"La build actual está técnicamente viva pero visualmente sigue siendo un blockout."* Confirmed by a real screenshot of the actual running build (`01_REFERENCES/CURRENT_BUILD.png`) before touching any code — this wasn't a documentation-only claim to take on faith.

## Root cause, not just symptoms

The garage didn't read as unconvincing because of asset *quality* — every character role, buildable, and piece of set dressing wired so far this session is real, authored, correctly-oriented geometry (`docs/art/PLACEHOLDER_AUDIT.md`). It read as unconvincing because **a new campaign started with zero buildings placed** (`GameState.reset_to_defaults()` → `buildings = []`) — an empty floor, 3 hired staff with no work to do, camera framing tuned for a room that had nothing to show. An earlier pass (`campaign.gd`'s own comment, now rewritten) had called this deliberate, reading the Art Bible's "cheap converted office" tier-progression note as license for a literally empty start. Every visual-target reference this project has ever used shows the opposite: a garage already staffed and working on day one.

## What changed

1. **`MainMenu._seed_starting_workstations()`** — a new campaign now places 3 real desk buildings and assigns each of the 3 starting hires to a real `research_sprint` work order at their own desk, through the exact same `GameState.buildings`/`TaskManager` plumbing a save/load restore already uses. No new mechanism; `Campaign._spawn_staff_agent()`'s existing "resume an in-progress task" path needed zero changes.
2. **Camera** — default zoom `15.0 → 13.5` (closer, per the brief's "20-30% closer") plus a non-zero default pan toward the back wall, so the closer zoom doesn't push the windows up behind the persistent top HUD bar (confirmed by rendering — a bare zoom change alone did crop them, the same failure mode a prior pass had already hit once at 13.0).
3. **Lighting** — ambient `0.55 → 0.7`, warm fill light `0.35 → 0.55`. A render at the new closer zoom with the old values read as murky/underlit; re-verified no blown-out highlights at the new ones.
4. **Garage density pass** — around the 3 starter desks: a chair, monitor and mug at each (desktop towers at two, a laptop at the third, for variety); a whiteboard "planning wall" near the back-left corner; a sofa + coffee table "mini lounge" at the opposite end of the route row from the existing break room; a few more cardboard boxes near the existing storage shelf. Every one of these already existed in one of the two supplied asset packs, imported since an earlier pass, unwired until now — no new files copied in.

Every item above was verified by rendering the real campaign scene (not a synthetic close-up shot alone) — the default view a player actually sees on New Campaign, matching the failure mode this whole pass was responding to.

## Not attempted this pass

- **`docs/design/ART_BIBLE.md` alignment for small_office/medium_office**: unrelated to the garage, out of this pass's stated scope ("NO intenta expandir el juego").
- **The recovery package's full NPC FSM** (`ACQUIRE_TASK/MOVE_TO_TARGET/WORK/BREAK/MEETING/TALK/IDLE`, `Workstation`/`WorkstationRegistry` reservation classes): not adopted verbatim. Cross-checked its P0 behavior checklist item by item against what the existing `StaffAgent`/`TaskManager`/`NavCoordinator` system plus this session's break-room work already does — every P0 behavior item is already satisfied (below) without a parallel reservation system duplicating what `TaskManager.can_assign()`/`is_building_reserved()` already does. A `MEETING`/`TALK`/`INSPECT` state expansion is real, additional scope beyond what the checklist requires — not built, to avoid over-engineering past an honest need.
- **UI rebuild** (`04_UI_REBUILD.md`): the right-side panel's tab structure (Overview/Staff/Objective/Incidents), a dedicated non-blocking staff-roster screen, and the described HUD reflow are a genuinely separate, larger initiative touching most of `hud.gd`'s ~20 `_dynamic_content` consumers — not attempted this pass. The specific P0 checklist item "Staff roster does not permanently cover gameplay" is **not** resolved (see checklist below) — named explicitly, not silently dropped.

## Acceptance checklist

Against `05_QA/GARAGE_ACCEPTANCE_CHECKLIST.md`:

### P0 Visual
- [x] Garage clearly reads as a garage
- [x] Garage door visible
- [x] 3 real workstations visible
- [x] PCs/monitors clearly visible
- [x] Shelves, boxes, coffee, whiteboard present
- [x] NPCs are not white/block placeholders (real character models, since an earlier pass)
- [x] NPC roles visually distinguishable (per-role clothing/color, since an earlier pass)
- [x] Camera is close enough
- [x] Room is not mostly empty floor
- [x] Lighting has depth
- [ ] No UI overlap — not re-audited this pass; not a known regression, just not specifically checked
- [~] Staff roster does not permanently cover gameplay — **partially true, checked rather than assumed**: `hud.gd`'s right panel already clears back to empty/selection state the moment the player clicks a 3D object (`_on_selection_changed`) or any other bottom-nav tab (`_on_section_pressed`) — it's not literally stuck open forever, `CURRENT_BUILD.png` just happened to be captured with Staff as the active tab. What's real and still unaddressed: while Staff *is* the active tab, it's a static docked side panel occupying a large fixed share of the screen, not the "opens as a dedicated screen" the brief asks for — that's the UI rebuild item below, not fixed this pass.

### P0 Behavior
- [x] NPCs do not wander randomly — purposeful movement (break-room destination) shipped a prior pass this session; now most staff spend most of their time on a real assigned work order, not wandering at all
- [x] NPCs move to actual workstations (the new seeded desks)
- [x] Workstations are reserved (`TaskManager.is_building_reserved()`, pre-existing, exercised by the new seeding)
- [x] Two NPCs do not occupy one chair (same reservation mechanism)
- [x] NPC stays at task long enough to read visually (`research_sprint` = 240 sim-minutes)
- [x] Typing/sitting state matches workstation (`StaffAgent`'s existing `WORKING` pose)
- [x] Coffee break has actual coffee destination (prior pass this session)

### P1 Polish
- [x] Posters/signage — pre-existing (garage motto/branding posters from an earlier pass)
- [x] clutter details (this pass)
- [ ] selection feedback — not touched
- [ ] ambient audio — not touched (out of scope; static-audio integration was separately, deliberately declined this session, see `docs/legal/ASSET_PROVENANCE.md`)
- [ ] hover/focus states — not touched
- [ ] worker card opens on inspect — not verified this pass

## Gate

Per the recovery package's own rule: **do not expand to new offices/city/features while the garage checklist is unmet.** Two P0 Visual items remain open — "no UI overlap" wasn't re-audited, and the staff roster, while not literally stuck open forever (checked, not assumed), is still a static docked panel rather than the dedicated non-blocking screen the brief asks for. Every P0 Behavior item is done. The garage itself (visual + behavior) is in real, verified shape; the UI rebuild is the honest remaining blocker before this gate is fully clear, named as a separate follow-up rather than declared done.
