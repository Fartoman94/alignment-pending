class_name StaffAgent
extends Node3D

## Minimal navigation + state machine for an office occupant: idle, then
## walk to a reserved random destination, then idle again. This prompt owns
## movement/pathing only — the full roster (roles/skills/salary/hiring) is
## a later system, so this deliberately stays generic and is not wired into
## GameState or spawned in the live campaign yet.

enum State { IDLE, MOVING }

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

func _ready() -> void:
    _nav_agent = NavigationAgent3D.new()
    _nav_agent.radius = 0.3
    _nav_agent.path_desired_distance = 0.3
    _nav_agent.target_desired_distance = ARRIVE_DISTANCE
    _nav_agent.avoidance_enabled = true
    _nav_agent.velocity_computed.connect(_on_velocity_computed)
    add_child(_nav_agent)
    _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
    # The navigation map needs at least one sync pass before path queries
    # return anything useful.
    await get_tree().physics_frame
    await get_tree().physics_frame
    _synced = true

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
    state = State.IDLE
    _idle_timer = rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)
