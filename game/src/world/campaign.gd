extends Node3D

const AUTOSAVE_INTERVAL_SECONDS: float = 60.0

var camera_controller: CameraController
var hud: Hud
var _autosave_timer: Timer

func _ready() -> void:
    _ensure_input_actions()
    _build_environment()
    _build_office()
    _build_camera()
    _build_hud()
    _build_autosave_timer()
    SimClock.active = true

func _exit_tree() -> void:
    SimClock.active = false

func _ensure_input_actions() -> void:
    var bindings: Dictionary = {
        "toggle_pause": KEY_SPACE,
        "return_to_menu": KEY_ESCAPE,
    }
    for action: String in bindings:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        if InputMap.action_get_events(action).is_empty():
            var event: InputEventKey = InputEventKey.new()
            event.physical_keycode = bindings[action]
            InputMap.action_add_event(action, event)

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("toggle_pause"):
        GameState.toggle_pause()
    if Input.is_action_just_pressed("return_to_menu") and not SceneRouter.is_busy():
        var err: Error = SaveManager.autosave()
        if err != OK:
            push_warning("Campaign: autosave-on-exit failed (error %s)" % err)
        await SceneRouter.go_to("res://scenes/main_menu.tscn")
        return

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
    camera_controller = CameraController.new()
    camera_controller.name = "CameraController"
    add_child(camera_controller)

func _build_hud() -> void:
    var packed: PackedScene = load("res://scenes/hud.tscn")
    hud = packed.instantiate()
    add_child(hud)

func _build_autosave_timer() -> void:
    _autosave_timer = Timer.new()
    _autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
    _autosave_timer.autostart = true
    _autosave_timer.timeout.connect(_on_autosave_timeout)
    add_child(_autosave_timer)

func _on_autosave_timeout() -> void:
    var err: Error = SaveManager.autosave()
    if err != OK:
        push_warning("Campaign: periodic autosave failed (error %s)" % err)
