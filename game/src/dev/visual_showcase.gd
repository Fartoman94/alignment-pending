extends Node3D

## Dev-only visual validation scene (finalization pack's visual-overhaul
## brief, section 17): unlike asset_gallery.tscn's grid-of-everything
## inventory view, this composes a believable populated workspace — real
## furniture arrangement, a datacenter corner, scattered props, and all
## 10 character models standing together — as a single reference shot
## for "does the whole art direction read as one coherent place." Never
## reachable from any menu, excluded from the shipped export
## (export_presets.cfg's exclude_filter covers scenes/dev/**), same
## treatment as asset_gallery.tscn and tools/.

const MODELS := "res://assets/models"

func _ready() -> void:
    _build_environment()
    _build_room()
    _build_workstations()
    _build_meeting_area()
    _build_datacenter_corner()
    _build_props()
    _build_characters()
    _build_camera()

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("11151b")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("8c95a8")
    env.ambient_light_energy = 0.55
    world_env.environment = env
    add_child(world_env)
    var key_light := DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-55, -35, 0)
    key_light.light_color = Color("d8e4ff")
    key_light.light_energy = 1.2
    key_light.shadow_enabled = true
    add_child(key_light)
    var fill_light := DirectionalLight3D.new()
    fill_light.rotation_degrees = Vector3(-70, 140, 0)
    fill_light.light_color = Color("ffc98a")
    fill_light.light_energy = 0.35
    add_child(fill_light)

func _box(name_: String, pos: Vector3, size: Vector3, color: Color) -> void:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, size, color)
    mi.position = pos
    add_child(mi)

func _build_room() -> void:
    _box("Floor", Vector3(0, -0.25, 0), Vector3(22, 0.5, 16), Color("39352f"))
    _box("BackWall", Vector3(0, 1.5, -8), Vector3(22, 3.5, 0.3), Color("6b6355"))
    _box("LeftWall", Vector3(-11, 1.5, 0), Vector3(0.3, 3.5, 16), Color("5c554a"))
    _box("BackWallTrim", Vector3(0, 0.15, -7.83), Vector3(22, 0.3, 0.05), Color("d97b3f"))

func _model(path: String, pos: Vector3, y_rot_deg: float = 0.0) -> Node3D:
    var packed: PackedScene = load(path)
    if packed == null:
        push_error("visual_showcase: could not load %s" % path)
        return null
    var inst: Node3D = packed.instantiate()
    add_child(inst)
    inst.position = pos
    inst.rotation_degrees = Vector3(-90.0, y_rot_deg, 0.0)
    return inst

func _build_workstations() -> void:
    var xs: Array[float] = [-8.0, -5.0, -2.0, 1.0]
    for x in xs:
        _model("%s/furniture/desk_single.glb" % MODELS, Vector3(x, 0.0, -6.0))
        _model("%s/furniture/office_chair.glb" % MODELS, Vector3(x, 0.0, -4.8), 180.0)
        _model("%s/computers/monitor.glb" % MODELS, Vector3(x, 0.0, -6.0))
        _model("%s/computers/keyboard.glb" % MODELS, Vector3(x + 0.3, 0.0, -5.6))

func _build_meeting_area() -> void:
    _model("%s/furniture/meeting_table.glb" % MODELS, Vector3(5.0, 0.0, -5.0))
    _model("%s/furniture/office_chair.glb" % MODELS, Vector3(4.0, 0.0, -3.8), 180.0)
    _model("%s/furniture/office_chair.glb" % MODELS, Vector3(6.0, 0.0, -3.8), 180.0)
    _model("%s/furniture/bookshelf.glb" % MODELS, Vector3(8.5, 0.0, -7.5))
    _model("%s/furniture/filing_cabinet.glb" % MODELS, Vector3(7.5, 0.0, -7.5))
    _model("%s/furniture/divider_panel.glb" % MODELS, Vector3(2.5, 0.0, -5.0), 90.0)

func _build_datacenter_corner() -> void:
    var xs: Array[float] = [-9.5, -9.5, -9.5]
    var zs: Array[float] = [0.0, 1.5, 3.0]
    for i in xs.size():
        _model("%s/datacenter/server_rack.glb" % MODELS, Vector3(xs[i], 0.0, zs[i]))
    _model("%s/datacenter/ups.glb" % MODELS, Vector3(-9.5, 0.0, 4.5))
    _model("%s/datacenter/battery_cabinet.glb" % MODELS, Vector3(-9.5, 0.0, 5.8))
    _model("%s/datacenter/cooling_unit.glb" % MODELS, Vector3(-8.0, 0.0, 6.5))
    _model("%s/datacenter/cable_tray.glb" % MODELS, Vector3(-9.5, 2.5, 2.0))

func _build_props() -> void:
    _model("%s/props/plant.glb" % MODELS, Vector3(9.5, 0.0, 6.5))
    _model("%s/props/plant.glb" % MODELS, Vector3(-2.0, 0.0, 6.5))
    _model("%s/props/water_dispenser.glb" % MODELS, Vector3(6.0, 0.0, 6.5))
    _model("%s/props/trash_bin.glb" % MODELS, Vector3(1.0, 0.0, -4.0))
    _model("%s/props/trophy.glb" % MODELS, Vector3(8.5, 1.0, -7.6))
    _model("%s/props/mug.glb" % MODELS, Vector3(-8.0, 1.0, -6.0))
    _model("%s/props/cardboard_box.glb" % MODELS, Vector3(-10.5, 0.0, 7.0))
    _model("%s/computers/coffee_machine.glb" % MODELS, Vector3(4.0, 0.0, 6.5))
    _model("%s/computers/printer.glb" % MODELS, Vector3(2.0, 0.0, 6.5))

func _build_characters() -> void:
    var names: Array[String] = [
        "junior", "engineer", "researcher", "safety", "legal",
        "ops", "hr", "manager", "ceo", "cfo",
    ]
    for i in names.size():
        var row: int = i / 5
        var col: int = i % 5
        var x: float = -4.0 + float(col) * 2.0
        var z: float = -1.5 + float(row) * 2.2
        _model("%s/characters/%s.glb" % [MODELS, names[i]], Vector3(x, 0.0, z))

func _build_camera() -> void:
    var cam := Camera3D.new()
    add_child(cam)
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 20.0
    cam.look_at_from_position(Vector3(0.0, 16.0, 16.0), Vector3(-1.0, 0.0, 0.0), Vector3.UP)
    cam.current = true
