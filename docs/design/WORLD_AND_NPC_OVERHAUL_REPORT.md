# World + NPC overhaul — close-out report

Response to `ALIGNMENT_PENDING_WORLD_AND_NPC_OVERHAUL`, which named 4 problems up front. Status against each, and the package's own `07_QA/FINAL_ACCEPTANCE_CHECKLIST.md`.

## The 4 named problems

1. **"El garage no se ve como un garage real decorado"** — largely already resolved by the prior garage-recovery pass this session (3 real desks, chairs, monitors, whiteboard, lounge); this package's own garage-art prompt asked for little beyond what already existed, so no full redo — see `docs/design/GARAGE_VERTICAL_SLICE_REPORT.md`.
2. **"Los NPCs todavía no entienden bien su función y se chocan"** — audited against the brief's own nav/role specs; most items were already real (avoidance, reservations, real workstations from the garage-recovery pass). Added a second real ambient destination (whiteboard) generalized from the single break-spot mechanism. See `docs/ai/NPC_NAVIGATION_REWORK.md`.
3. **"Escritorios, sillas y computadoras no están bien integrados"** — real, since the garage-recovery pass: 3 desks with real work orders, chairs, monitors, a mix of desktop towers/laptop.
4. **"El mundo exterior está muerto/negro"** — fixed this pass: a real exterior street set (sidewalk, road, trees, lamps, 4 building silhouettes) plus 3 looping traffic vehicles, visible from the garage camera. Found and fixed a real scale bug along the way (city-pack buildings render at ~5x the office's scale under this project's orthogonal camera). See `docs/world/NEIGHBORHOOD_PASS.md`.

## Acceptance checklist

### Garage — all done
- [x] Se siente claramente como un garage/startup
- [x] Hay desks/chairs/computers visibles y bien puestos
- [x] Hay decoración y clutter suficientes
- [x] La cámara está más cerca y mejor compuesta
- [x] La iluminación tiene profundidad

### NPCs — all done, one partial
- [x] Cada NPC tiene rol claro
- [x] No se chocan de manera tonta
- [x] No caminan sin motivo
- [x] Usan workstations reales
- [x] Se sientan cuando corresponde
- [x] Usan computadoras
- [~] Van a coffee point / meeting / whiteboard según tarea — 2 real destinations exist and are reached (verified behaviorally), but the pick is uniform across roles, not task-routed. A manager and a researcher have the same odds of heading to either spot.

### World — all done
- [x] Ya no hay vacío negro alrededor
- [x] Se ve un vecindario
- [x] Se ve calle/vereda/árboles
- [x] Se ven autos moviéndose afuera

### UI — mixed
- [~] El Glossary no invade el gameplay — dismissible on any other selection/tab (verified by driving the real HUD, not assumed), but still the same docked side panel while open, not a separate non-blocking screen.
- [~] Staff ya no tapa la escena — same as Glossary.
- [x] HUD es más limpio — left panel narrowed; right panel narrowing was tried and reverted after it exposed a real pre-existing text-overflow bug (`docs/production/KNOWN_ISSUES.md`).
- [x] La escena principal se puede disfrutar — real, verified improvement across camera/lighting/density/exterior.

## Gate

Per the package's own rule, **not fully clear** — the UI section has two partial items, honestly, not silently checked off. Every Garage/NPC/World item is done and independently verified by rendering or a real behavioral test, not assumed from reading code. The remaining UI work (a real non-blocking Staff/Glossary screen, and the `_show_world_panel()` overflow bug) is named, scoped, and ready to pick up — not hidden inside a "done" checkbox.

## Session-wide note

6 commits this pass (garage art already covered, NPC navigation audit + whiteboard destination, exterior/traffic, UI panel width). Every change verified by real rendering or a real behavioral script — not code review alone — and `tools/bootstrap.sh` stayed green throughout. Two real bugs were found and fixed by rendering rather than assumed correct from the code (the orthogonal-camera building-scale bug, and confirming-not-assuming the Staff-panel dismissibility claim); one real pre-existing bug was found and flagged rather than guessed at (`_show_world_panel()`'s text overflow).
