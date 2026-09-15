class_name CameraController
extends Node3D

## Dedicated production camera rig: WASD/middle-drag pan, Q/E cardinal
## rotation, wheel zoom, F focus, clamped to playable bounds. All motion
## uses exponential smoothing (see _frame_weight) so it converges at the
## same visual rate regardless of frame rate, per docs/technical/INPUT_CAMERA.md.

@export var pan_speed: float = 8.0
@export var pan_smooth_rate: float = 10.0
@export var rotate_smooth_rate: float = 9.0
@export var zoom_smooth_rate: float = 10.0
@export var zoom_min: float = 8.0
@export var zoom_max: float = 34.0
@export var zoom_step: float = 1.5
@export var bounds_min: Vector2 = Vector2(-9.0, -7.0)
@export var bounds_max: Vector2 = Vector2(9.0, 7.0)
@export var elevation_degrees: float = -38.0

var camera: Camera3D

var _yaw_target: float = deg_to_rad(45.0)
var _zoom_target: float
var _pan_target: Vector3 = Vector3.ZERO
var _dragging: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
    _ensure_input_actions()
    _zoom_target = clampf(18.0, zoom_min, zoom_max)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = _zoom_target
    camera.position = Vector3(0.0, 16.0, 18.0)
    camera.rotation_degrees = Vector3(elevation_degrees, 0.0, 0.0)
    camera.current = true
    rotation.y = _yaw_target
    add_child(camera)
    position = _pan_target

func _ensure_input_actions() -> void:
    var bindings: Dictionary = {
        "pan_left": KEY_A,
        "pan_right": KEY_D,
        "pan_up": KEY_W,
        "pan_down": KEY_S,
        "rotate_left": KEY_Q,
        "rotate_right": KEY_E,
        "focus_selected": KEY_F,
    }
    for action: String in bindings:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        if InputMap.action_get_events(action).is_empty():
            var event: InputEventKey = InputEventKey.new()
            event.physical_keycode = bindings[action]
            InputMap.action_add_event(action, event)

func focus_on(target: Vector3) -> void:
    _pan_target = Vector3(target.x, 0.0, target.z)
    _clamp_bounds()

func _clamp_bounds() -> void:
    _pan_target.x = clampf(_pan_target.x, bounds_min.x, bounds_max.x)
    _pan_target.z = clampf(_pan_target.z, bounds_min.y, bounds_max.y)

func _process(delta: float) -> void:
    if Input.is_action_just_pressed("rotate_left"):
        _yaw_target += deg_to_rad(90.0)
    if Input.is_action_just_pressed("rotate_right"):
        _yaw_target -= deg_to_rad(90.0)
    if Input.is_action_just_pressed("focus_selected"):
        focus_on(Vector3.ZERO)

    var pan_axis: Vector2 = Vector2(
        Input.get_axis("pan_left", "pan_right"),
        Input.get_axis("pan_up", "pan_down")
    )
    if pan_axis.length_squared() > 0.0:
        var move: Vector3 = Vector3(pan_axis.x, 0.0, pan_axis.y).normalized().rotated(Vector3.UP, rotation.y) * pan_speed * delta
        _pan_target += move
        _clamp_bounds()

    var reduced: bool = SettingsManager.reduced_motion
    var rot_weight: float = 1.0 if reduced else _frame_weight(rotate_smooth_rate, delta)
    var zoom_weight: float = 1.0 if reduced else _frame_weight(zoom_smooth_rate, delta)
    var pan_weight: float = 1.0 if reduced else _frame_weight(pan_smooth_rate, delta)
    rotation.y = lerp_angle(rotation.y, _yaw_target, rot_weight)
    camera.size = lerp(camera.size, _zoom_target, zoom_weight)
    position = position.lerp(_pan_target, pan_weight)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index == MOUSE_BUTTON_MIDDLE:
            _dragging = mb.pressed
            _drag_last_pos = mb.position
        elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_target = maxf(zoom_min, _zoom_target - zoom_step)
        elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_target = minf(zoom_max, _zoom_target + zoom_step)
    elif event is InputEventMouseMotion and _dragging:
        var mm: InputEventMouseMotion = event
        var viewport_height: float = maxf(float(get_viewport().size.y), 1.0) if is_inside_tree() else 720.0
        var world_per_pixel: float = camera.size / viewport_height
        var screen_delta: Vector2 = mm.position - _drag_last_pos
        _drag_last_pos = mm.position
        var move: Vector3 = Vector3(-screen_delta.x, 0.0, -screen_delta.y) * world_per_pixel
        _pan_target += move.rotated(Vector3.UP, rotation.y)
        _clamp_bounds()

## Exponential smoothing weight: converges at the same rate regardless of
## frame rate, unlike a plain `delta * constant` lerp factor.
static func _frame_weight(rate: float, delta: float) -> float:
    return clampf(1.0 - exp(-rate * delta), 0.0, 1.0)
