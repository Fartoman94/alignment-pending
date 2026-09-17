# Phase 03 — Interacciones

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_03_INTERACTIONS.md`. The bundle ships its own generic `Interactable`/`ObjectReservationService`/`NPCInteractionPlanner` templates (`08_GODOT_INTERACTIONS/`) — read and compared against what's already here before writing any code.

## Decision: keep the existing pipeline, don't adopt the bundle's generic framework

`StaffAgent` + `NavCoordinator` (point reservation) + `TaskManager` (desk task assignment) already implement the exact same conceptual flow the bundle's own `08_GODOT_INTERACTIONS/README.md`-equivalent flow describes (`recibe tarea → reserva objeto → pathfind → avoidance → align → animación contextual → usa objeto → libera reserva → nuevo estado`) and is already real, tested, and — as of Phase 1/2 this pass — verified against the exact same requirement list. Swapping to the bundle's generic `Interactable` class for the same observable behavior would be a large, risky rewrite under the project's own "no romper sistemas existentes" rule for no gameplay-visible gain. This is the same call the earlier `REAL_GAME_VISUAL_OVERHAUL` pass already made and documented (`docs/art/REAL_GAME_VISUAL_OVERHAUL_REPORT.md`, priority 4) — reaffirmed here, not re-litigated from scratch.

## Checklist, mapped to the real implementation

| Requirement | Real mechanism |
|---|---|
| Reservar escritorio | `TaskManager.assign()` binds a staff member to a specific desk building id |
| Reservar silla / puesto ambiente | `NavCoordinator.try_reserve(pos)` — one agent per point at a time, same mechanism for desks and the 3 ambient spots (break/whiteboard/lounge) |
| Llegar al UsePoint | `NavigationAgent3D` pathing, `StaffAgent._process_moving()` |
| Alinearse | Turn-to-face via `lerp_angle` toward the path direction (not a hard position/rotation snap to an exact "use point" transform like the bundle's `_align_and_use()` — the existing `ARRIVE_DISTANCE`/`target_desired_distance` tolerance is small enough that this hasn't been a visible problem in any render this session, but it's an honest difference worth naming) |
| Usar PC / sentarse (desk) | `State.WORKING` → `typing` animation (skeletal) / a rigid-leg "seated approximation" pose (flat-mesh, already documented as a geometry-fidelity trade-off) |
| Ir a coffee corner | `BREAK_SPOT`, tagged `"break"` → `talk` |
| Usar whiteboard | `WHITEBOARD_SPOT`, tagged `"whiteboard"` → `talk` |
| Sentarse (lounge) | **New this pass** (Phase 2) — `LOUNGE_SPOT`, tagged `"lounge"` → the real `sit` clip, verified live (see `phase-02-report.md`) |
| Liberar el puesto | `NavCoordinator.release()` (ambient spots, `_finish_move()`) / `TaskManager` unassign path (`StaffAgent.clear_work()`) — both already covered by existing smoke tests |

## Gap not fixed this pass

No dedicated coffee-machine "drink" animation exists (same gap `REAL_GAME_VISUAL_OVERHAUL_REPORT.md` already documented) — the break-room visit reuses `talk`. A real fix needs either a new baked clip (Blender, unavailable this session — see `phase-02-report.md`) or a procedural arm-to-mouth gesture layered on top of `talk`; not attempted this pass, flagged honestly rather than silently left looking like "sentarse/usa objeto" fully covers every object.

## Verification

No new code this phase beyond what Phase 2 already added and verified (`LOUNGE_SPOT`/`sit`). This report is an audit against the checklist, cross-referencing evidence already produced in `phase-02-report.md` and the prior `REAL_GAME_VISUAL_OVERHAUL_REPORT.md` rather than re-capturing duplicate screenshots.
