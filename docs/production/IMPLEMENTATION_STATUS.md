# Implementation status

Update this file after every prompt.

| Prompt | Status | Commit | Notes |
|---|---|---|---|
| P00 | DONE | (pending) | Godot 4.7.2 headless installed for CI. Fixed `smoke_test.gd` Variant-inference parse error (strict typing treats inference warning as error). Bootstrap + headless editor import both clean. No gameplay added. |
| P01 | DONE | (pending) | Added SceneRouter autoload (fade + error-safe ResourceLoader checks, busy-guard). Boot -> MainMenu -> Campaign flow; renamed main.tscn/main.gd to campaign.tscn/campaign.gd. Esc returns to menu from Campaign. Extended smoke_test.gd with scene-resolution, autoload-presence, and router-failure checks (moved autoload checks to `_initialize()`, since autoloads aren't attached yet during `_init()`). |
| P02 | DONE | (pending) | Added SettingsManager autoload (audio bus volumes, UI scale 80-160%, fullscreen/resolution, reduced motion, camera shake) persisted to `user://settings.cfg` with a version field and safe-default fallback on load failure. Added Music/SFX/UI audio buses (`default_bus_layout.tres`). Added Settings screen reachable from MainMenu with Apply/Reset/Back. Wired reduced_motion into SceneRouter fades and Campaign camera lerp (not just stored). Extended smoke_test.gd with clamping and save/load round-trip checks. |
| P03 | DONE | (pending) | Extracted camera into `CameraController` (class_name, own script): WASD + middle-drag pan, Q/E 90° rotation, wheel zoom, F focus-selected (currently resets to office origin; real entity focus deferred to prompts that add selectable entities), bounds-clamped pan. All motion uses exponential (frame-rate-independent) smoothing instead of the old `delta*constant` lerp. Campaign.gd now only owns pause/menu input and HUD. Added a runtime instantiation smoke check (loads main_menu/settings/campaign, adds to tree, processes a frame) catching errors plain existence checks miss. |
| P04 | DONE | (pending) | Added reusable `Hud` scene/script: anchor-driven top resource strip (cash/compute/power/trust/safety debt/date/pause/1x-2x-3x speed), bottom section nav (Build/Staff/Research/Models/Deployments/Company/World — placeholder-only, systems don't exist yet), left objectives panel, right contextual inspector wired to `EventBus.selection_changed`. Replaced campaign.gd's fixed-pixel-position HUD. Added a structural anchor check (not pixel-perfect) proving every strip is anchor-based so 1280x720/1920x1080 both work. Caught and fixed two bugs via the runtime instantiation smoke test: `Hud` class_name needed a fresh editor import pass before headless script runs could resolve it, and BottomBar's button paths were missing a `Margin` path segment. Fixed `tools/bootstrap.sh` to always do a headless editor import/rescan before running the smoke test, so this class-cache trap won't recur for future prompts. |
| P05 | DONE | (pending) | Rewrote SaveManager: 3 rotating autosaves + 3 manual slots under `user://saves/`, temp-file-then-atomic-rename writes validated before ever replacing the real file, SHA-256 checksum envelope (`{save_version, checksum, payload}`), and a migration registry keyed by GameState.SAVE_VERSION (explicit, currently v1, no migrations needed yet). `load_newest_autosave()` walks older rotating slots on checksum/parse failure. Wired real usage: periodic 60s autosave timer + autosave-on-exit in Campaign; MainMenu Continue now loads the newest autosave. Fixed a checksum bug caught by the round-trip test: JSON has no int/float distinction, so hashing pre-round-trip payload (with real ints) never matched the post-parse (all-float) payload on read — fixed by hashing a JSON-normalized copy at write time. |
| P06 | DONE | (pending) | Added `DataValidator` (static, not an autoload): validates JSON content datasets for duplicate IDs, missing required fields, and invalid numeric/enum ranges. Wired to `data/events_seed.json` (category must be one of the 12 documented categories, severity in P0-P3 = [0,3], 2-4 non-empty choices, non-empty title/body). Runs on Boot before routing to MainMenu, pushing one actionable `push_error` per issue; does not hard-block startup since these are content bugs, not corruption. IncidentDefinition fields owned by later systems (prerequisites, weight, cooldown_days, tags) intentionally not required yet. Closes Phase 0 (foundation). |
| P07 | DONE | (pending) | Added `SimClock` autoload: fixed-timestep calendar (day/hour/minute, `EventBus.day_advanced` on day rollover), gated on `active` (Campaign sets true/false on enter/`_exit_tree`) and `GameState.paused`, and named deterministic RNG streams (`rng(name)`/`pick_from(name, items)`) seeded from `(campaign_seed, stream_name)`. Fixed accumulator-based ticking makes calendar progression frame-rate independent (verified by splitting the same elapsed time into 1 vs 370 steps and comparing results). Added `GameState.calendar_day/hour/minute` (persisted) and `GameState.reset_to_defaults()` (randomizes seed, resets calendar/resources) called from MainMenu's New Campaign, which was previously not resetting state between sessions. Corrected HUD speed tiers from 1x/2x/3x (P04's placeholder) to the spec's 1x/2x/4x, and wired the real calendar into the HUD date label (closing a P04 TODO). Deterministic RNG test: same seed + same call sequence produces the same pick sequence. |
| P08 | DONE | (pending) | Added data-driven buildable catalog (`data/buildables.json`: desk/server_rack/safety_lab, cost, data-driven refund_ratio, footprint), `BuildGrid` (8x6 cell grid, occupancy, footprint/rotation math, a reserved mandatory-walkway row that placements can never block), and `BuildController` (ghost preview with green/red valid-invalid feedback, R rotates, click places/sells, re-validates against the authoritative grid even if the cached ghost state says valid). HUD's "Build" section now shows a real palette (one button per catalog entry + Sell + Cancel) instead of a placeholder. Removed the old hardcoded static desk/rack/chair/people scaffold from Campaign — the player now builds everything. Buildings persist in `GameState.buildings` and reload via `BuildController.load_from_state()` on campaign start (continues to survive save/load). Fixed two real bugs the tests caught: (1) DataValidator wrongly required `footprint.w/d` to be GDScript `int` — JSON parsing always yields float, so whole-number floats were being rejected; (2) statically typing test variables as `BuildGrid`/`BuildController` in smoke_test.gd forced Godot to eagerly compile build_controller.gd (which touches GameState) while loading the test script itself, before autoloads exist — fixed by loading those scripts dynamically via `load()` instead of bare class identifiers, same root-cause family as the P04 class-cache issue but at compile-time instead of scene-tree-time. |
| P09 | DONE | (pending) | Added `NavigationRegion3D` over the buildable floor (single static navmesh polygon; buildings get dynamic `NavigationObstacle3D` avoidance instead of navmesh re-baking, so build/sell never needs a bake step). Added `StaffAgent` (idle/moving state machine, `NavigationAgent3D` + RVO avoidance) and `NavCoordinator` (destination reservation: rejects a second agent claiming the same point, with a bounded retry-then-back-off escape hatch instead of blocking forever). Both gate on `GameState.paused`, including the async avoidance velocity callback (a real bug: movement could still land one frame after pausing if only the state-machine tick was gated). No roster/hiring yet (P10) — this prompt only delivers navigation infra, proven by an automated test that spawns 20 synthetic `StaffAgent`s, runs 900 physics ticks, and asserts every agent moved (no stuck/deadlocked agent) and that pausing halts all movement. Real in-game staff will reuse `StaffAgent`/`NavCoordinator` once P10 adds hiring. |
| P10 | DONE | (pending) | Added `data/staff_roles.json` (6 roles: researcher/engineer/data_ops/safety_analyst/product_manager/support_specialist) + `StaffRoleCatalog` loader + DataValidator rules. Added `StaffManager` autoload: deterministic candidate generation (fictional invented names, role, 5 skills, salary) via `SimClock`'s named RNG streams, hire/fire against `GameState.staff` (stable `staff_N` ids from `GameState.next_staff_id`), and daily payroll deducted on `EventBus.day_advanced`. HUD's "Staff" section now shows the real roster + candidate pool with Hire/Fire/Inspect (inspect shows role/salary/morale/fatigue/skills). Campaign spawns/despawns a real `StaffAgent` (from P09's navigation infra) per roster change via a new `EventBus.staff_roster_changed` signal, so hired staff actually walk the office. `values`/`relationships`/`traits`/`assigned_task` are present per DATA_SCHEMA.md but left empty — deep staff modeling (P24) and task assignment (P11) own those. |
| P11 | TODO | | |
| P12 | TODO | | |
| P13 | TODO | | |
| P14 | TODO | | |
| P15 | TODO | | |
| P16 | TODO | | |
| P17 | TODO | | |
| P18 | TODO | | |
| P19 | TODO | | |
| P20 | TODO | | |
| P21 | TODO | | |
| P22 | TODO | | |
| P23 | TODO | | |
| P24 | TODO | | |
| P25 | TODO | | |
| P26 | TODO | | |
| P27 | TODO | | |
| P28 | TODO | | |
| P29 | TODO | | |
| P30 | TODO | | |
| P31 | TODO | | |
| P32 | TODO | | |
| P33 | TODO | | |
| P34 | TODO | | |
| P35 | TODO | | |
| P36 | TODO | | |
| P37 | TODO | | |
| P38 | TODO | | |
| P39 | TODO | | |
| P40 | TODO | | |
| P41 | TODO | | |
| P42 | TODO | | |
| P43 | TODO | | |
| P44 | TODO | | |
| P45 | TODO | | |
| P46 | TODO | | |
| P47 | TODO | | |
