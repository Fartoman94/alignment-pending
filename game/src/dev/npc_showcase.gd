extends Node3D

## Dev-only validation scene for `34-ALIGNMENT-PENDING-REDISENO-NPCS.md`
## (NPC visual rework brief, section 14): unlike `visual_showcase.tscn`'s
## static populated-workspace shot, this exercises the *real* StaffAgent
## code path — same _build_visual()/_apply_variation()/_animate_visual()
## the actual game uses, same assign_work()/coordinator/NavigationAgent3D
## flow — so what's verified here is what ships, not a re-implementation
## of it. Never reachable from any menu; excluded from the shipped export
## (export_presets.cfg's exclude_filter already covers scenes/dev/**/
## src/dev/**).
##
## Layout (front-to-back rows, brief section 14's checklist):
##  Row 1 — one of each of the 10 roles, standing IDLE: role differentiation.
##  Row 2 — four instances of the SAME role (engineer), IDLE: per-instance
##          skin/hair variation, so a crowd of one role isn't identical clones.
##  Row 3 — three agents walking to and sitting at real desk_single.glb +
##          office_chair.glb models via the real assign_work() call: scale
##          vs. furniture, and the WORKING/"seated" pose, verified in place.
##  Row 4 — two agents left in their default IDLE->MOVING wander loop on a
##          real NavigationRegion3D: the walk cycle, seen in motion.

const MODELS := "res://assets/models"
const ALL_ROLES: Array[String] = [
    "junior", "engineer", "researcher", "safety", "legal",
    "ops", "hr", "manager", "ceo", "cfo",
]

var _nav_coordinator: NavCoordinator

func _ready() -> void:
    _build_environment()
    _build_room()
    _build_navigation()
    _build_role_row()
    _build_variation_row()
    _build_scale_test_row()
    _build_walk_row()
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
    _box("Floor", Vector3(0, -0.25, 0), Vector3(28, 0.5, 20), Color("39352f"))
    _box("BackWall", Vector3(0, 1.5, -10), Vector3(28, 3.5, 0.3), Color("6b6355"))

## Mirrors Campaign._build_navigation(): a single flat walkable polygon
## covering every row, plus a fresh NavCoordinator so Row 4's agents can
## really call try_reserve()/release() exactly like in-game staff do.
func _build_navigation() -> void:
    var nav_region := NavigationRegion3D.new()
    nav_region.name = "NavRegion"
    var navmesh := NavigationMesh.new()
    navmesh.vertices = PackedVector3Array([
        Vector3(-13.0, 0.0, -9.0),
        Vector3(13.0, 0.0, -9.0),
        Vector3(13.0, 0.0, 9.0),
        Vector3(-13.0, 0.0, 9.0),
    ])
    navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    nav_region.navigation_mesh = navmesh
    add_child(nav_region)
    _nav_coordinator = NavCoordinator.new()

## Spawns a real StaffAgent for `role_name` (one of ALL_ROLES) at `pos`,
## going straight to game/assets/models/characters/<role>.glb — 4 of the
## 10 pack roles (ceo/cfo/hr/legal) have no StaffRoleCatalog entry yet
## (no board/legal/HR gameplay system exists to attach them to — see
## docs/art/NPC_VISUAL_REWORK_REPORT.md), so this bypasses the catalog on
## purpose to still validate their models here.
func _spawn_agent(role_name: String, pos: Vector3) -> StaffAgent:
    var agent := StaffAgent.new()
    agent.name = "Agent_%s_%d" % [role_name, get_child_count()]
    agent.character_model_path = "%s/characters/%s.glb" % [MODELS, role_name]
    agent.coordinator = _nav_coordinator
    agent.bounds_min = Vector2(-12.0, -8.0)
    agent.bounds_max = Vector2(12.0, 8.0)
    agent.rng.randomize()
    agent.position = pos
    add_child(agent)
    return agent

func _label(text: String, pos: Vector3) -> void:
    var lbl := Label3D.new()
    lbl.text = text
    lbl.position = pos
    lbl.font_size = 32
    lbl.outline_size = 6
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(lbl)

func _build_role_row() -> void:
    _label("Row 1 — all 10 roles (IDLE)", Vector3(-9.0, 2.2, -6.5))
    for i in ALL_ROLES.size():
        var x: float = -9.0 + float(i) * 2.0
        _spawn_agent(ALL_ROLES[i], Vector3(x, 0.0, -6.0))

func _build_variation_row() -> void:
    _label("Row 2 — same role x4 (skin/hair variation)", Vector3(-3.0, 2.2, -3.5))
    for i in 4:
        var x: float = -3.0 + float(i) * 2.0
        _spawn_agent("engineer", Vector3(x, 0.0, -3.0))

## Real desk/chair models plus an agent that really walks over and really
## calls assign_work() — the same call Campaign._spawn_staff_agent() uses
## when a staff member starts a task — so the "seated" WORKING pose is
## checked against the real furniture, not an approximate stand-in scene.
func _build_scale_test_row() -> void:
    _label("Row 3 — desk/chair scale test (real assign_work)", Vector3(-6.0, 2.2, 0.5))
    var xs: Array[float] = [-6.0, -2.0, 2.0]
    var roles: Array[String] = ["researcher", "safety", "manager"]
    for i in xs.size():
        var x: float = xs[i]
        var desk_pos := Vector3(x, 0.0, 1.0)
        var packed_desk: PackedScene = load("%s/furniture/desk_single.glb" % MODELS)
        var desk: Node3D = packed_desk.instantiate()
        add_child(desk)
        desk.position = desk_pos
        desk.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        var packed_chair: PackedScene = load("%s/furniture/office_chair.glb" % MODELS)
        var chair: Node3D = packed_chair.instantiate()
        add_child(chair)
        chair.position = Vector3(x, 0.0, 2.2)
        chair.rotation_degrees = Vector3(-90.0, 180.0, 0.0)
        var packed_monitor: PackedScene = load("%s/computers/monitor.glb" % MODELS)
        var monitor: Node3D = packed_monitor.instantiate()
        add_child(monitor)
        monitor.position = desk_pos
        monitor.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        var agent: StaffAgent = _spawn_agent(roles[i], Vector3(x + 3.0, 0.0, 1.0))
        agent.assign_work(Vector3(x, 0.0, 1.8))

func _build_walk_row() -> void:
    _label("Row 4 — free wander (walk cycle)", Vector3(-2.0, 2.2, 4.5))
    _spawn_agent("junior", Vector3(-3.0, 0.0, 5.0))
    _spawn_agent("hr", Vector3(3.0, 0.0, 5.5))

func _build_camera() -> void:
    var cam := Camera3D.new()
    add_child(cam)
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 22.0
    cam.look_at_from_position(Vector3(0.0, 20.0, 18.0), Vector3(0.0, 0.0, -2.0), Vector3.UP)
    cam.current = true
