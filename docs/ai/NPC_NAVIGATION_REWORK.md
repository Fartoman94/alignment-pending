# NPC navigation report

Response to `ALIGNMENT_PENDING_WORLD_AND_NPC_OVERHAUL`'s prompt 02 (choques, giros de más, agrupamiento, wandering sin lógica). Audited the brief's own `NAVIGATION_SPEC.md`/`NPC_ROLE_SPEC.md` requirements against the real, already-shipped `StaffAgent`/`TaskManager`/`NavCoordinator` system before writing any new code — most of what this prompt asks for was already real and tested from earlier passes this session, not net-new.

## Already real, cross-checked against the spec, not re-built

- **`NavigationAgent3D` per NPC + avoidance enabled** — `StaffAgent._ready()`, unchanged this pass.
- **No random wandering** — the garage-recovery pass earlier this session gave the 3 starting hires real `research_sprint` work orders at real desks; most of a campaign's staff spend most of their time on an actual assigned task, not wandering. Idle staff (nobody's actively working, or between tasks) use the production-kit pass's tagged-destination system (below) instead of a uniform-random point.
- **Workstation reservation, no two NPCs sharing one desk** — `TaskManager.is_building_reserved()`/`can_assign()` (pre-existing) plus `NavCoordinator.try_reserve()`/`release()` for the ambient-destination system (below) — both exercised by real behavioral tests, not just read.
- **Legible dwell time** — `research_sprint` runs 240 simulated minutes; the seated/typing `WORKING` pose (an earlier pass) holds for that whole duration.
- **Facing the direction of travel** — fixed earlier this session (`fix(world): staff agents turn to face their walk direction`), unrelated to this package but the same underlying complaint ("giran de más" reads a lot like the pre-fix symptom: a character that never turns to face where it's walking looks like it's spinning/sliding).

## What this pass added

`StaffAgent`'s single-destination "break spot" (a production-kit-pass addition) generalized to `ambient_destinations: Array[Vector3]` — a small set of tagged real destinations an idle agent has a 30% chance to head for instead of a random point, picking one at random from the set rather than always the same one. Garage-tier staff now get two: the existing break-room corner, and a new point in front of the garage's planning whiteboard (`WHITEBOARD_SPOT`), closing the checklist's "van a coffee point / meeting / whiteboard según tarea" item — partially: **not** role/task-routed (an engineer and an HR partner have the same 30% chance to wander to either spot), a real, named scope limitation, not silently dropped.

Verified behaviorally, not just by code review: a scripted real-campaign run (3 real hired staff, real physics ticks) confirms an agent reaches both the break spot (0.26 units) and the whiteboard spot (0.99 units, at `ARRIVE_DISTANCE`) during ordinary idle wandering.

## Deliberately not built: the brief's full NPC FSM

The brief's own `NPCStateMachine.gd`/`RoleBrain.gd`/`Workstation.gd`/`WorkstationRegistry.gd` templates sketch a much larger system — per-role activity tables (`npc_roles_overhaul.json`), a daily schedule of time-blocked activities (`npc_daily_routines.json`), typed workstations with role tags and seat points (`workstations.json`). Not adopted verbatim, for the same reason the identical ask from the garage-recovery package was declined earlier this session: it would duplicate what `TaskManager`'s real work-order/reservation system and `StaffAgent`'s real state machine already do, with a second, parallel, less-integrated system. The P0 navigation/behavior checklist items this prompt actually gates on (no random wandering, real workstations, reservations, legible dwell time, no collisions) are satisfied by the existing system plus this pass's small addition — a full role-routed daily-schedule simulation is real, additional scope beyond what's needed to clear that gate, not attempted.

## Not attempted this pass

- **Role-specific ambient destination routing** (manager → whiteboard more often, support → talk point, etc.) — the `ambient_destinations` list is uniform per agent regardless of role; a role-weighted pick would be a small, real follow-up on top of this pass's mechanism, not a rewrite.
- **Navigation obstacles for the new density-pass furniture** (desks/chairs/monitors from the garage recovery pass) — these are decorative, not registered with `NavigationObstacle3D` the way real `BuildController`-placed buildings are (`_add_obstacle()`). Not confirmed as a real visible problem (agents path to/through the desk cluster via `assign_work()`'s exact target point, not through the furniture) but not specifically stress-tested either — flagged, not verified clean.
