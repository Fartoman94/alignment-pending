# Phase 05 — Barrio y tráfico

Response to `ALIGNMENT_PENDING_CLAUDE_VISUAL_EXECUTION_MASTERPACK`'s `PHASE_05_NEIGHBORHOOD.md`. Most of this was already real, from the prior `REAL_GAME_VISUAL_OVERHAUL` pass and before — `Campaign._build_exterior()` already builds a 3-lane road, sidewalk, trees, lamp posts, a park bench, and background buildings, with 3 moving traffic vehicles each on their own dedicated lane (no shared-line collisions by construction).

## Checklist

| Item | Status |
|---|---|
| Calle doble carril | Already done (3 lanes, exceeds the ask) |
| Veredas | Already done |
| Árboles | Already done |
| Farolas | Already done |
| Fachadas / edificios de fondo | Already done |
| Autos/van en movimiento | Already done — 3 vehicles, separate `Path3D`-equivalent straight-line lanes (a deliberately simple ping-pong mover per `TrafficVehicle`'s own doc comment — a full traffic simulation was explicitly ruled out by an earlier brief) |
| **Autos estacionados** | **Missing → fixed this phase** |
| Carriles separados | Already done |
| No atravesarse | Already done by construction (one vehicle per lane) |

## Fix: parked cars

No static parked cars existed — only the 3 moving lane vehicles. The pack ships no dedicated "parked car" model, so this reuses the same `car_blue.glb`/`car_orange.glb` meshes the moving lanes already use, placed once as static exterior set dressing (not a `TrafficVehicle`) along the far curb, past the traffic lanes and in front of the background buildings.

## Verification

Real windowed render, camera pulled back to frame the whole street (`phase-05-exterior-after.png`) — shows the road with lane markings, both moving traffic (mid-transit) and the new static parked car, sidewalk, trees, lamp post, and background buildings all in frame together, no empty black void. `tools/bootstrap.sh` full smoke suite — green.
