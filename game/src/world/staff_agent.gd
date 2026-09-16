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
## Set by the spawner (Campaign._spawn_staff_agent()) from the staff
## member's role (StaffRoleCatalog.visual_color) before this node enters
## the tree. P39: a minimal procedural placeholder body — real character
## art/animation is P40's job.
var role_color: Color = Color.WHITE

var state: State = State.IDLE
var total_distance_traveled: float = 0.0
var destinations_reached: int = 0

var _idle_timer: float = 0.0
var _nav_agent: NavigationAgent3D
var _current_reservation: Vector3
var _has_reservation: bool = false
var _synced: bool = false
var _has_work_target: bool = false

# P40: modular low-poly body parts + procedural animation. Each part is
# its own MeshInstance3D (swappable/extendable independently — "modular"),
# built once in _build_visual() and then just re-transformed every frame
# by _animate_visual(), never rebuilt — cheap enough for 50+ agents at
# once (a handful of sin() calls and Transform assignments per agent).
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _accessory: MeshInstance3D
var _visual_time: float = 0.0
## Random per-agent phase offset so a crowd doesn't all bob in unison.
var _visual_phase: float = 0.0

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

## A modular low-poly placeholder body (P40): 7 independent parts, each
## its own MeshInstance3D, tinted by department (role_color). Original
## proportions chosen for silhouette clarity at isometric camera distance
## — a large head-to-body ratio and a bright accessory accent read clearly
## even as a small on-screen shape. Real authored character art is a later
## content pass; this is the procedural floor described in
## docs/design/ART_ASSET_LIST.md's "Character MVP".
func _build_visual() -> void:
    _visual_phase = rng.randf_range(0.0, TAU)
    _torso = ProceduralMeshFactory.make_capsule("Torso", 0.28, 1.3, role_color)
    _torso.position.y = 0.75
    add_child(_torso)
    _head = ProceduralMeshFactory.make_capsule("Head", 0.18, 0.36, role_color.lightened(0.35))
    _head.position.y = 1.56
    add_child(_head)
    _left_arm = ProceduralMeshFactory.make_capsule("LeftArm", 0.07, 0.7, role_color.darkened(0.1))
    _left_arm.position = Vector3(-0.32, 1.05, 0.0)
    add_child(_left_arm)
    _right_arm = ProceduralMeshFactory.make_capsule("RightArm", 0.07, 0.7, role_color.darkened(0.1))
    _right_arm.position = Vector3(0.32, 1.05, 0.0)
    add_child(_right_arm)
    _left_leg = ProceduralMeshFactory.make_capsule("LeftLeg", 0.09, 0.8, role_color.darkened(0.3))
    _left_leg.position = Vector3(-0.13, 0.35, 0.0)
    add_child(_left_leg)
    _right_leg = ProceduralMeshFactory.make_capsule("RightLeg", 0.09, 0.8, role_color.darkened(0.3))
    _right_leg.position = Vector3(0.13, 0.35, 0.0)
    add_child(_right_leg)
    # A small bright badge — the one "accessory" slot (ART_ASSET_LIST.md);
    # a distinct authored accessory per role is a later art pass.
    _accessory = ProceduralMeshFactory.make_box("Accessory", Vector3(0.12, 0.12, 0.05), role_color.lightened(0.6), 0.4)
    _accessory.position = Vector3(0.0, 0.95, 0.26)
    add_child(_accessory)

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
    _visual_time += delta
    var t: float = _visual_time * 6.0 + _visual_phase
    match state:
        State.MOVING:
            var swing: float = sin(t) * 0.5
            _left_leg.rotation.x = swing
            _right_leg.rotation.x = -swing
            _left_arm.rotation.x = -swing * 0.6
            _right_arm.rotation.x = swing * 0.6
            _torso.position.y = 0.75 + absf(sin(t)) * 0.03
            _head.position.y = 1.56 + absf(sin(t)) * 0.03
        State.WORKING:
            var focus_t: float = _visual_time * 10.0 + _visual_phase
            _right_arm.rotation.x = -0.9 + sin(focus_t) * 0.15
            _left_arm.rotation.x = -0.1
            _left_leg.rotation.x = 0.0
            _right_leg.rotation.x = 0.0
            _torso.position.y = 0.75
            _head.position.y = 1.56 + sin(focus_t * 0.5) * 0.01
        State.IDLE:
            var idle_t: float = _visual_time * 1.5 + _visual_phase
            _left_leg.rotation.x = 0.0
            _right_leg.rotation.x = 0.0
            _left_arm.rotation.x = 0.0
            _right_arm.rotation.x = 0.0
            _torso.position.y = 0.75 + sin(idle_t) * 0.015
            _head.position.y = 1.56 + sin(idle_t) * 0.02

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
