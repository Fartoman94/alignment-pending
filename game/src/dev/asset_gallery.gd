extends Node3D

## Dev-only visual QA scene (finalization pack's asset pack README asked
## for one): lays out every model in game/assets/models/ in a grid so the
## whole pack can be reviewed at a glance. Never reachable from any menu
## and excluded from the shipped export (export_presets.cfg's
## exclude_filter covers scenes/dev/**), same treatment as tools/.
##
## Corrects the pack's authored Z-up orientation the same way
## StaffAgent._build_visual() does (see that script's docstring for why
## — confirmed by actually rendering one and looking at the pixels, not
## assumed).

const MODEL_ROOT: String = "res://assets/models"
const SPACING: float = 2.0
const COLUMNS: int = 8

func _ready() -> void:
    var env: WorldEnvironment = WorldEnvironment.new()
    var e: Environment = Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.2, 0.2, 0.25)
    env.environment = e
    add_child(env)

    var light: DirectionalLight3D = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-50, -30, 0)
    add_child(light)

    var paths: Array[String] = _collect_glb_paths(MODEL_ROOT)
    paths.sort()
    for i in paths.size():
        var col: int = i % COLUMNS
        var row: int = i / COLUMNS
        var packed: PackedScene = load(paths[i])
        if packed == null:
            push_error("asset_gallery: failed to load %s" % paths[i])
            continue
        var inst: Node3D = packed.instantiate()
        inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        inst.position = Vector3(float(col) * SPACING, 0.0, float(row) * SPACING)
        add_child(inst)
        var label: Label3D = Label3D.new()
        label.text = paths[i].get_file().trim_suffix(".glb")
        label.position = Vector3(float(col) * SPACING, 2.2, float(row) * SPACING)
        label.font_size = 32
        label.pixel_size = 0.01
        add_child(label)

    var row_count: int = ceili(float(paths.size()) / float(COLUMNS))
    var cam: Camera3D = Camera3D.new()
    add_child(cam)
    var center: Vector3 = Vector3(float(COLUMNS - 1) * SPACING * 0.5, 1.0, float(row_count - 1) * SPACING * 0.5)
    cam.position = center + Vector3(0.0, 6.0, float(COLUMNS) * SPACING * 0.9)
    cam.look_at(center, Vector3.UP)
    cam.current = true

func _collect_glb_paths(dir_path: String) -> Array[String]:
    var results: Array[String] = []
    var dir: DirAccess = DirAccess.open(dir_path)
    if dir == null:
        return results
    dir.list_dir_begin()
    var entry: String = dir.get_next()
    while entry != "":
        var full_path: String = "%s/%s" % [dir_path, entry]
        if dir.current_is_dir():
            results.append_array(_collect_glb_paths(full_path))
        elif entry.ends_with(".glb"):
            results.append(full_path)
        entry = dir.get_next()
    dir.list_dir_end()
    return results
