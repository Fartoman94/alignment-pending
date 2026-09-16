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
    # Rebuild the walls/trim/garage-door live when the player actually
    # moves — without this, RealEstateManager.move_to() would be correct
    # in data but visually silent until the next scene reload, which is
    # exactly the "impacte... visible" gap the brief calls out.
    EventBus.real_estate_moved.connect(_on_real_estate_moved)
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

## Visual overhaul pass: docs/design/ART_BIBLE.md's lighting section asks
## for "soft directional key + baked/SSIL-friendly ambient" plus, per the
## finalization pack's visual-overhaul brief, a natural cool key light
## alongside a warm interior fill so the office reads with some depth
## instead of one flat gray wash — measured with a before/after GPU
## profile (docs/performance/REAL_GPU_PROFILE.md) to confirm the extra
## light doesn't cost anything worth trading the improvement away for.
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
    # Natural key light — cool/blueish, as if daylight through the
    # BackWall windows (see _build_office()).
    var key_light := DirectionalLight3D.new()
    key_light.name = "KeyLight"
    key_light.rotation_degrees = Vector3(-55, -35, 0)
    key_light.light_color = Color("d8e4ff")
    key_light.light_energy = 1.2
    key_light.shadow_enabled = true
    add_child(key_light)
    # Warm interior fill — a soft amber counter-light from roughly where
    # ceiling office lighting would be, so surfaces facing away from the
    # key light aren't pure flat shadow.
    var fill_light := DirectionalLight3D.new()
    fill_light.name = "FillLight"
    fill_light.rotation_degrees = Vector3(-70, 140, 0)
    fill_light.light_color = Color("ffc98a")
    fill_light.light_energy = 0.35
    add_child(fill_light)

## Visual overhaul pass: the original shell was three blue-gray boxes
## (floor/back wall/left wall all within a few shades of each other) —
## exactly the "todo gris" / no-material-variety the brief called out.
## Same shell, same empty-until-the-player-builds-something design (an
## empty starting office is this project's own deliberate progression,
## docs/design/ART_BIBLE.md's "1. Cheap converted office" — not a bug to
## fix by pre-furnishing it), but now following the Art Bible's actual
## named palette (charcoal/warm gray/off-white base, a tech-blue and a
## brand-orange accent) instead of one undifferentiated blue-gray.
## Real estate progression (RealEstateManager, garage -> HQ) is presented
## here the same "palette + trim, not a layout change" way the visual-
## overhaul pass reworked office materials: the buildable grid/navmesh
## dimensions never change per tier (resizing them could strand already-
## placed buildings from an earlier tier outside a shrunk floor — a real
## correctness risk, not just a cosmetic one), but the walls' material and
## the garage-door prop are real, deterministic functions of
## GameState.current_building_id, so the move from a "cheap converted
## office" to a "corporate building" (Art Bible's own progression list)
## reads as a visible reward, not a purely numeric one.
var _office_visuals: Node3D

func _build_office() -> void:
    _office_visuals = Node3D.new()
    _office_visuals.name = "OfficeVisuals"
    add_child(_office_visuals)
    _rebuild_office_visuals()
    _build_ambient_decoration()

## Rebuildable subset (walls/trim/windows/garage-door) — everything that
## changes per real-estate tier lives under _office_visuals so a move can
## free and redraw just this, not the whole office (ambient decoration/
## grid/nav/staff are untouched by a move).
func _rebuild_office_visuals() -> void:
    for child in _office_visuals.get_children():
        child.queue_free()
    var tier: String = String(RealEstateManager.current_company_tier_def().get("id", "garage"))
    var palette: Dictionary = _office_palette(tier)
    _office_box("Floor", Vector3(0,-0.25,0), Vector3(18,0.5,14), palette["floor"])
    _office_box("BackWall", Vector3(0,1.5,-7), Vector3(18,3.5,0.3), palette["wall"])
    _office_box("LeftWall", Vector3(-9,1.5,0), Vector3(0.3,3.5,14), palette["wall_side"])
    # A baseboard trim along the back wall — a thin accent strip, not a
    # repaint, so it reads as a deliberate design choice. Brand orange
    # everywhere except the garage, which hasn't "earned" the brand color
    # yet — a plain safety-yellow strip instead (garages get hazard
    # stripes, not corporate trim).
    _office_box("BackWallTrim", Vector3(0,0.15,-6.83), Vector3(18,0.3,0.05), palette["trim"])
    # Two window "glow" panels on the back wall (an emissive material, no
    # real glass/transparency system needed) — cool-toned to sell
    # "natural light" per the brief's lighting direction, and to give
    # the back wall some silhouette variety instead of one flat plane.
    # Brighter at higher tiers (more/better windows a bigger lease buys).
    _office_window("BackWallWindowL", Vector3(-5.5, 2.0, -6.82), palette["window_energy"])
    _office_window("BackWallWindowR", Vector3(5.5, 2.0, -6.82), palette["window_energy"])
    if tier == "garage" or tier == "garage_plus":
        # A visible garage door on the left wall — the one concrete,
        # unmistakable "this is still the garage" signal the brief asks
        # for ("el garage inicial debe quedar como punto de partida
        # canon"), not just a slightly-different gray.
        _office_box("GarageDoor", Vector3(-8.85, 1.1, 4.5), Vector3(0.15, 2.2, 3.4), Color("2c2a28"))
        _office_box("GarageDoorTrim", Vector3(-8.8, 2.25, 4.5), Vector3(0.1, 0.12, 3.6), Color("d9c02e"))

func _on_real_estate_moved(_building_id: String, _bought: bool) -> void:
    _rebuild_office_visuals()

func _office_box(name_: String, pos: Vector3, size: Vector3, color: Color) -> void:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, size, color)
    mi.position = pos
    _office_visuals.add_child(mi)

## Garage: grungy concrete, no brand polish. Small/medium office: today's
## established warm-charcoal baseline (visual-overhaul pass). Premium/HQ:
## a visibly brighter, cleaner palette plus stronger window glow — the
## Art Bible's own "cheap converted office -> corporate building"
## progression, told entirely through material/lighting, no new geometry.
func _office_palette(tier: String) -> Dictionary:
    match tier:
        "garage", "garage_plus":
            return {
                "floor": Color("2e2b26"), "wall": Color("4a453d"), "wall_side": Color("423e37"),
                "trim": Color("d9c02e"), "window_energy": 0.25,
            }
        "premium_office", "hq_building":
            return {
                "floor": Color("403c33"), "wall": Color("827a6c"), "wall_side": Color("6f6759"),
                "trim": Color("d97b3f"), "window_energy": 1.0,
            }
        _:
            return {
                "floor": Color("39352f"), "wall": Color("6b6355"), "wall_side": Color("5c554a"),
                "trim": Color("d97b3f"), "window_energy": 0.6,
            }

func _office_window(name_: String, pos: Vector3, energy: float = 0.6) -> void:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, Vector3(3.2, 1.6, 0.06), Color("bfe3ff"))
    var mat: StandardMaterial3D = mi.mesh.surface_get_material(0)
    mat.emission_enabled = true
    mat.emission = Color("bfe3ff")
    mat.emission_energy_multiplier = energy
    mi.position = pos
    _office_visuals.add_child(mi)

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
