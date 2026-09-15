extends Node3D

var camera_rig: Node3D
var camera: Camera3D
var hud_label: Label
var yaw_target: float = deg_to_rad(45.0)
var zoom_target: float = 18.0

func _ready() -> void:
    _ensure_input_actions()
    _build_environment()
    _build_office()
    _build_camera()
    _build_hud()


func _ensure_input_actions() -> void:
    var bindings := {
        "pan_left": KEY_A,
        "pan_right": KEY_D,
        "pan_up": KEY_W,
        "pan_down": KEY_S,
        "rotate_left": KEY_Q,
        "rotate_right": KEY_E,
        "toggle_pause": KEY_SPACE
    }
    for action: String in bindings:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        if InputMap.action_get_events(action).is_empty():
            var event := InputEventKey.new()
            event.physical_keycode = bindings[action]
            InputMap.action_add_event(action, event)

func _process(delta: float) -> void:
    if Input.is_action_just_pressed("toggle_pause"):
        GameState.toggle_pause()
    if Input.is_action_just_pressed("rotate_left"):
        yaw_target += deg_to_rad(90.0)
    if Input.is_action_just_pressed("rotate_right"):
        yaw_target -= deg_to_rad(90.0)
    camera_rig.rotation.y = lerp_angle(camera_rig.rotation.y, yaw_target, min(delta * 7.0, 1.0))
    camera.size = lerp(camera.size, zoom_target, min(delta * 8.0, 1.0))
    var pan := Vector3.ZERO
    pan.x = Input.get_axis("pan_left", "pan_right")
    pan.z = Input.get_axis("pan_up", "pan_down")
    if pan.length_squared() > 0.0:
        camera_rig.position += pan.normalized().rotated(Vector3.UP, camera_rig.rotation.y) * delta * 7.0
    _refresh_hud()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom_target = max(8.0, zoom_target - 1.5)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom_target = min(34.0, zoom_target + 1.5)

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("18202a")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("9ca8b8")
    env.ambient_light_energy = 0.75
    world_env.environment = env
    add_child(world_env)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -35, 0)
    light.light_energy = 1.3
    light.shadow_enabled = true
    add_child(light)

func _mat(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.82
    return m

func _box(name_: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = name_
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = _mat(color)
    mi.mesh = mesh
    mi.position = pos
    add_child(mi)
    return mi

func _build_office() -> void:
    _box("Floor", Vector3(0,-0.25,0), Vector3(18,0.5,14), Color("3d4654"))
    _box("BackWall", Vector3(0,1.5,-7), Vector3(18,3.5,0.3), Color("657181"))
    _box("LeftWall", Vector3(-9,1.5,0), Vector3(0.3,3.5,14), Color("596575"))
    for x in [-4.5, 0.0, 4.5]:
        _box("Desk", Vector3(x,0.55,-1.2), Vector3(2.7,0.18,1.1), Color("b4875d"))
        _box("Monitor", Vector3(x,1.15,-1.35), Vector3(0.9,0.65,0.12), Color("242b35"))
        _box("Chair", Vector3(x,0.45,0.1), Vector3(0.75,0.9,0.75), Color("2a313b"))
    for z in [-4.5,-2.7,-0.9,0.9,2.7,4.5]:
        _box("ServerRack", Vector3(7.2,1.0,z), Vector3(1.2,2.0,1.15), Color("232a33"))
    _build_person(Vector3(-4.5,0.0,0.0), Color("f0b85a"), Color("7b61ff"))
    _build_person(Vector3(0.0,0.0,0.0), Color("bd805f"), Color("2ed3c6"))
    _build_person(Vector3(4.5,0.0,0.0), Color("d99a73"), Color("ef8354"))

func _build_person(pos: Vector3, skin: Color, shirt: Color) -> void:
    var root := Node3D.new(); root.position = pos; add_child(root)
    var body := MeshInstance3D.new(); var bm := CapsuleMesh.new(); bm.radius=.32; bm.height=1.1; bm.material=_mat(shirt); body.mesh=bm; body.position.y=.78; root.add_child(body)
    var head := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius=.29; sm.height=.58; sm.material=_mat(skin); head.mesh=sm; head.position.y=1.62; root.add_child(head)

func _build_camera() -> void:
    camera_rig = Node3D.new(); camera_rig.name="CameraRig"; add_child(camera_rig)
    camera = Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=zoom_target
    camera.position=Vector3(0,16,18); camera.rotation_degrees=Vector3(-38,0,0); camera.current=true
    camera_rig.rotation.y=yaw_target; camera_rig.add_child(camera)

func _build_hud() -> void:
    var layer := CanvasLayer.new(); add_child(layer)
    var panel := ColorRect.new(); panel.color=Color(0.04,0.055,0.075,.92); panel.set_anchors_preset(Control.PRESET_TOP_WIDE); panel.offset_bottom=68; layer.add_child(panel)
    hud_label=Label.new(); hud_label.position=Vector2(22,20); hud_label.add_theme_font_size_override("font_size",20); panel.add_child(hud_label)
    var help:=Label.new(); help.text="WASD pan   Q/E rotate   wheel zoom   Space pause"; help.position=Vector2(22,680); help.add_theme_font_size_override("font_size",16); layer.add_child(help)

func _refresh_hud() -> void:
    if hud_label == null: return
    var state := "PAUSED" if GameState.paused else "RUNNING"
    hud_label.text = "$%s     COMPUTE %.0f%%     POWER %.0f%%     TRUST %.0f     SAFETY DEBT %.0f     %s" % [
        _money(GameState.cash), GameState.compute_used/GameState.compute_capacity*100.0,
        GameState.power_used/GameState.power_capacity*100.0, GameState.public_trust, GameState.safety_debt, state]

func _money(v: float) -> String:
    return "%d" % int(v)
