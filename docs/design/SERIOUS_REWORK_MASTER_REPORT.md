# Serious rework master report

Response to `ALIGNMENT_PENDING_SERIOUS_REWORK_MASTER` — user's own words: *"vas a tomarte este proyecto en serio... quiero ver mejoras tanto a motor grafico como a motor de funcionamiento"* (take this seriously, improvements to both the graphics engine and the functioning/gameplay engine). This pass's real deliverable is the second half: a genuine NPC behavior engine (identity, needs, a real scoring planner), not another visual-only pass.

## Block 00 (VISUAL_GRAPHICS_AUDIO_SYSTEM): byte-identical to already-implemented work

Checked before touching anything: `diff -rq` against `ALIGNMENT_PENDING_REAL_GAME_VISUAL_OVERHAUL` (fully implemented and pushed earlier this session, see `docs/art/REAL_GAME_VISUAL_OVERHAUL_REPORT.md`) returned **zero differences** — every file in this block is the exact same bundle. No re-work needed or done here; re-implementing it would have been pure waste. If the graphics changes from that earlier pass aren't visible, the build being looked at predates that push (`f88f644`) — pull latest / relaunch the exported binary.

## Block 01 (NPC_BEHAVIOR_SYSTEM): the real new work — "motor de funcionamiento"

`StaffAgent` gained a genuine identity/needs/planner layer, adapted from the bundle's own `NPCIdentity`/`NPCNeeds`/`NPCPlanner` templates onto the existing, tested `StaffAgent`/`NavCoordinator`/`TaskManager` pipeline (not a rewrite onto the bundle's separate `CharacterBody3D`-based classes — same "don't replace a working system" call this project keeps making, see `docs/visual-progress/phase-03-report.md`).

### Personality and needs (new)
- 8 traits per agent (`focus`, `sociability`, `patience`, `diligence`, `stress_tolerance`, `coffee_affinity`, `meeting_affinity`, `autonomy`), rolled once per agent with a real per-role bias (`ROLE_TRAIT_BIAS`) so **the role sets a distribution, not a value** — two engineers still differ from each other, but read differently from two HR partners on average. Verified with a 40-sample statistical smoke test, not a single lucky roll.
- 4 live needs (`need_energy`, `need_focus`, `need_social`, `need_stress`) that actually tick: energy/focus drain faster while working, social drains unless actively talking, stress rises while working and falls otherwise — moderated per-agent by `stress_tolerance`.

### The planner (replaces the old coin-flip)
The old system (`AMBIENT_DESTINATION_CHANCE`, a flat 65% coin-flip between "go somewhere real" and "walk to a uniform-random point") is gone. `_score_ambient_destination()` scores every candidate (break room / whiteboard / lounge) from real needs × personality × a short-term memory penalty (an agent won't repeat the same spot twice in a row just because it still scores highest) — verified directly: a starved, coffee-loving agent scores the break room clearly above a rested, coffee-indifferent one; a recently-visited tag scores lower than a fresh one.

### Stuck recovery (new)
Movement tracks real displacement, not elapsed time — if an agent makes no real progress for 2.5s (a nav dead-end, a reservation race, anything), it abandons the destination, releases the reservation, and lets the planner pick again, instead of freezing. Verified by calling the recovery function directly and checking the reservation is actually freed for another agent to claim.

### Furniture collision (real bug found and fixed)
Large ambient furniture (lounge sofa/table, break-room table/coffee machine/fridge/vending machine, storage shelf, whiteboard, steel beam) had **zero navigation obstacles** — agents could walk straight through them. Added real `NavigationObstacle3D`s, same technique `BuildController` already uses for placed buildings.

**Caught a real bug while doing this, not assumed correct**: the first radius pass only checked raw distance from obstacle center to each ambient destination point, not accounting for the nav agent's own 0.3-unit body radius. That made `LOUNGE_SPOT` and `BREAK_SPOT` themselves unreachable — instrumented testing showed an agent stalled 0.35 units short of its target, circling forever, just outside its own arrival tolerance. Fixed by requiring `distance > obstacle_radius + agent_radius + margin` for every furniture piece near a destination, and re-verified both spots are reachable again before moving on.

### Acceleration/deceleration (new)
Movement used to jump straight to full speed the instant a move started (only rotation was ever smoothed). Added a ~0.3s ramp-up on move start, composing with the existing avoidance/rotation smoothing rather than replacing it.

### Live status in the UI (new, ties the system to something visible)
The staff detail panel's "Status:" line used to hard-default to "Idle" whenever no mechanical `TaskManager` order was assigned — true even while that person's agent was visibly walking to the coffee machine or sitting on the lounge sofa. It now reads the live agent and shows "Coffee break" / "At the whiteboard" / "Relaxing" / "Walking" / "At their desk" accordingly. Verified with a real screenshot showing `Status: Relaxing` in the actual Inspector panel while the 3D agent sits on the lounge sofa.

### Audio tied to real actions (new, synthesized — not the bundle's .wav files)
The bundle shipped real `.wav` files (footstep/typing/chair/coffee) — this project's own audio system is 100% synthesized at runtime and has a real smoke-test gate against third-party audio files (`"no third-party addons and no orphaned placeholder audio files ship with the project"`). Added 4 new `AudioSynth`-generated cues instead (`footstep`, `typing_click`, `chair_creak`, `coffee_pour`) to `data/sfx_cues.json`, triggered from real agent state: a footstep roughly every half-stride while walking, a typing click every ~0.3s while at a desk, a chair creak on sitting down, a coffee-machine sound on reaching the break spot. Per-agent cooldowns, not per-frame triggers — at the 150-agent stress scenario, firing a cue every physics tick per agent would be tens of thousands of calls/second for no audible gain.

## Deliberately not done this pass

- **Indoor/outdoor ambience crossfade** (the bundle's `AudioDirector`) — the existing adaptive music system (a persistent, always-on synthesized bed that crossfades calm/tense) already covers the room-tone role "ambience" is asking for; a second, separate crossfade layer was judged lower value than the action-tied SFX above, given the time this pass had.
- **Click-to-select / highlight system** — already flagged in `docs/production/KNOWN_ISSUES.md` from the prior masterpack audit; still a real gap, still out of scope for a behavior-focused pass.
- **A dedicated "drink" animation/pose** — no baked clip exists (see the prior pass's report); the coffee-machine visit still reuses "talk."
- **Full per-role task-type visual distinction at desks** (e.g. an engineer visibly "debugging" vs. a researcher "training") — the underlying `TaskManager` data model doesn't track per-role task flavor at the desk level; adding that is a mechanical-layer change bigger than this pass's scope, not just an animation swap.

## Verification

Every change was checked with real renders and/or dedicated smoke-test assertions, not assumed:
- 5 new `tests/smoke_test.gd` blocks (personality individuality, role bias via a 40-sample statistical check, needs-driven planner scoring, repeat-visit memory, stuck-recovery), all green.
- `tools/bootstrap.sh` run and green after every meaningful change (8 separate runs across this pass, not just once at the end).
- Real windowed renders: personality/needs printed from a live instance, the lounge-sit pose caught and screenshotted mid-animation, the live staff-panel status line screenshotted showing "Relaxing," and a final wide shot showing 4 agents in 4 different real states at once (two working at desks, one at the whiteboard, one sitting at the lounge) — `docs/visual-progress/serious_rework/`.
- `tools/export_release.sh` (Linux+Windows export + packaged-binary smoke) run clean before this commit.
