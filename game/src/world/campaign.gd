extends Node3D

const AUTOSAVE_INTERVAL_SECONDS: float = 60.0

var camera_controller: CameraController
var hud: Hud
var build_grid: BuildGrid
var build_controller: BuildController
var nav_region: NavigationRegion3D
var nav_coordinator: NavCoordinator
var _autosave_timer: Timer
var _staff_agents: Dictionary = {}

func _ready() -> void:
    _ensure_input_actions()
    _build_environment()
    _build_office()
    _build_camera()
    _build_grid_and_controller()
    _build_navigation()
    _build_hud()
    _build_autosave_timer()
    EventBus.build_tool_changed.connect(_on_build_tool_changed)
    EventBus.staff_roster_changed.connect(_sync_staff_agents)
    EventBus.task_assigned.connect(_on_task_assigned)
    EventBus.task_completed.connect(_on_task_completed)
    EventBus.task_unassigned.connect(_on_task_unassigned)
    EventBus.research_unlocked.connect(_on_research_unlocked)
    EventBus.ending_triggered.connect(_on_ending_triggered)
    build_controller.load_from_state(GameState.buildings)
    _sync_staff_agents()
    SimClock.active = true
    if EndingManager.has_ended():
        await SceneRouter.go_to("res://scenes/ending.tscn")

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
        if build_controller.mode != BuildController.Mode.NONE:
            build_controller.stop()
            EventBus.build_tool_changed.emit("")
            return
        var err: Error = SaveManager.autosave()
        if err != OK:
            push_warning("Campaign: autosave-on-exit failed (error %s)" % err)
        await SceneRouter.go_to("res://scenes/main_menu.tscn")
        return

func _on_build_tool_changed(tool_id: String) -> void:
    if tool_id.is_empty():
        build_controller.stop()
    elif tool_id == "sell":
        build_controller.start_sell()
    else:
        build_controller.start_place(tool_id)

func _on_task_assigned(staff_id: String, building_id: String, _target_id: String) -> void:
    if not _staff_agents.has(staff_id):
        return
    var pos: Vector3 = build_controller.building_position(building_id)
    (_staff_agents[staff_id] as StaffAgent).assign_work(pos)

func _on_task_completed(staff_id: String, _task_id: String, _target_id: String) -> void:
    _clear_staff_work(staff_id)

func _on_task_unassigned(staff_id: String) -> void:
    _clear_staff_work(staff_id)

func _on_research_unlocked(_node_id: String) -> void:
    # A "compute_bonus" unlock effect changes GameState.research_compute_bonus,
    # which only feeds into compute_capacity when infrastructure is recomputed.
    build_controller.recompute_infrastructure()

func _on_ending_triggered(_ending_id: String) -> void:
    var err: Error = SaveManager.autosave()
    if err != OK:
        push_warning("Campaign: autosave-on-ending failed (error %s)" % err)
    await SceneRouter.go_to("res://scenes/ending.tscn")

func _clear_staff_work(staff_id: String) -> void:
    if _staff_agents.has(staff_id):
        (_staff_agents[staff_id] as StaffAgent).clear_work()

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

## Office shell geometry (P39: routed through ProceduralMeshFactory
## instead of building BoxMesh/StandardMaterial3D inline).
func _box(name_: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, size, color)
    mi.position = pos
    add_child(mi)
    return mi

func _build_office() -> void:
    # An empty shell: the player builds everything else via BuildController.
    _box("Floor", Vector3(0,-0.25,0), Vector3(18,0.5,14), Color("3d4654"))
    _box("BackWall", Vector3(0,1.5,-7), Vector3(18,3.5,0.3), Color("657181"))
    _box("LeftWall", Vector3(-9,1.5,0), Vector3(0.3,3.5,14), Color("596575"))
    _build_ambient_decoration()

## Fixed, non-buildable set dressing (finalization-pack 3D asset pack) —
## deliberately placed in the margin between the walls and the buildable
## grid/navmesh (grid+navmesh both span roughly X:[-8,8] Z:[-6,6]; the
## floor extends to X:[-9,9] Z:[-7,7]), so nothing here can block a build
## cell or need a NavigationObstacle3D. Not a general prop-placement
## system (see KNOWN_ISSUES.md's "500 props" scope boundary) — just a
## few fixed pieces so the office reads as inhabited rather than an
## empty shell before the player has built anything.
func _build_ambient_decoration() -> void:
    _static_prop("res://assets/models/props/plant.glb", Vector3(-8.4, 0.0, -6.3))
    _static_prop("res://assets/models/props/plant.glb", Vector3(-8.4, 0.0, 2.5))
    _static_prop("res://assets/models/props/water_dispenser.glb", Vector3(-3.5, 0.0, -6.4))
    _static_prop("res://assets/models/props/trash_bin.glb", Vector3(3.5, 0.0, -6.4))

func _static_prop(model_path: String, pos: Vector3) -> void:
    var packed: PackedScene = load(model_path)
    if packed == null:
        push_error("Campaign: could not load decorative prop '%s'" % model_path)
        return
    var inst: Node3D = packed.instantiate()
    inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    inst.position = pos
    add_child(inst)

func _build_camera() -> void:
    camera_controller = CameraController.new()
    camera_controller.name = "CameraController"
    add_child(camera_controller)

func _build_grid_and_controller() -> void:
    build_grid = BuildGrid.new()
    build_grid.name = "BuildGrid"
    add_child(build_grid)
    build_controller = BuildController.new()
    build_controller.name = "BuildController"
    build_controller.grid = build_grid
    build_controller.camera = camera_controller.camera
    add_child(build_controller)

## Static navmesh covering the whole buildable floor. Buildings don't cut
## holes in it; they get NavigationObstacle3D avoidance instead (see
## BuildController._add_obstacle), which is much cheaper than re-baking
## the navmesh every time the player builds or sells something.
func _build_navigation() -> void:
    nav_region = NavigationRegion3D.new()
    nav_region.name = "NavRegion"
    var navmesh: NavigationMesh = NavigationMesh.new()
    var half_x: float = BuildGrid.GRID_COLS * BuildGrid.CELL_SIZE * 0.5
    var half_z: float = BuildGrid.GRID_ROWS * BuildGrid.CELL_SIZE * 0.5
    navmesh.vertices = PackedVector3Array([
        Vector3(-half_x, 0.0, -half_z),
        Vector3(half_x, 0.0, -half_z),
        Vector3(half_x, 0.0, half_z),
        Vector3(-half_x, 0.0, half_z),
    ])
    navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    nav_region.navigation_mesh = navmesh
    add_child(nav_region)
    nav_coordinator = NavCoordinator.new()

## Spawns/despawns a StaffAgent per current GameState.staff entry. Called on
## load and whenever StaffManager fires EventBus.staff_roster_changed.
func _sync_staff_agents() -> void:
    var current_ids: Dictionary = {}
    for member: Dictionary in GameState.staff:
        var staff_id: String = String(member.get("id", ""))
        if staff_id.is_empty():
            continue
        current_ids[staff_id] = true
        if not _staff_agents.has(staff_id):
            _spawn_staff_agent(staff_id)
    for staff_id: String in _staff_agents.keys():
        if not current_ids.has(staff_id):
            (_staff_agents[staff_id] as Node3D).queue_free()
            _staff_agents.erase(staff_id)

func _spawn_staff_agent(staff_id: String) -> void:
    var agent: StaffAgent = StaffAgent.new()
    agent.name = "Staff_%s" % staff_id
    agent.coordinator = nav_coordinator
    agent.bounds_min = Vector2(-7.0, -5.0)
    agent.bounds_max = Vector2(7.0, 5.0)
    var role_id: String = String(StaffManager.find(staff_id).get("role", ""))
    var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)
    agent.character_model_path = String(role_def.get("character_model", ""))
    agent.rng.randomize()
    agent.position = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-4.0, 4.0))
    add_child(agent)
    _staff_agents[staff_id] = agent
    # Restores the "walk to workstation and work" visual state for a staff
    # member who was already mid-task when the campaign was (re)loaded.
    var order: Dictionary = TaskManager.find_order_for_staff(staff_id)
    if not order.is_empty():
        var building_id: String = String(order.get("building_id", ""))
        agent.assign_work(build_controller.building_position(building_id))

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
