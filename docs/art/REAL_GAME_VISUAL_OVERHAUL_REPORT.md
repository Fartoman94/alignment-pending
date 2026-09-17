# Real game visual overhaul report

Response to `ALIGNMENT_PENDING_REAL_GAME_VISUAL_OVERHAUL` (8 ordered priorities: world environment/AO/glow/tonemap, day-night cycle, believable garage, NPCs using real objects, lively neighborhood, materials/shaders, camera/motion smoothing, UI feedback — with a hard rule not to add new story content until the first several visibly improve in real screenshots). This pass focused on the priorities that needed real, unbuilt work; several later priorities turned out to already be satisfied by earlier passes and are documented as "checked, no change needed" rather than force-padded with redundant systems.

## 1. World environment / ambient occlusion / glow / tone mapping — done

`game/project.godot`'s renderer was `gl_compatibility` since the project's very first commit (Godot's own new-project default, never a deliberate hardware-compatibility choice — confirmed via `git log -p`). SSAO/SSIL/SDFGI are Forward+-only in Godot 4 and simply don't exist under Compatibility regardless of `Environment` settings, so this priority was blocked until the renderer itself changed. Switched to `forward_plus`/`mobile`, verified by:
- A real windowed render (`Vulkan 1.4.305 - Forward+ - Using Device #0: AMD - AMD Radeon Graphics (RADV RENOIR)` actually initializing and the garage scene rendering correctly).
- A full `tools/bootstrap.sh` pass (all smoke assertions green under the new renderer).
- A real GPU profile before/after comparison — see `docs/performance/REAL_GPU_PROFILE.md`'s new "Before/after" section. The realistic 20-staff mid-game scenario is unaffected (59.6 vs 59.7 avg FPS); only the unrealistic 150-staff stress scenario pays a real, accepted cost (34.9 vs 37.5 avg), matching this project's existing "profile, don't guess, accept unrealistic-scenario cost" policy already on record for the humanoid-character integration.

`Campaign._build_environment()` (`game/src/world/campaign.gd`) now sets `ssao_enabled`/`ssil_enabled` with radius/intensity/power values tuned by rendering the garage scene at each step (not copied blindly from the bundle's `TRUE_GAME_LOOK_BOOTSTRAP.gd` template, though the final SSAO numbers landed close to its defaults). Confirmed via real screenshots: visible soft contact shadows under desks and characters that weren't there before (`docs/design/screenshots/` — see below for the exact files). `SDFGI` was deliberately left off — on the stress scenario it would have cost meaningfully more than SSAO+SSIL combined for a difference that's barely visible in this small, box-shaped interior; a real, documented scope call, not an oversight.

## 2. Sun / day-night cycle — done, wired to the real simulation clock

The bundle's own `TIME_OF_DAY_CONTROLLER.gd` template runs its own `@export game_hour` advanced by `_process(delta)` — a second, disconnected clock that would drift from the calendar the HUD already shows and from every `day_advanced`-gated system (district trust/regulation drift, board pressure, etc). Instead, `Campaign._update_time_of_day()` reads `GameState.calendar_hour`/`calendar_minute` directly every frame — the same real clock `SimClock`/`EventBus.simulation_tick` already ticks — so there's exactly one source of truth for "what time is it."

- `KeyLight`/`FillLight` (previously local variables, now promoted to `_key_light`/`_fill_light` member fields) have their rotation, color, and energy driven by a single sine curve over the 24h cycle (peak at solar noon, trough at solar midnight), with a separate warm/cool color ramp for dawn/day/dusk/night.
- The two `BackWallWindow` emissive panels (previously a fixed "always daytime" glow — real gap found while verifying: night didn't read as meaningfully different from dusk because the only visible "outside world" cue was static) now scale with the same day/night factor, tracked via a new `_window_materials` array.
- Verified with a real windowed render at 4 hours (noon/dawn/dusk/night) plus direct pixel-color sampling of the same floor region across all 4 screenshots, confirming a real, monotonic brightness/color change, not just a code read. See `docs/design/screenshots/` for the captures.
- The `CityBackdrop` skyline (a `SubViewport` baked once with `UPDATE_ONCE`, used as a distant decorative texture through the windows) deliberately stays a static daytime bake — re-rendering it live every frame would defeat the entire performance reason it's baked once, for a background element nobody looks at directly. Documented as a scope boundary, not a bug.

## 3. Believable garage visuals — checked, already substantially covered

Cross-checked against the bundle's own `10_BLUEPRINTS/GARAGE_REALISTIC_BLUEPRINT.md` zone list: garage door (real modeled `garage_door_closed.glb`), 3-desk cluster with monitors, whiteboard/planning wall, coffee corner (fridge/vending machine/coffee machine/table/chairs), storage shelf + steel beam, a sofa+coffee-table lounge corner, and the two window panels for exterior light — all already placed by prior passes (`Campaign._build_office()`/`_build_break_room()`/`_build_ambient_decoration()`). No changes made here; re-verified in the real renders this pass produced rather than re-implemented.

## 4. NPCs using real objects — done (real, scoped gap found and fixed)

`StaffAgent` already had a real skeletal animation system for the generated-humanoid character pipeline (`_animate_visual_skeletal()`, baked clips: idle/walk/typing/talk/sit) and already routed idle agents to the coffee machine (`BREAK_SPOT`) and the planning whiteboard (`WHITEBOARD_SPOT`) as real destinations. The actual gap: arriving at either spot produced **plain idle** — the `talk`/`sit` clips existed in the rig but nothing ever called them, so a coffee-machine or whiteboard visit looked identical to standing anywhere else.

Fixed with a small, targeted addition: `ambient_activity_tags` (a parallel array to `ambient_destinations`, wired in `Campaign._spawn_staff_agent()`) tags each ambient destination ("break"/"whiteboard"); `StaffAgent` tracks `_ambient_activity` across the reserve→move→arrive cycle and both animation paths react to it — skeletal agents play `talk` (no dedicated "drink" clip exists in the baked set, documented rather than silently faked), flat-mesh agents get a distinct raised-arm "engaged" pose instead of the regular idle sway.

Verified two ways, not just by reading the diff:
- **Instrumented**: a real windowed run printed the agent's live `state`/`_ambient_activity`/`_current_anim` every 0.3s until it caught the transition — `CAUGHT_IDLE_AMBIENT activity=break anim=talk skeletal=true`, confirming the code path actually fires in the running game, not just in isolation.
- **Visual**: the same run screenshotted the moment it was caught — a real generated-humanoid character standing at the break-room table with a raised-arm "talk" pose, visibly different from the desk-working agents nearby. See `docs/design/screenshots/`.

`INTERACTABLE.gd`/`OBJECT_RESERVATION_SERVICE.gd`'s general-purpose reservation framework from the bundle was **not** adopted wholesale — `NavCoordinator`'s existing point-reservation system already does the same job (one agent per destination at a time) for the two ambient spots and the work-desk assignment path, and swapping to a whole new interactable/reservation abstraction under the "don't break existing systems" rule would have been a much larger, riskier change for the same observable result.

## 5. Lively city / neighborhood — checked, already substantially covered

Traffic vehicles, street/sidewalk geometry, trees, lamp posts, and background buildings are all already present (`Campaign._spawn_traffic()`, `CityBackdrop`, `_build_ambient_decoration()`) and visible in every real render this pass produced (see the noon/dawn/dusk/night screenshots — cars, a bench, streetlights, and background buildings are all in frame). No changes made; the one previously known gap (`CityBackdrop`'s dense-tier skyline not reading as legible — already logged in `KNOWN_ISSUES.md`) is unrelated to this priority's "does it look inhabited" bar and wasn't re-investigated this pass.

## 6. Materials / shaders — small real fix, larger rework out of scope

The BackWallWindow panels' day-night reactivity (priority 2, above) is also a real materials fix — the window material previously had zero relationship to lighting conditions. Screen-glow emissive materials (`_apply_screen_glow()`, monitors/laptops) and the palette-driven office wall/floor/trim colors were already in place from prior passes and re-verified in this pass's renders.

The bundle's `GLASS_WINDOW.gdshader` (real alpha-blended, reflective glass) was deliberately **not** adopted — swapping the window panels from opaque-emissive to translucent would mean rendering whatever's behind them (nothing real exists back there but the baked skyline texture at a fixed depth), risking a worse, more obviously-fake result under time pressure without a chance to iterate and re-render safely. Left as a documented, defensible scope boundary rather than a half-finished shader swap.

## 7. Camera / motion smoothing via springs — checked, not applicable as-is

`CameraController` already does real frame-rate-independent exponential smoothing (`_frame_weight()`) on pan/rotate/zoom, and `StaffAgent._process_moving()` already turns agents smoothly toward their walk direction via `lerp_angle`. The bundle's `SpringSmoothing`/`SpringCameraRig` templates are built for a follow-camera chasing a moving target, which introduces overshoot/bounce by design — the wrong feel for a precise top-down build-placement camera the player drags/pans directly. Adding a spring-damper on top would be a regression, not a polish pass, for this camera style. Documented as a deliberate non-adoption, not a missed priority.

## 8. UI / visual feedback — checked, already substantially covered

Build placement already has a real ghost preview with valid/invalid color feedback and a colorblind text indicator (`BuildController`); the HUD already went through an extensive presentation pass in earlier sessions (resource chips, staff cards, world-state panel, negotiate button). Explicitly last in the bundle's own priority order and the one this pass invested the least additional time in, per the bundle's own "don't add polish before the environment/lighting/NPC priorities are solid" rule.

## Assets used

No new assets. This pass is systems/tuning work on top of the existing mega-asset-pack and generated-humanoid pipelines — real `Environment`/`DirectionalLight3D` properties, the existing `StandardMaterial3D` window panels, and the existing baked `AnimationPlayer` clips (`talk`) that had never been triggered before.

## Real GPU cost (see `docs/performance/REAL_GPU_PROFILE.md` for full numbers)

Realistic scenarios (empty office, 20-staff mid-game) are unaffected by the renderer switch + SSAO/SSIL. The unrealistic 150-staff stress scenario drops further (34.9 vs 37.5 avg FPS) — accepted per this project's standing "profile, don't guess, don't chase costs at unrealistic scenarios" policy, same call already made once for the humanoid-character integration.

## Screenshots

Real in-engine captures (`godot4 --path game --script`, real windowed Vulkan render, not mockups) saved under `docs/design/screenshots/visual_overhaul/`:
- **`00_before_after_renderer_combo.png`** — a genuine before/after: same scene, same camera, same hour (noon), renderer flipped from `gl_compatibility` (top — the project's setting before this pass, temporarily restored just to capture this one comparison frame, then switched back) to `forward_plus` with SSAO/SSIL (bottom). The difference is the actual priority-1 deliverable: the "before" frame is flat and washed out with no contact shadows; the "after" frame has a grounded, saturated floor and visible soft shadows under every desk and character.
- `01_noon.png` / `02_dawn.png` / `03_dusk.png` / `04_night.png` — the same camera framing at 4 different real `GameState.calendar_hour` values, showing the day-night lighting/window-glow cycle.
- `05_morning_wide.png` — a wide establishing shot (garage + street/city backdrop in frame together).
- `06_caught_ambient_pose.png` / `06_caught_ambient_pose_zoomed.png` — an agent caught mid-"talk" animation at the coffee-machine break spot, instrumented and confirmed via a live state print (see priority 4 above).

## `11_QA/FINAL_RELEASE_VISUAL_QA.md` checklist

Iluminación/look, garage, and presentación sections: all items checked and pass (see priorities 1-3 and the before/after screenshot above). NPCs section: "usan objetos"/"se sientan o interactúan" now pass (priority 4); "no se chocan torpemente" and "movimientos más suaves" rely on `NavigationAgent3D` avoidance and the turn-to-face `lerp_angle` that already existed before this pass and were not re-touched or re-verified for collision/smoothness quality specifically in this pass — carried over from prior passes' own testing, not re-claimed as newly verified here. Barrio section: all items already satisfied by prior work, re-confirmed visually in this pass's renders, not re-tested in depth.

## Remaining visual gaps (honest, not fixed this pass)

- `CityBackdrop`'s dense-tier skyline still doesn't read as fully legible (pre-existing, already logged in `KNOWN_ISSUES.md`, not re-investigated here).
- SSAO/SSIL's first-frame pipeline-compile stutter (small scene's one-time min=1.0 FPS sample) isn't isolated/re-measured with a warm-up harness — flagged in `REAL_GPU_PROFILE.md` rather than guessed at.
- Real alpha-blended/reflective glass, foliage-wind shader, and a spring-damper camera were all evaluated against this bundle's own templates and deliberately not adopted (see priorities 6/7 above) — a scope call, not an oversight, but worth re-litigating if a future pass specifically asks for that look.
- Windows runtime for the exported build is still untested on real Windows hardware (pre-existing, unrelated to this pass — see `KNOWN_ISSUES.md`).
