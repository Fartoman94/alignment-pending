extends Node3D

## Dev-only validation scene for the MEGA_ASSET_PACK integration
## (docs/art/MEGA_ASSET_INTEGRATION_REPORT.md): the pack's own
## `rooms/garage_room_assembled.glb` reference room, side by side with a
## few real StaffAgent instances cycling through each role's full
## character_model_pool — so the mesh variety added this pass (not just
## the existing skin/hair tint) is visible in one shot. Never reachable
## from any menu; excluded from the shipped export (export_presets.cfg's
## exclude_filter already covers scenes/dev/**).

const MODELS := "res://assets/models/mega"

func _ready() -> void:
    _build_environment()
    _build_navigation()
    _build_reference_room()
    _build_variant_row()
    _build_camera()

## A real NavigationRegion3D so the spawned StaffAgents' NavigationAgent3D
## has a valid map (same minimal setup as npc_showcase.gd) — none of them
## need to actually walk for this shot, but StaffAgent._ready() always
## creates one, so it needs somewhere valid to exist.
func _build_navigation() -> void:
    var nav_region := NavigationRegion3D.new()
    var navmesh := NavigationMesh.new()
    navmesh.vertices = PackedVector3Array([
        Vector3(-14.0, 0.0, -8.0), Vector3(14.0, 0.0, -8.0),
        Vector3(14.0, 0.0, 8.0), Vector3(-14.0, 0.0, 8.0),
    ])
    navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    nav_region.navigation_mesh = navmesh
    add_child(nav_region)

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("11151b")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("8c95a8")
    env.ambient_light_energy = 0.6
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

## The pack's own pre-assembled reference room — used here exactly as its
## own README suggests ("usar rooms/garage_room_assembled.glb como
## referencia rápida del start"), not swapped in for the live, buildable-
## grid-compatible garage (a single fused room mesh can't host the grid/
## nav/furniture-placement systems the real garage needs — see
## MEGA_ASSET_INTEGRATION_REPORT.md's scope note).
func _build_reference_room() -> void:
    var packed: PackedScene = load("%s/rooms/garage_room_assembled.glb" % MODELS)
    if packed == null:
        push_error("garage_showcase: could not load garage_room_assembled.glb")
        return
    var inst: Node3D = packed.instantiate()
    inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    inst.position = Vector3(-6.0, 0.0, 0.0)
    add_child(inst)
    var label := Label3D.new()
    label.text = "rooms/garage_room_assembled.glb (pack reference)"
    label.position = Vector3(-6.0, 5.0, 0.0)
    label.font_size = 28
    label.pixel_size = 0.01
    add_child(label)

## Real StaffAgents (same code path the actual campaign uses), one row
## per role that has a character_model_pool, each spawned 3x to show the
## real mesh picked from [character_model] + character_model_pool  in
## action — not a re-implementation, the exact same rng.randi() %
## candidates.size() pick StaffAgent._build_visual() makes in-game.
func _build_variant_row() -> void:
    var role_ids: Array = ["researcher", "engineer", "safety_analyst", "legal_specialist", "ceo"]
    for row in role_ids.size():
        var role_id: String = String(role_ids[row])
        var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)
        var label := Label3D.new()
        label.text = role_id
        label.position = Vector3(4.0, 2.2, -4.0 + float(row) * 2.2)
        label.font_size = 28
        label.pixel_size = 0.01
        add_child(label)
        for col in 4:
            var agent := StaffAgent.new()
            agent.name = "Variant_%s_%d" % [role_id, col]
            agent.character_model_path = String(role_def.get("character_model", ""))
            var pool: Array[String] = []
            for entry: Variant in (role_def.get("character_model_pool", []) as Array):
                pool.append(String(entry))
            agent.character_model_pool = pool
            agent.rng.seed = hash("%s_%d" % [role_id, col])
            agent.position = Vector3(4.0 + float(col) * 1.6, 0.0, -4.0 + float(row) * 2.2)
            add_child(agent)

func _build_camera() -> void:
    var cam := Camera3D.new()
    add_child(cam)
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 24.0
    cam.look_at_from_position(Vector3(2.0, 20.0, 20.0), Vector3(2.0, 1.0, -1.0), Vector3.UP)
    cam.current = true
