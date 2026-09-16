# NPC visual rework report

Response to `34-ALIGNMENT-PENDING-REDISEÑO-NPCS.md`. Scope constraint from the brief itself: **"NO cambiar el gameplay"** — every change here is presentation/animation on top of the existing `StaffAgent` state machine (`game/src/world/staff_agent.gd`), never a new gameplay state, save field, or data schema. Gated on `tools/bootstrap.sh` staying green (§17) and on real, non-headless rendering — both the dev validation scene and the actual campaign scene through the real game camera — not just source review, per this project's own recurring lesson (see `docs/release/FINAL_RC_AUDIT.md`).

## Honest scope boundary, stated up front

The brief's §3 ("P0 — proporciones") and parts of §6/§9 ask to *remodel* the character meshes: new body proportions, new hairstyles, swappable clothing pieces, glasses/beard/helmet accessory meshes. **This environment has no 3D modeling tool** — the character geometry is the finalization pack's authored `.glb` files (`game/assets/models/characters/*.glb`), and nothing here can add new geometry to them. That was true of the prior 3D-asset-integration pass too and is unchanged.

What *is* real and shipped in this pass, entirely in code:
- A per-instance material variation system (skin tone, hair color) so same-role NPCs aren't visual clones (§6).
- Improved idle animation (head-turn/weight-shift, subtle arm sway) instead of a static bob (§7 "Idle").
- An approximated seated pose for the `WORKING` state, checked against real desk/chair models (§7 "Sit", §8, §12).
- A validation scene exercising the real `StaffAgent` code path across all 10 roster roles (§14).
- Scale/lighting/camera-legibility verification via real rendering, both in the validation scene and the actual campaign scene (§8, §10, §11).

What's **not** done, and why:
- **Clothing/accessory swaps, glasses, beards, helmets** (§6, §5's "gafas opcionales" / "casco o accesorio distintivo"): the pack ships one fixed mesh per role with baked-in accessories (or none) — there's no separate glasses/helmet mesh to toggle on or off. Adding one means authoring new geometry, which needs a 3D tool this environment doesn't have.
- **"Talk" animation** (§7): the `StaffAgent` state machine has exactly three states — `IDLE`, `MOVING`, `WORKING` — and none of them represents "in conversation." Adding a fourth state, and something to trigger it (two NPCs recognizing proximity and starting a "talk" interaction), is a gameplay/state-machine change, which the brief's own first line rules out for this task. Not attempted.
- **New body proportions** (§3): confirmed via the same renders documented below that the pack's existing proportions (stylized low-poly, head noticeably larger than anatomically real, simple blocky limbs) already match the brief's own "Recomendación visual" almost exactly — this was authored to spec by the pack, not something this pass needed to fix. See "Proportions assessment" below.
- **`ceo`/`cfo`/`hr`/`legal` roles have no `StaffRoleCatalog` entry** — same gap the prior two passes already documented (`docs/art/VISUAL_OVERHAUL_REPORT.md`, `docs/legal/ASSET_PROVENANCE.md`): no board/legal/HR gameplay system exists yet to spawn them into. Their `.glb` files are validated and shown in `npc_showcase.tscn` (bypassing the catalog on purpose, see below) but don't appear in real campaign gameplay.

## Problems found (confirmed by rendering, not just reading the code)

Re-checking the brief's own problem list (§0) against the state left by the prior 3D-asset-integration + visual-overhaul passes:

- **"se sienten como muñecos de prueba"** — largely already addressed by the earlier pack integration (real geometry replaced procedural capsules), but every NPC of the same role was a literal visual clone (identical skin tone, identical hair color, identical everything) — confirmed by spawning the same role twice in a throwaway script and rendering both: pixel-identical. That's the concrete form "poca personalidad general" and "se sienten como muñecos" took here.
- **"piernas y brazos rígidos" / poor idle** — the existing idle animation was a single vertical bob with zero variation between "just started idling" and "about to walk" — no head-turn, no weight shift, exactly what §7's "Idle" section calls out as missing.
- **No "sit" pose** — `WORKING` reused the same standing bob as `IDLE`, just faster and smaller, with an arm raised — an NPC parked at a desk stood upright next to their chair rather than looking seated.
- Role differentiation, scale, and background-blending were **re-verified, not broken**: the earlier pack-integration pass already gives each role a distinct `.glb` with its own clothing/color (safety = teal vest, researcher = white labcoat, engineer = light blue, manager = charcoal suit + tie, etc.), and the visual-overhaul pass's two-light setup already prevents anyone from disappearing into the background. Confirmed again this pass via real gameplay renders — see "Tested" below — rather than assumed unchanged.

## Changes made

### Per-instance material variation (`game/src/world/staff_agent.gd::_apply_variation()`)

Called once at the end of `_build_visual()`, after the model's parts are already reparented into `_bob_group`. Two things vary:
- **Skin tone**: the head's existing skin material is duplicated (never mutated in place — `load()` caches by `res://` path, so every agent of the same role shares the same `Mesh`/`Material` *resource*; mutating it directly would restyle every other agent of that role too, not just this one — this was the exact class of bug the earlier pack-integration pass had already learned to avoid for role colors). A random shift (±0.08, scaled down slightly on green/blue) is applied to `albedo_color`, then set via `set_surface_override_material()` — safe per-instance, the shared `Mesh` resource is never touched.
- **Hair color**: same duplicate-and-override pattern, picked from an 8-color palette (`HAIR_COLORS`) spanning dark/light, warm/cool tones — not a random RGB roll, which would produce implausible hair colors.

Deliberately **not** varied: clothing/vest/labcoat color, which stays the role's own baked color — that's the actual role-legibility signal §4/§5 ask to preserve ("Cada rol debe ser identificable por... color principal"), and randomizing it would undermine exactly the thing those sections require.

### Idle animation (`_animate_visual()`, `State.IDLE` branch)

Before: `_bob_group.position.z = sin(idle_t) * 0.015` and nothing else — a single vertical bob, identical every idle cycle.

After, per §7's "Idle" checklist:
- Same vertical bob (breathing-equivalent), kept.
- **Weight shift / "mirar alrededor"**: `_bob_group.rotation.y = sin(idle_t * 0.35) * 0.12` — a slow ±7° yaw of the torso+head group. There's no separate neck joint in the geometry to turn just the head, so a whole-body yaw stands in for it; at isometric distance this reads as "looking around" without the character's feet moving, which is what a stationary weight-shift actually looks like.
- **Subtle arm sway**: `_arm_l_pivot`/`_arm_r_pivot` get a small (±0.04 rad), phase-offset sine drift instead of staying frozen at zero — prevents the "mannequin" stiffness the brief calls out.

### Seated pose (`_animate_visual()`, `State.WORKING` branch)

Before: legs at `rotation.x = 0.0` (i.e., standing) while the character stood at the workstation with one arm raised.

After: `_leg_l_pivot.rotation.x = 1.15` and `_leg_r_pivot.rotation.x = 1.15` (both legs rotated ~66° forward from the hip), plus `_bob_group.position.z` lowered by `0.22` to bring the torso down to chair height. This is an **approximation, not a real sit** — the leg is a single rigid segment with no knee joint, so the lower leg can't bend back down to the floor the way an actual seated pose would; the whole leg just angles forward. Verified by rendering three agents seated at real `desk_single.glb` + `office_chair.glb` models (see screenshots below) — at the game's isometric camera distance it reads convincingly as "seated at the desk," which is what §12's "sentado en escritorio" needs, without overclaiming skeletal fidelity the geometry doesn't have. The existing arm-typing oscillation (`_arm_r_pivot` small sine wobble) now doubles as the "typing" cue §7 asks for, since the character is genuinely positioned at a monitor when it plays.

### Validation scene (`game/scenes/dev/npc_showcase.tscn`, `game/src/dev/npc_showcase.gd`) — §14

New dev-only scene, excluded from the shipped export (`export_presets.cfg`'s existing `scenes/dev/**`/`src/dev/**` filter already covers it — no export-config change needed). Unlike `visual_showcase.tscn` (a static populated-workspace shot), this one exercises the **real `StaffAgent` code path**, not a re-implementation of it:

- **Row 1** — one `StaffAgent` per role, all 10 (`junior/engineer/researcher/safety/legal/ops/hr/manager/ceo/cfo`), `IDLE`. The 4 roles with no `StaffRoleCatalog` entry (`ceo/cfo/hr/legal`) get their `character_model_path` set directly to `res://assets/models/characters/<role>.glb`, bypassing the catalog on purpose — this scene's job is validating the models exist and read correctly, independent of whether a gameplay system spawns them yet.
- **Row 2** — four real `StaffAgent`s, all role `engineer`, `IDLE` — the variation system's actual test: same role, same model, different `rng.randomize()` seed each, so skin/hair differ per instance exactly like a real crowd would.
- **Row 3** — three real `StaffAgent`s that call the same public `assign_work()` Campaign uses, walking to and settling at real `desk_single.glb` + `office_chair.glb` + `monitor.glb` instances — the scale/seated-pose/typing test, against real furniture, not stand-in boxes.
- **Row 4** — two agents left to freely wander on a real `NavigationRegion3D` + fresh `NavCoordinator` (mirrors `Campaign._build_navigation()`), for the walk cycle in motion.

## Proportions assessment (§3)

Re-read against the brief's own "Recomendación visual": *"cabeza un poco más grande que en realismo puro; torso claro; brazos y piernas limpios; manos y pies simples pero legibles"* — rendered and inspected (`docs/art/screenshots/npc_variation_detail.png`): the pack's characters already have an oversized head relative to the torso, a clear single-color torso block, simple unadorned limb geometry, and no hyperrealism. This matches the brief's target description closely enough that remodeling wasn't attempted — the P0 concern reads as already resolved by the pack's own authoring, not something introduced or left broken by prior integration work. What this pass could and did fix (rigidity, cloning, seated pose) is documented above; what it could not touch (adding new geometry variants) is in the scope boundary section.

## Screenshots

All real renders (`godot4 --path game --script <throwaway>`, windowed GPU rendering, not `--headless`), saved under `docs/art/screenshots/`:

- `npc_showcase_full.png` — the full validation scene: all 10 roles (row 1), 4-instance variation test (row 2), 3-agent desk/chair scale+sit test (row 3), 2 free-wandering agents (row 4).
- `npc_variation_detail.png` — cropped/zoomed row 1+2: 10 distinct roles side by side (role differentiation, confirmed still intact), plus 4 same-role `engineer`s with visibly different hair colors (black, gray-white, tan, brown) — the concrete evidence for §6's "que 10–20 NPCs no se sientan idénticos."
- `npc_seated_scale_detail.png` — cropped/zoomed row 3: three agents seated at real desks with monitors, legs tucked under the desk edge, chair visible behind — the seated-pose-vs-furniture scale check (§8, §12).
- `npc_ingame_default_zoom.png` — the **real campaign scene**, real HUD, real `CameraController` at its actual default zoom (15.0, the same value the visual-overhaul pass set) — six staff agents standing/moving in the real office, checked for background-blending (§10) and role legibility (§11) at normal play distance.
- `npc_ingame_close_zoom.png` — same real campaign scene, camera zoomed to 8.0 (closer than default) — same legibility check at the brief's "zoom un poco alejado ... / distinguirse desde zoom normal" range, both ends.

## Performance impact (§13)

Re-profiled with `tools/gpu_profile.gd` (real GPU rendering) at the same three scenarios this project already tracks. Full numbers and before/after table in `docs/performance/REAL_GPU_PROFILE.md`'s new "Before/after the NPC visual rework pass" section — headline: **no measurable regression** (stress scenario 150 staff: 60.0 → 59.8 FPS avg, within normal run-to-run noise). `_apply_variation()` runs once per agent at spawn time only (two `Material.duplicate()` calls, not per-frame); the idle/seated animation changes are the same cheap per-frame trig the existing bob/swing system already did — no new draw calls, no new meshes.

## Integration (§15)

- Staff system, `data/staff_roles.json`, spawn (`Campaign._spawn_staff_agent()`), and the `assign_work()`/`clear_work()` public API are all untouched — `_apply_variation()` and the animation changes are additive within `staff_agent.gd`, called from existing hook points (`_build_visual()`, `_animate_visual()`).
- Navigation/collision: unchanged (`NavigationAgent3D` setup, `NavCoordinator` reservation logic, `NavigationObstacle3D` for buildings — none of this pass's diffs touch that code). Exercised for real in `npc_showcase.tscn`'s Row 3/4 (real `assign_work()` walk, real free-roam) and in the real campaign render — agents walked, arrived, and worked with no errors.
- Spawns and references verified working via the real campaign render (`npc_ingame_default_zoom.png`/`npc_ingame_close_zoom.png`): staff spawn from `GameState.staff`, resolve their role's model, and animate correctly.

## Tests (§17)

- `tools/bootstrap.sh`: green after the `_apply_variation()`/animation edits, and again after adding the `npc_showcase` dev scene (two separate full runs, both clean — same ~200-assertion suite as before, no count regression, no new failures).
- Staff scenes: covered by the same bootstrap run (`StaffAgent` real-model-load and animation-pivot smoke tests already in the suite), plus the dedicated `npc_showcase.tscn` real render above.
- Resize: not re-tested this pass — no HUD/camera/anchor code changed (only `staff_agent.gd` and the new dev-only scene), so the visual-overhaul pass's own resize verification (1366x768/1920x1080/2560x1440, `docs/art/VISUAL_OVERHAUL_REPORT.md`) still applies unchanged.
- Save/load: not re-tested — no save schema, `GameState` field, or serialization path touched by this pass.
- Navigation: exercised for real (see "Integration" above) — real `assign_work()` walk-to-desk, real free-roam on a real `NavigationRegion3D`, no errors in either the showcase or the campaign render.
- Real gameplay visual check: done twice, at two camera zoom levels, through the actual `campaign.tscn` scene and actual `CameraController` — not just the dev showcase's own custom camera. See screenshots above.

## Acceptance criteria (§16) — status

| Criterion | Status |
|---|---|
| Ya no se ven como placeholders | Already true since the prior pack-integration pass; this pass adds per-instance variation and pose fixes on top |
| Proporciones mejoraron | Assessed, not remodeled — already close to spec (see "Proportions assessment") |
| Silueta más clara | Unchanged geometry — already role-distinct per silhouette+color; re-verified via render |
| Roles se distinguen mejor | Re-verified via render, unbroken by this pass's changes |
| Hay variedad visible | **Done** — skin/hair variation, confirmed via render |
| Materiales se ven mejor | Unchanged base materials (inherited from the pack); variation added on top |
| Animaciones básicas funcionan mejor | **Done** — idle head-turn/arm-sway, seated pose; "typing" reuses the WORKING arm wobble; "talk" out of scope (new gameplay state, ruled out by the brief itself) |
| Escala correcta respecto al entorno | **Verified** via real desk/chair/monitor render |
| Se ven bien desde cámara real | **Verified** at two zoom levels in the real campaign scene |
| No se mezclan con el fondo | **Verified** — inherited from the visual-overhaul pass's two-light setup, re-checked this pass |
| Rendimiento aceptable | **Verified** — no measurable FPS regression |

## Pendientes

- Clothing/accessory swap system (glasses, beards, helmets, modular garments) — needs new mesh authoring, not achievable without a 3D modeling tool.
- A "talk" animation/interaction state — would require a new `StaffAgent` state and a trigger mechanism (proximity-based NPC-to-NPC interaction), which is a gameplay-system change the brief's own first line excludes from this task.
- `ceo`/`cfo`/`hr`/`legal` still have no gameplay spawn path (no board/legal/HR system exists yet) — same gap the prior two passes already flagged, unchanged by this one.
- A true knee joint for an anatomically accurate sit (current seated pose is a single rigid-leg rotation approximation, documented as such above).
