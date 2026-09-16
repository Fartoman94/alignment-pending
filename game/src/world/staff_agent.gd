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

var bounds_min: Vector2 = Vector2(-7.0, -5.0)
var bounds_max: Vector2 = Vector2(7.0, 5.0)
var coordinator: NavCoordinator
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

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
    var packed: PackedScene = load(character_model_path)
    if packed == null:
        push_error("StaffAgent: could not load character model '%s'" % character_model_path)
        return
    var model: Node3D = packed.instantiate()
    add_child(model)
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
        if limb_names.has(String(mesh_inst.name)):
            var pivot: Node3D = Node3D.new()
            pivot.name = "%s_pivot" % mesh_inst.name
            var joint_z: float = _joint_z(mesh_inst)
            pivot.position = Vector3(0.0, 0.0, joint_z)
            world_node.remove_child(mesh_inst)
            visual_root.add_child(pivot)
            pivot.add_child(mesh_inst)
            mesh_inst.position = Vector3(0.0, 0.0, -joint_z)
            match String(mesh_inst.name):
                "leg_l": _leg_l_pivot = pivot
                "leg_r": _leg_r_pivot = pivot
                "arm_l": _arm_l_pivot = pivot
                "arm_r": _arm_r_pivot = pivot
        else:
            world_node.remove_child(mesh_inst)
            _bob_group.add_child(mesh_inst)
    model.queue_free()
    _apply_variation()

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
    var head: MeshInstance3D = _bob_group.get_node_or_null("head")
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
    var hair: MeshInstance3D = _bob_group.get_node_or_null("hair")
    if hair != null and hair.mesh != null:
        var hair_mat: StandardMaterial3D = hair.mesh.surface_get_material(0)
        if hair_mat != null:
            var hair_variant: StandardMaterial3D = hair_mat.duplicate()
            hair_variant.albedo_color = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
            hair.set_surface_override_material(0, hair_variant)

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
            _arm_l_pivot.rotation.x = sin(idle_t * 0.7) * 0.04
            _arm_r_pivot.rotation.x = sin(idle_t * 0.7 + 0.6) * 0.04
            _bob_group.position.z = sin(idle_t) * 0.015
            # A slow head-turn/weight-shift ("mirar alrededor" from the
            # brief) — a full body yaw is a much cheaper, still-readable
            # stand-in for a separate neck joint the geometry doesn't have.
            _bob_group.rotation.y = sin(idle_t * 0.35) * 0.12

func _try_start_moving() -> void:
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
        state = State.WORKING
    else:
        state = State.IDLE
        _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)

## Walks to target (a workstation's world position) and stays there once
## arrived, instead of resuming idle wandering. Cancels any pending
## wander-destination reservation immediately.
func assign_work(target: Vector3) -> void:
    _has_work_target = true
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
