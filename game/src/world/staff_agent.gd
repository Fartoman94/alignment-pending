class_name StaffAgent
extends Node3D

## Navigation + state machine for an office occupant: idle, then walk to a
## reserved random destination, then idle again — unless a work task is
## assigned (P11's TaskManager), in which case it walks to the workstation
## and stays there (WORKING) until the task completes or is cancelled.

enum State { IDLE, MOVING, WORKING }

const SPEED: float = 2.4
const IDLE_MIN_SECONDS: float = 1.0
const IDLE_MAX_SECONDS: float = 4.0
const ARRIVE_DISTANCE: float = 0.3
const MAX_RESERVE_ATTEMPTS: int = 6
## How fast the character turns to face its movement direction, in
## radians/second-equivalent lerp weight. Fast enough to feel responsive
## over the office's short walk legs, slow enough not to snap instantly on
## every avoidance-driven micro-adjustment.
const TURN_SPEED: float = 10.0

var bounds_min: Vector2 = Vector2(-7.0, -5.0)
var bounds_max: Vector2 = Vector2(7.0, 5.0)
var coordinator: NavCoordinator
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Production-kit pass ("NPCs never wander randomly"), extended by the
## world+NPC overhaul pass ("van a coffee point / meeting / whiteboard
## según tarea"): a small set of real, tagged destinations (the
## break-room corner, the planning whiteboard) an idle agent sometimes
## heads for instead of a uniformly random point in bounds — a
## deliberately modest, honest scope: a handful of shared destinations on
## top of the existing random-wander fallback, not a full needs/schedule
## simulation with per-role routing (see docs/production/
## PRODUCTION_KIT_AUDIT.md's "NPC purposeful movement" note for why that
## bigger system is out of scope here). Empty by default; only real
## campaign-spawned agents get any (Campaign._spawn_staff_agent()) —
## dev/showcase scenes keep pure random wander unless they opt in too.
var ambient_destinations: Array[Vector3] = []
## VISUAL_OVERHAUL pass, priority 4 ("NPCs que usan objetos reales"):
## parallel to ambient_destinations by index — what an agent is doing once
## it arrives, so the coffee machine/whiteboard read as more than just a
## walk target. Empty entries (or an index with no tag) fall back to plain
## idle, same as before this pass.
var ambient_activity_tags: Array[String] = []
## Set on arrival at a tagged ambient destination (see _finish_move()),
## cleared the moment the agent starts any new move (wander, ambient, or
## assigned work) — see _try_start_moving()/assign_work().
var _ambient_activity: String = ""
var _pending_ambient_activity: String = ""
## Rolled once per idle-to-moving transition, not per frame — see
## _try_start_moving().
## CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 2 ("no caminar al azar"):
## raised from 0.3 — at the old value, most idle wandering was still a
## uniform-random point in the room bounds (the fallback in
## _try_start_moving() below), which is exactly the "muñecos caminando al
## azar" the phase calls out. Still not zero (a real needs/schedule AI is
## out of scope — see the class doc comment above), but a real, tagged
## destination (break room / whiteboard / lounge) is now the common case
## instead of the exception.
const AMBIENT_DESTINATION_CHANCE: float = 0.65

var state: State = State.IDLE
var total_distance_traveled: float = 0.0
var destinations_reached: int = 0

var _idle_timer: float = 0.0
var _nav_agent: NavigationAgent3D
var _current_reservation: Vector3
var _has_reservation: bool = false
var _synced: bool = false
var _has_work_target: bool = false

# P40, replaced by the finalization-pack 3D asset pack: a real, authored
# low-poly character model (game/assets/models/characters/*.glb, one per
# role — see StaffRoleCatalog's character_model field) instead of the
# original procedural capsule body. Still animated procedurally (no
# skeleton/AnimationPlayer — the pack's characters are static meshes by
# design), just re-transformed every frame by _animate_visual(), never
# rebuilt — cheap enough for 150+ agents at once.
##
## The pack's meshes are authored Z-up in local space (confirmed by
## rendering one and inspecting the pixels: without a corrective
## rotation, a character renders as a top-down silhouette, not a front
## view) — _build_visual() rotates the whole loaded model -90° on X to
## match Godot's Y-up convention. leg_l/leg_r/arm_l/arm_r are wrapped in
## their own pivot Node3D positioned at the joint (hip/shoulder — the top
## of each limb mesh's local Z range) instead of rotating the limb mesh
## directly: the mesh's own local origin sits at the limb's far end (the
## foot for legs, and — critically — nowhere near the arm mesh at all
## for arms, since a hanging arm's local origin is inherited from the
## character root, well below the shoulder), so rotating the raw mesh
## node would swing it around the wrong point entirely.
var _leg_l_pivot: Node3D
var _leg_r_pivot: Node3D
var _arm_l_pivot: Node3D
var _arm_r_pivot: Node3D
## Everything that isn't a leg/arm pivot (torso, head, hair, and every
## role-specific accessory — tie, glasses, labcoat, vest, helmet, cap,
## tablet) reparented under one group so the idle/walk/work bob is a
## single position offset instead of N separate ones.
var _bob_group: Node3D
var _visual_time: float = 0.0
## Random per-agent phase offset so a crowd doesn't all bob in unison.
var _visual_phase: float = 0.0
## Set by the spawner (Campaign._spawn_staff_agent()) from the staff
## member's role (StaffRoleCatalog.character_model) before this node
## enters the tree.
var character_model_path: String = ""
## Optional same-role alternative meshes (StaffRoleCatalog.
## character_model_pool, mega-asset-pack pass) — _build_visual() picks
## one of [character_model_path] + this pool per agent, deterministically
## by rng, for real mesh variety on top of the existing skin/hair tint
## variation. Empty by default (old pack roles with no pool behave
## exactly as before).
var character_model_pool: Array[String] = []

## Total-visual-rework pass: a second, real character pipeline for the
## Blender-generated humanoids (game/tools/blender_generators/
## generate_humanoids.py) — a genuine Skeleton3D + AnimationPlayer with
## 5 baked clips (idle/walk/typing/talk/sit), not this file's usual flat
## unskinned-mesh + manual-pivot approach. Detected per-instance in
## _build_visual() (does the loaded model have a Skeleton3D?), not a
## separate agent type — a crowd can mix both kinds of character freely.
## Skinned meshes can't be reparented into _bob_group without breaking
## their skin binding, so none of the pivot/bob machinery above applies
## to this path; _animate_visual_skeletal() below is the whole animation
## story for these agents, real AnimationPlayer.play() calls instead of
## per-frame trig.
var _is_skeletal: bool = false
var _anim_player: AnimationPlayer
var _current_anim: String = ""

func _ready() -> void:
    _nav_agent = NavigationAgent3D.new()
    _nav_agent.radius = 0.3
    _nav_agent.path_desired_distance = 0.3
    _nav_agent.target_desired_distance = ARRIVE_DISTANCE
    _nav_agent.avoidance_enabled = true
    # P44: measured with the 150-agent stress scene — RVO avoidance's
    # per-tick neighbor search defaults (500m radius, 10 neighbors) scan
    # far more of the office than a ~14x10 unit floor ever needs, and
    # every extra neighbor considered costs CPU across all 150 agents,
    # every physics tick. Capped to what a crowded single office actually
    # needs (see docs/technical/PERFORMANCE_BUDGET.md's "stagger path
    # queries" guidance) with no visible change to movement quality.
    _nav_agent.neighbor_distance = 6.0
    _nav_agent.max_neighbors = 5
    _nav_agent.velocity_computed.connect(_on_velocity_computed)
    add_child(_nav_agent)
    _build_visual()
    _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
    # The navigation map needs at least one sync pass before path queries
    # return anything useful.
    await get_tree().physics_frame
    await get_tree().physics_frame
    _synced = true

## Loads the role's authored character model, corrects its authored Z-up
## orientation to Godot's Y-up, and wraps each limb in a joint-positioned
## pivot so rotation animates naturally (see the class-level doc comment
## above for why the raw meshes can't just be rotated directly).
func _build_visual() -> void:
    _visual_phase = rng.randf_range(0.0, TAU)
    var candidates: Array[String] = [character_model_path]
    candidates.append_array(character_model_pool)
    var chosen_path: String = candidates[rng.randi() % candidates.size()]
    var packed: PackedScene = load(chosen_path)
    if packed == null:
        push_error("StaffAgent: could not load character model '%s'" % chosen_path)
        return
    var model: Node3D = packed.instantiate()
    add_child(model)

    var found_anim_player: AnimationPlayer = _find_animation_player(model)
    if found_anim_player != null:
        _build_visual_skeletal(model, found_anim_player)
        return

    var world_node: Node = model.get_node_or_null("world")
    if world_node == null:
        push_error("StaffAgent: character model '%s' has no 'world' root node" % character_model_path)
        return

    # Everything visible (bob group AND limb pivots) lives under one
    # wrapper carrying the corrective rotation — reparenting limbs
    # directly under `self` (as an earlier version of this did) silently
    # left them outside the rotation, rendering the whole character
    # sideways/from-above. Caught by actually rendering and looking at
    # the pixels, not just by the headless test suite passing.
    var visual_root: Node3D = Node3D.new()
    visual_root.name = "VisualRoot"
    visual_root.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    add_child(visual_root)

    _bob_group = Node3D.new()
    _bob_group.name = "BobGroup"
    visual_root.add_child(_bob_group)

    var limb_names: Array[String] = ["leg_l", "leg_r", "arm_l", "arm_r"]
    for child in world_node.get_children().duplicate():
        var mesh_inst: Node3D = child
        # Godot's glTF importer suffixes every node with its sibling index
        # on import ("leg_l" -> "leg_l_0") — seen on the mega-asset-pack's
        # characters but not the original pack's (bare "leg_l"). Matched by
        # prefix, not equality, so both naming styles work identically;
        # never assumed from one pack alone again.
        var limb_name: String = _matching_limb_prefix(String(mesh_inst.name), limb_names)
        if not limb_name.is_empty():
            var pivot: Node3D = Node3D.new()
            pivot.name = "%s_pivot" % limb_name
            var joint_z: float = _joint_z(mesh_inst)
            pivot.position = Vector3(0.0, 0.0, joint_z)
            world_node.remove_child(mesh_inst)
            visual_root.add_child(pivot)
            pivot.add_child(mesh_inst)
            mesh_inst.position = Vector3(0.0, 0.0, -joint_z)
            match limb_name:
                "leg_l": _leg_l_pivot = pivot
                "leg_r": _leg_r_pivot = pivot
                "arm_l": _arm_l_pivot = pivot
                "arm_r": _arm_r_pivot = pivot
        else:
            world_node.remove_child(mesh_inst)
            _bob_group.add_child(mesh_inst)
    model.queue_free()
    _apply_variation()

func _find_animation_player(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer:
        return n
    for c in n.get_children():
        var found: AnimationPlayer = _find_animation_player(c)
        if found != null:
            return found
    return null

func _find_skeleton(n: Node) -> Skeleton3D:
    if n is Skeleton3D:
        return n
    for c in n.get_children():
        var found: Skeleton3D = _find_skeleton(c)
        if found != null:
            return found
    return null

## Confirmed by rendering (4 cardinal angles, same discipline as every
## other facing/orientation check in this project): these models' front
## already faces local +Z at rotation.y == 0, the same convention every
## other character pack in this project already uses — no corrective
## rotation needed here, unlike the flat-mesh path's -90° X fix for the
## other packs' Z-up authoring.
func _build_visual_skeletal(model: Node3D, anim_player: AnimationPlayer) -> void:
    _is_skeletal = true
    _anim_player = anim_player
    # The generator bakes clips with no explicit loop mode, which
    # defaults to "play once and hold the last frame" — confirmed by
    # rendering "walk" and watching it freeze mid-stride instead of
    # cycling. Every clip here (idle/walk/typing/talk/sit) is meant to
    # cycle continuously, so this is set for all of them, not guessed at
    # per-clip.
    for anim_name: StringName in _anim_player.get_animation_list():
        var anim: Animation = _anim_player.get_animation(anim_name)
        if anim != null:
            anim.loop_mode = Animation.LOOP_LINEAR
    var skeleton: Skeleton3D = _find_skeleton(model)
    if skeleton != null:
        _apply_variation_skeletal(skeleton)

## Same per-instance skin/hair tint variation _apply_variation() already
## does for the flat-mesh pack, adapted for this hierarchy: the parts
## are direct children of the Skeleton3D (never reparented — a skinned
## mesh's "skeleton" reference is a NodePath that would break if moved),
## and named "Head"/"Hair" (capitalized, the generator's own convention)
## instead of "head"/"hair".
func _apply_variation_skeletal(skeleton: Skeleton3D) -> void:
    var head: MeshInstance3D = _find_child_by_prefix(skeleton, "Head") as MeshInstance3D
    if head != null and head.mesh != null:
        var skin_mat: StandardMaterial3D = head.mesh.surface_get_material(0)
        if skin_mat != null:
            var skin_variant: StandardMaterial3D = skin_mat.duplicate()
            var skin_shift: float = rng.randf_range(-0.08, 0.08)
            skin_variant.albedo_color = Color(
                clampf(skin_variant.albedo_color.r + skin_shift, 0.0, 1.0),
                clampf(skin_variant.albedo_color.g + skin_shift * 0.85, 0.0, 1.0),
                clampf(skin_variant.albedo_color.b + skin_shift * 0.7, 0.0, 1.0),
            )
            head.set_surface_override_material(0, skin_variant)
    var hair: MeshInstance3D = _find_child_by_prefix(skeleton, "Hair") as MeshInstance3D
    if hair != null and hair.mesh != null:
        var hair_mat: StandardMaterial3D = hair.mesh.surface_get_material(0)
        if hair_mat != null:
            var hair_variant: StandardMaterial3D = hair_mat.duplicate()
            hair_variant.albedo_color = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
            hair.set_surface_override_material(0, hair_variant)

## Real AnimationPlayer.play() per state, instead of _animate_visual()'s
## trig-pivot math — the whole animation story for a skeletal agent.
## Only calls .play() when the target clip actually changes, not every
## frame, so it doesn't restart the same animation from frame 0
## constantly (confirmed by rendering: calling .play() every physics
## frame visibly froze the character instead of animating it).
func _animate_visual_skeletal(_delta: float) -> void:
    if _anim_player == null:
        return
    var target: String = "idle"
    match state:
        State.MOVING:
            target = "walk"
        State.WORKING:
            target = "typing"
        State.IDLE:
            # Baked clip set is idle/walk/typing/talk/sit (see
            # _build_visual_skeletal()'s doc comment) — no dedicated
            # "drink" clip, so the break-room/whiteboard ambient spots use
            # "talk" (chatting over coffee / discussing at the board reads
            # the same at isometric distance); "lounge" (CLAUDE_VISUAL_
            # EXECUTION_MASTERPACK Phase 2/3, Campaign.LOUNGE_SPOT) uses
            # the real "sit" clip instead, since that one actually has a
            # matching authored pose.
            match _ambient_activity:
                "lounge":
                    target = "sit"
                "":
                    target = "idle"
                _:
                    target = "talk"
    if target != _current_anim and _anim_player.has_animation(target):
        _anim_player.play(target)
        _current_anim = target

func _matching_limb_prefix(node_name: String, limb_names: Array[String]) -> String:
    for limb_name: String in limb_names:
        if node_name == limb_name or node_name.begins_with(limb_name + "_"):
            return limb_name
    return ""

## Same import-suffix quirk as the limb matching above — "head"/"hair"
## may be "head_5"/"hair_6" depending on the source pack, so this finds
## the first child whose name matches that prefix instead of an exact
## get_node_or_null() lookup.
func _find_child_by_prefix(parent: Node, prefix: String) -> Node:
    for child in parent.get_children():
        var name_str: String = String(child.name)
        if name_str == prefix or name_str.begins_with(prefix + "_"):
            return child
    return null

## Finalization pack visual-rework brief: "que 10-20 NPCs en pantalla no
## se sientan idénticos." The pack ships one fixed material per part per
## character file — load()'d role-for-role, so (Godot caches resources by
## path) every agent of the same role would otherwise share the exact
## same Material *resource*, and mutating it would restyle every other
## agent of that role too, not just this one. Duplicating onto a surface
## override, never touching the shared Mesh resource, is what makes this
## safe per-instance. Only skin tone and hair color vary — every other
## part (torso/vest/labcoat and so on) keeps the role's own baked color
## untouched, since that's the actual role-legibility signal the same
## brief asks to preserve.
const HAIR_COLORS: Array[Color] = [
    Color("2b2320"), Color("4a3427"), Color("6b4a2f"), Color("b89968"),
    Color("d9c9a3"), Color("8a8580"), Color("1c1c1e"), Color("7a3b2e"),
]
func _apply_variation() -> void:
    var head: MeshInstance3D = _find_child_by_prefix(_bob_group, "head") as MeshInstance3D
    if head != null and head.mesh != null:
        var skin_mat: StandardMaterial3D = head.mesh.surface_get_material(0)
        if skin_mat != null:
            var skin_variant: StandardMaterial3D = skin_mat.duplicate()
            var skin_shift: float = rng.randf_range(-0.08, 0.08)
            skin_variant.albedo_color = Color(
                clampf(skin_variant.albedo_color.r + skin_shift, 0.0, 1.0),
                clampf(skin_variant.albedo_color.g + skin_shift * 0.85, 0.0, 1.0),
                clampf(skin_variant.albedo_color.b + skin_shift * 0.7, 0.0, 1.0),
            )
            head.set_surface_override_material(0, skin_variant)
    var hair: MeshInstance3D = _find_child_by_prefix(_bob_group, "hair") as MeshInstance3D
    if hair != null and hair.mesh != null:
        var hair_mat: StandardMaterial3D = hair.mesh.surface_get_material(0)
        if hair_mat != null:
            var hair_variant: StandardMaterial3D = hair_mat.duplicate()
            hair_variant.albedo_color = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
            hair.set_surface_override_material(0, hair_variant)
    if head != null:
        _add_face_details(head)

## CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 2 ("cara con ojos/nariz/boca/
## pelo"): the original flat-mesh pack's head is a bare cube — no eyes,
## nose, or mouth geometry at all (confirmed by dumping ceo.glb's node
## tree and rendering a close-up: a featureless skin-colored blob). Only
## `ceo`/`cfo` still use this pack — the other 8 roles were migrated to
## the real generated-humanoid pipeline (see class doc comment above),
## which already has proper face geometry from `_build_visual_skeletal()`
## and doesn't go through this function at all. Rather than pull in
## Blender (not installed in this environment, and installing/downloading
## a new toolchain for 2 roles is disproportionate), this adds the same
## simple primitive face features `tools/blender_generators/
## generate_humanoids.py` bakes for the other roles, built directly with
## Godot's own `ProceduralMeshFactory` instead — same visual language
## (flat-shaded low-poly boxes), no new asset files or dependencies.
## Coordinates are relative to `head`'s own local space, derived from its
## real mesh AABB (center (0,0,1.8), half-extent 0.3) — not guessed: this
## pack's "front" is -Y in a part's local space (derived from the tie
## mesh's known position and the class doc comment's "necktie is visible
## from +Z" *after* the VisualRoot's -90°-X correction, which maps
## local -Y to final +Z).
const _FACE_EYE_WHITE: Color = Color("f7f7f5")
const _FACE_PUPIL: Color = Color("14120f")
const _FACE_MOUTH: Color = Color("8a4a45")
func _add_face_details(head: MeshInstance3D) -> void:
    if head.get_node_or_null("FaceDetails") != null:
        return  # Pooled/reused agents shouldn't stack a second set.
    var group := Node3D.new()
    group.name = "FaceDetails"
    head.add_child(group)
    for side in [1.0, -1.0]:
        # CapsuleMesh requires height >= 2*radius (Godot clamps otherwise);
        # using exactly that minimum makes it read as a small sphere.
        var eye := ProceduralMeshFactory.make_capsule(
            "Eye", 0.028, 0.056, _FACE_EYE_WHITE, 0.3)
        eye.position = Vector3(0.11 * side, -0.30, 1.87)
        eye.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        group.add_child(eye)
        var pupil := ProceduralMeshFactory.make_capsule(
            "Pupil", 0.012, 0.024, _FACE_PUPIL, 0.2)
        pupil.position = Vector3(0.11 * side, -0.315, 1.87)
        pupil.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        group.add_child(pupil)
    var nose := ProceduralMeshFactory.make_box(
        "Nose", Vector3(0.035, 0.045, 0.05), head.mesh.surface_get_material(0).albedo_color if head.mesh.surface_get_material(0) else Color("e0b596"))
    nose.position = Vector3(0.0, -0.32, 1.81)
    group.add_child(nose)
    var mouth := ProceduralMeshFactory.make_box(
        "Mouth", Vector3(0.09, 0.015, 0.025), _FACE_MOUTH)
    mouth.position = Vector3(0.0, -0.30, 1.71)
    group.add_child(mouth)

## The joint a limb hangs/pivots from — the top of its local Z-range
## (hip for a leg, shoulder for an arm) — read directly from the mesh's
## own AABB rather than hardcoded, so it works for every character in
## the pack without per-model tuning.
func _joint_z(mesh_inst: Node3D) -> float:
    if not (mesh_inst is MeshInstance3D):
        return 0.0
    var mesh: Mesh = (mesh_inst as MeshInstance3D).mesh
    if mesh == null:
        return 0.0
    var aabb: AABB = mesh.get_aabb()
    return aabb.position.z + aabb.size.z

func _physics_process(delta: float) -> void:
    if not _synced or GameState.paused:
        return
    match state:
        State.IDLE:
            _idle_timer -= delta
            if _idle_timer <= 0.0:
                _try_start_moving()
        State.MOVING:
            _process_moving(delta)
        State.WORKING:
            pass  # stationary at the workstation until the task ends
    _animate_visual(delta)

## Procedural animation approximations (P40) — no imported skeleton/
## AnimationPlayer, just cheap per-frame trig on the modular parts built
## in _build_visual(). Three readable states: a slow idle bob, a walking
## limb swing while MOVING, and a smaller, faster "focused" bob while
## WORKING, so a player can tell what a staff member is doing at a glance
## even at isometric distance.
func _animate_visual(delta: float) -> void:
    if _is_skeletal:
        _animate_visual_skeletal(delta)
        return
    if _leg_l_pivot == null:
        return  # _build_visual() failed to load a model — nothing to animate.
    _visual_time += delta
    var t: float = _visual_time * 6.0 + _visual_phase
    match state:
        State.MOVING:
            var swing: float = sin(t) * 0.5
            _leg_l_pivot.rotation.x = swing
            _leg_r_pivot.rotation.x = -swing
            _arm_l_pivot.rotation.x = -swing * 0.6
            _arm_r_pivot.rotation.x = swing * 0.6
            _bob_group.position.z = absf(sin(t)) * 0.03
            _bob_group.rotation.y = 0.0
        State.WORKING:
            # A seated-at-the-desk approximation (finalization pack's
            # NPC-rework brief asks for a "sit" pose): the legs are a
            # single rigid segment each (no knee joint to bend at), so a
            # full anatomical sit isn't reachable without adding one —
            # documented as such rather than faked. Rotating the whole
            # leg forward from the hip plus lowering the torso reads as
            # "seated" at isometric distance without claiming more
            # fidelity than the geometry actually has.
            var focus_t: float = _visual_time * 10.0 + _visual_phase
            _arm_r_pivot.rotation.x = -0.9 + sin(focus_t) * 0.15
            _arm_l_pivot.rotation.x = -0.1
            _leg_l_pivot.rotation.x = 1.15
            _leg_r_pivot.rotation.x = 1.15
            _bob_group.position.z = -0.22 + sin(focus_t * 0.5) * 0.01
            _bob_group.rotation.y = 0.0
        State.IDLE:
            var idle_t: float = _visual_time * 1.5 + _visual_phase
            _leg_l_pivot.rotation.x = 0.0
            _leg_r_pivot.rotation.x = 0.0
            if not _ambient_activity.is_empty():
                # VISUAL_OVERHAUL pass, priority 4: a distinct "engaged
                # with the object" pose for the flat-mesh pack (no
                # skeleton here to play a real "talk" clip on) — one arm
                # raised roughly to chest/mouth height and held, instead
                # of the loose idle sway, so a coffee-machine or
                # whiteboard visit reads differently from just standing
                # around at isometric distance.
                var talk_t: float = _visual_time * 3.0 + _visual_phase
                _arm_r_pivot.rotation.x = -1.0 + sin(talk_t) * 0.08
                _arm_l_pivot.rotation.x = sin(idle_t * 0.7) * 0.04
                _bob_group.position.z = sin(idle_t) * 0.01
                _bob_group.rotation.y = sin(idle_t * 0.25) * 0.08
            else:
                _arm_l_pivot.rotation.x = sin(idle_t * 0.7) * 0.04
                _arm_r_pivot.rotation.x = sin(idle_t * 0.7 + 0.6) * 0.04
                _bob_group.position.z = sin(idle_t) * 0.015
                # A slow head-turn/weight-shift ("mirar alrededor" from the
                # brief) — a full body yaw is a much cheaper, still-readable
                # stand-in for a separate neck joint the geometry doesn't have.
                _bob_group.rotation.y = sin(idle_t * 0.35) * 0.12

func _try_start_moving() -> void:
    _pending_ambient_activity = ""
    if not ambient_destinations.is_empty() and rng.randf() < AMBIENT_DESTINATION_CHANCE and coordinator != null:
        var pick_index: int = rng.randi() % ambient_destinations.size()
        var pick: Vector3 = ambient_destinations[pick_index]
        if coordinator.try_reserve(pick):
            _current_reservation = pick
            _has_reservation = true
            _nav_agent.target_position = pick
            state = State.MOVING
            if pick_index < ambient_activity_tags.size():
                _pending_ambient_activity = ambient_activity_tags[pick_index]
            return
    for attempt in MAX_RESERVE_ATTEMPTS:
        var candidate: Vector3 = Vector3(
            rng.randf_range(bounds_min.x, bounds_max.x), 0.0,
            rng.randf_range(bounds_min.y, bounds_max.y)
        )
        if coordinator == null or coordinator.try_reserve(candidate):
            _current_reservation = candidate
            _has_reservation = coordinator != null
            _nav_agent.target_position = candidate
            state = State.MOVING
            return
    # Every candidate collided with another reservation this tick; back off
    # briefly instead of forcing a placement. This is the deadlock escape
    # hatch: nobody blocks forever, everybody just retries shortly after.
    _idle_timer = 0.2

func _process_moving(delta: float) -> void:
    if _nav_agent.is_navigation_finished():
        _finish_move()
        return
    var next_pos: Vector3 = _nav_agent.get_next_path_position()
    var desired: Vector3 = next_pos - global_position
    desired.y = 0.0
    if desired.length() > 0.001:
        desired = desired.normalized() * SPEED
        # The character model's authored front faces local +Z at rotation.y
        # == 0 (verified by rendering: the necktie is visible from +Z, the
        # bare back from -Z) — nothing turned this to face the walk
        # direction before, so every agent kept its spawn-time orientation
        # while wandering in every direction, reading as walking sideways
        # or backwards. Faced toward the path's next waypoint (the intent),
        # not the post-avoidance velocity, so a momentary avoidance swerve
        # doesn't snap the body to face sideways.
        var target_yaw: float = atan2(desired.x, desired.z)
        rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
    if _nav_agent.avoidance_enabled:
        _nav_agent.set_velocity(desired)
    else:
        _apply_velocity(desired, delta)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
    # This callback can fire from an avoidance computation that was queued
    # just before the game paused; never apply movement while paused,
    # regardless of when the callback lands.
    if GameState.paused:
        return
    _apply_velocity(safe_velocity, get_physics_process_delta_time())

func _apply_velocity(velocity: Vector3, delta: float) -> void:
    var move: Vector3 = velocity * delta
    global_position += move
    total_distance_traveled += move.length()

func _finish_move() -> void:
    if _has_reservation and coordinator != null:
        coordinator.release(_current_reservation)
    _has_reservation = false
    destinations_reached += 1
    if _has_work_target:
        _ambient_activity = ""
        state = State.WORKING
    else:
        _ambient_activity = _pending_ambient_activity
        state = State.IDLE
        _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)

## Walks to target (a workstation's world position) and stays there once
## arrived, instead of resuming idle wandering. Cancels any pending
## wander-destination reservation immediately.
func assign_work(target: Vector3) -> void:
    _has_work_target = true
    _ambient_activity = ""
    _pending_ambient_activity = ""
    if _has_reservation and coordinator != null:
        coordinator.release(_current_reservation)
        _has_reservation = false
    _nav_agent.target_position = target
    state = State.MOVING

## Returns to idle wandering. Safe to call even if not currently working.
func clear_work() -> void:
    _has_work_target = false
    if state == State.WORKING:
        state = State.IDLE
        _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
