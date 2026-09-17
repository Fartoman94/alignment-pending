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
    # Garage vertical-slice recovery pass: 0.55 read as murky/underlit at
    # the closer camera zoom this pass also added — a real render showed
    # rooms and characters harder to read, not more atmospheric. Raised
    # just enough to keep depth (still real directional shadows below,
    # not flat) without washing anything toward "blancos quemados."
    env.ambient_light_energy = 0.7
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
    # key light aren't pure flat shadow. Energy raised alongside the
    # ambient bump above (0.35 -> 0.55) — the recovery brief specifically
    # asks for "luces interiores cálidas" to read as more than a hint;
    # confirmed by rendering that this doesn't overpower the cool key
    # light or blow out highlights.
    var fill_light := DirectionalLight3D.new()
    fill_light.name = "FillLight"
    fill_light.rotation_degrees = Vector3(-70, 140, 0)
    fill_light.light_color = Color("ffc98a")
    fill_light.light_energy = 0.55
    add_child(fill_light)

## Visual overhaul pass: the original shell was three blue-gray boxes
## (floor/back wall/left wall all within a few shades of each other) —
## exactly the "todo gris" / no-material-variety the brief called out.
## Same shell, now following the Art Bible's actual named palette
## (charcoal/warm gray/off-white base, a tech-blue and a brand-orange
## accent) instead of one undifferentiated blue-gray. The shell itself
## no longer starts empty — an earlier pass called that deliberate (Art
## Bible's "cheap converted office" framing), but a real screenshot of
## the actual running build showed it read as an unconvincing blockout,
## not a "humble start": no desks, no monitors, staff with nothing to do.
## MainMenu._seed_starting_workstations() now places 3 real desks and
## assigns the 3 starting hires to them before the campaign scene ever
## loads (garage vertical-slice recovery pass) — this function still
## only owns the walls/palette/tier-specific set dressing below, not the
## furniture, which is real GameState.buildings data like anything the
## player places.
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
## Production-kit city layer: a baked (render-once, not per-frame)
## SubViewport street scene shown through the office windows below —
## see CityBackdrop's own doc comment for the full "decorative, not a
## spatial city" scope statement. Lives outside _office_visuals (unlike
## the walls/windows it feeds) so a tier rebuild can free the old one and
## build a fresh one for the new tier before the windows that reference
## its texture are created, without fighting _office_visuals' own
## clear-all-children loop over the same node.
var _city_backdrop: CityBackdrop

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
    if _city_backdrop != null:
        _city_backdrop.queue_free()
    _city_backdrop = CityBackdrop.new()
    add_child(_city_backdrop)
    _city_backdrop.build_for_tier(tier)
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
    _office_window("BackWallWindowL", Vector3(-5.5, 2.0, -6.82), palette["window_energy"], _city_backdrop.get_texture())
    _office_window("BackWallWindowR", Vector3(5.5, 2.0, -6.82), palette["window_energy"], _city_backdrop.get_texture())
    if tier == "garage" or tier == "garage_plus":
        # Mega-asset-pack pass: a real modeled garage door (previously a
        # flat procedural box) — the one concrete, unmistakable "this is
        # still the garage" signal the brief asks for ("el garage inicial
        # debe quedar como punto de partida canon"), now real geometry
        # (ribbed panel) instead of a tinted rectangle. y_rot 90 turns its
        # authored width (local X) to run along the wall (world Z);
        # position/height matched to the door's own real AABB (2.45 tall).
        _office_model("res://assets/models/mega/architecture/garage/garage_door_closed.glb", "GarageDoor", Vector3(-8.85, 0.0, 4.5), 90.0)
        # A steel support column and a storage shelf — real set dressing
        # from the same pack, garage-only sizing/placement (KNOWN_ISSUES.md's
        # "not a general prop-placement system" still applies: fixed spots,
        # not a system).
        _office_model("res://assets/models/mega/architecture/garage/steel_beam.glb", "SteelBeam", Vector3(-6.0, 0.0, -5.5), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/storage_shelf.glb", "GarageStorageShelf", Vector3(8.3, 0.0, -6.6), 180.0)
        # Production-kit garage art pass: small "someone actually works
        # here" clutter in the same fixed-margin band the door/beam/shelf
        # above already use — a breaker panel and wall clock mounted on
        # the back wall, a toolbox next to the steel beam, a pallet and
        # stacked file boxes near the storage shelf, a standing fan and
        # trailing extension cord along the back wall, and a broom leaned
        # in the corner by the garage door. Garage/garage_plus only, same
        # as the rest of this block — cleared automatically on the next
        # _rebuild_office_visuals() call when the company moves out.
        _office_model("res://assets/models/mega/architecture/garage/breaker_panel.glb", "BreakerPanel", Vector3(6.5, 1.4, -6.85), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/wall_clock.glb", "WallClock", Vector3(-2.0, 2.3, -6.85), 0.0, true)
        _office_model("res://assets/models/mega/architecture/garage/toolbox.glb", "GarageToolbox", Vector3(-6.9, 0.0, -6.0), 20.0)
        _office_model("res://assets/models/mega/architecture/garage/pallet.glb", "GaragePallet", Vector3(7.5, 0.0, -3.2), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/file_box.glb", "GarageFileBox", Vector3(7.7, 0.0, 5.6), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/fan.glb", "GarageFan", Vector3(2.5, 0.0, -6.6), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/extension_cord.glb", "GarageExtensionCord", Vector3(0.5, 0.02, -6.6), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/broom.glb", "GarageBroom", Vector3(-8.6, 0.0, 2.8), 15.0)
    elif tier == "small_office" or tier == "medium_office":
        # Closes a real gap: garage/garage_plus and premium_office/
        # hq_building both got real entrance geometry (garage door, then
        # glass door + reception), but these two middle tiers had nothing
        # at all at this wall — a plain empty box with a palette change,
        # no unmistakable "you moved somewhere real" signal. A plain
        # office door (not the glass one premium/hq earn later) at the
        # same fixed spot the door has occupied at every other tier —
        # modest on purpose, matching "first real office, not fancy yet."
        _office_model("res://assets/models/mega/architecture/office/office_door.glb", "OfficeEntrance", Vector3(-8.85, 0.0, 4.5), 90.0)
    elif tier == "premium_office" or tier == "hq_building":
        # Production-kit office art pass: the Art Bible's "cheap converted
        # office -> corporate building" progression, same fixed-margin-band
        # dressing pattern the garage tier above uses, now for the top two
        # tiers — a real glass entrance (replacing the garage door's old
        # spot, same wall/position, so the entrance stays in the same
        # place across the whole progression), a lobby partition wall just
        # inside it, and two support columns flanking the back wall.
        _office_model("res://assets/models/mega/architecture/office/door_glass.glb", "OfficeEntrance", Vector3(-8.85, 0.0, 4.5), 90.0)
        _office_model("res://assets/models/mega/architecture/office/reception_wall.glb", "ReceptionWall", Vector3(-8.6, 0.0, 0.0), 90.0)
        _office_model("res://assets/models/mega/architecture/office/support_column.glb", "ColumnL", Vector3(-4.0, 0.0, -6.5), 0.0)
        _office_model("res://assets/models/mega/architecture/office/support_column.glb", "ColumnR", Vector3(4.0, 0.0, -6.5), 0.0)

func _on_real_estate_moved(_building_id: String, _bought: bool) -> void:
    _rebuild_office_visuals()

func _office_box(name_: String, pos: Vector3, size: Vector3, color: Color) -> void:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, size, color)
    mi.position = pos
    _office_visuals.add_child(mi)

## Loads a real mega-asset-pack model into _office_visuals, correcting its
## authored Z-up orientation the same way every other real model in this
## project does (StaffAgent/BuildController/visual_showcase.gd), with an
## optional y_rot_deg to turn a wall-mounted piece to face the right way.
## The facing rotation is a SEPARATE outer wrapper around the Z-up-
## correction node, not one combined Vector3(-90, y, 0) — composing both
## into a single Euler triple doesn't commute the way a naive reading
## suggests (confirmed by rendering: a combined rotation warped the
## garage door instead of just turning it to face into the room), so
## each rotation gets its own node, same nested-transform discipline
## StaffAgent's VisualRoot already uses for its own correction.
## flat_wall_mount: most mega-asset-pack pieces are authored to stand on
## the floor (local Z-up, corrected to Y-up by the standard -90° X below),
## but a handful of flat wall-mounted pieces (confirmed by rendering:
## wall_clock) are authored lying face-up instead, like a disc on a
## table — the standard correction rotates their face to point at the
## ceiling, not into the room. Those need no correction at all: their
## local +Z (face normal) and +Y (in-face "up") already match world Z/Y
## once placed with no rotation.
func _office_model(path: String, name_: String, pos: Vector3, y_rot_deg: float = 0.0, flat_wall_mount: bool = false) -> void:
    var packed: PackedScene = load(path)
    if packed == null:
        push_error("Campaign: could not load office model '%s'" % path)
        return
    var facing: Node3D = Node3D.new()
    facing.name = name_
    facing.position = pos
    facing.rotation_degrees = Vector3(0.0, y_rot_deg, 0.0)
    _office_visuals.add_child(facing)
    var inst: Node3D = packed.instantiate()
    if not flat_wall_mount:
        inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    facing.add_child(inst)

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

## city_texture (CityBackdrop's baked, render-once viewport texture) is
## used as albedo (so the skyline reads under normal scene lighting) plus
## a much-dimmed emission of the same texture (just enough to still read
## as "a lit window" from across the room the way the old flat-color
## glow did, at low ambient light). CITY_EMISSION_SCALE is small and
## deliberate: the backdrop scene's own materials are mostly light/pastel
## (white building facades, pale sidewalk) — confirmed by rendering the
## raw baked texture in isolation — so using it as emission at the same
## multiplier the old flat "bfe3ff" color used way overexposes the whole
## window to solid white. The flat emissive color stays as a fallback
## fill so the window doesn't just go dark before city_texture is ready
## (SubViewport rendering is a frame or two behind window creation).
const CITY_EMISSION_SCALE: float = 0.12
func _office_window(name_: String, pos: Vector3, energy: float = 0.6, city_texture: Texture2D = null) -> void:
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(name_, Vector3(3.2, 1.6, 0.06), Color("bfe3ff"))
    var mat: StandardMaterial3D = mi.mesh.surface_get_material(0)
    mat.emission_enabled = true
    mat.emission = Color("bfe3ff")
    mat.emission_energy_multiplier = energy
    if city_texture != null:
        mat.albedo_texture = city_texture
        mat.emission_texture = city_texture
        mat.emission_energy_multiplier = energy * CITY_EMISSION_SCALE
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
    _build_break_room()

## Production-kit pass: a break-room corner staff can actually walk to
## (see BREAK_SPOT / StaffAgent.break_spot), unlike every other ambient
## prop above — those live in the unwalkable margin outside the navmesh
## on purpose (KNOWN_ISSUES.md), which also makes them impossible to use
## as a real destination. BuildGrid.ROUTE_ROW (world z in [0,2], the full
## east-west aisle every staff member must already be able to cross) is
## the one strip of floor guaranteed walkable and guaranteed never
## buildable regardless of tier — placed in its western end so the rest
## of the aisle stays clear. Tier-agnostic like the rest of this
## function: every office, not just the garage, gets a break corner.
const BREAK_SPOT: Vector3 = Vector3(-6.1, 0.0, 1.0)
func _build_break_room() -> void:
    _static_prop("res://assets/models/mega/kitchen/fridge.glb", Vector3(-7.6, 0.0, 0.35), 90.0)
    _static_prop("res://assets/models/mega/kitchen/vending_machine.glb", Vector3(-7.6, 0.0, 1.7), -90.0)
    _static_prop("res://assets/models/mega/kitchen/coffee_machine.glb", Vector3(-6.6, 0.0, 1.75), 180.0)
    _static_prop("res://assets/models/mega/kitchen/table.glb", Vector3(-5.6, 0.0, 1.0), 0.0)
    _static_prop("res://assets/models/mega/kitchen/chair.glb", Vector3(-5.6, 0.0, 0.25), 180.0)

## y_rot_deg gets its own outer wrapper node around the pack's standard
## -90 X correction, same reason _office_model() does this instead of one
## combined Euler triple (see that function's doc comment) — confirmed
## necessary again here, not just assumed to carry over.
func _static_prop(model_path: String, pos: Vector3, y_rot_deg: float = 0.0) -> void:
    var packed: PackedScene = load(model_path)
    if packed == null:
        push_error("Campaign: could not load decorative prop '%s'" % model_path)
        return
    var facing: Node3D = Node3D.new()
    facing.position = pos
    facing.rotation_degrees = Vector3(0.0, y_rot_deg, 0.0)
    add_child(facing)
    var inst: Node3D = packed.instantiate()
    inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    facing.add_child(inst)

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
    agent.has_break_spot = true
    agent.break_spot = BREAK_SPOT
    var role_id: String = String(StaffManager.find(staff_id).get("role", ""))
    var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)
    agent.character_model_path = String(role_def.get("character_model", ""))
    var pool: Array[String] = []
    for entry: Variant in (role_def.get("character_model_pool", []) as Array):
        pool.append(String(entry))
    agent.character_model_pool = pool
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
