# Neighborhood pass report

Response to `ALIGNMENT_PENDING_WORLD_AND_NPC_OVERHAUL`'s prompt 04, whose brief opens: *"El alrededor del garage no puede ser negro vacío."* Confirmed via a real screenshot of the actual running build before touching code — the room only ever built 2 of its 4 walls (`BackWall`/`LeftWall`; the other two sides were always open by design, so the isometric camera could see in), and past those open sides — or over the low walls' top edge — there was nothing but the flat `WorldEnvironment` background color.

## Scope, per the brief's own boundary

*"No hace falta mundo abierto... debe ser un 'set' exterior convincente visto desde la cámara del garage."* Not a spatial/explorable neighborhood — `Campaign._build_exterior()` places a fixed street "set" (sidewalk, street with lane markings, trees, lamp posts, a park bench, 4 building silhouettes across the street) just past the floor's own edge, plus 3 vehicles on a simple back-and-forth loop. Nothing here is walkable or interactive; it exists to be looked at from the garage camera, matching the same "decorative, low-cost" scope the earlier `CityBackdrop` window pass already established for this project.

## A real scale bug, found and fixed by rendering

The city asset pack's building-exterior models (`hq_building_exterior.glb`, `mid_building_exterior.glb`, `small_building_exterior.glb`, `tower.glb`) are authored at a dramatically larger scale than every other model this project's mega asset pack uses — confirmed by pulling a real perspective camera back far enough to compare a building side by side with the office box: unscaled, a single building dwarfed the entire room, looming into the play space instead of reading as "down the street."

This project's camera is **orthogonal** (no perspective), which matters here specifically: with a normal 3D camera, pushing an object further away shrinks it on screen for free. With an orthogonal camera, world position along the view axis does nothing to apparent size — an object 20 units away renders at the exact same screen size as one 5 units away. Distance alone couldn't fix this; the buildings needed an explicit scale-down (`_ext_model()`'s new `model_scale` parameter, `0.22` for all 4), verified by re-rendering the same perspective comparison until the buildings read as a believable few-story block rather than a skyscraper crowding the sidewalk.

## Traffic

`TrafficVehicle` (`game/src/world/traffic_vehicle.gd`): a deliberately simple straight-line ping-pong mover between two authored points, reversing on arrival — not a traffic simulation (the brief rules that out explicitly: *"no hace falta tránsito complejo de simulación"*). Faces its direction of travel (confirmed the model's authored front is local +X, not the +Z convention every character/prop elsewhere in this project uses — checked by rendering from 4 cardinal angles first, not assumed to match). 3 vehicles (`car_blue`, `car_orange`, `delivery_van`), staggered start positions and speeds (2.1-3.4 units/sec) so they don't move in lockstep.

## Performance

Real GPU profile (`docs/performance/REAL_GPU_PROFILE.md`'s "world+NPC overhaul pass" section): no meaningful regression across all three scenarios. This is the first pass this session with genuine *per-frame* cost (3 vehicles moving every physics tick, versus every prior pass's one-time set dressing) and it's still within normal run-to-run noise — a straight-line mover with no pathfinding or avoidance is cheap by construction.

## Verified

Through the real campaign scene at the actual default camera framing (not a synthetic close-up alone) — the exterior is now visible at the edges of the default view where the void used to be, and a dedicated wider shot confirms the full street set (trees, lamp posts, moving cars, building silhouettes) reads correctly at the corrected scale.

## Not attempted this pass

- Exterior lighting variation ("pequeños cambios de iluminación exterior" — the brief's own phrasing, itself modest) — the exterior currently uses the same lighting as the interior scene; no separate exterior-specific lighting pass.
- Scaling the exterior set to react to real-estate tier (premium/HQ offices) — this pass is fixed geometry regardless of tier, matching the garage-focused scope the whole `WORLD_AND_NPC_OVERHAUL` package states up front.

## Follow-up: lane separation (`ALIGNMENT_PENDING_TOTAL_VISUAL_AND_SYSTEM_REWORK`'s prompt 05)

The original 3-vehicle setup above shared one line (z=10) across both travel directions — functional (no crash, no visible bug in a quick look) but not actually collision-safe: two `TrafficVehicle`s ping-ponging the same bounded line will eventually pass through each other regardless of their starting directions, since it's the same 1D path traversed forever, not a one-shot crossing. The newer total-rework package named this directly ("Path3D por carril, dirección separada... sin colisiones absurdas"). Fixed: 3 separate parallel lane lines (z=9.3/10.5/11.7), one vehicle each, so no two vehicles can ever occupy the same line by construction — verified with a real top-down render showing clear separation between all three, not just reasoned about. Lanes 1 and 3 run the same direction, lane 2 the opposite way, so both travel directions are represented as the brief also asks.
