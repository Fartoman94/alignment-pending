extends Node3D

const AUTOSAVE_INTERVAL_SECONDS: float = 60.0

## GIGA_GRAPHICS pass: a real glowing-screen material for any prop mesh
## part named "display_*" (monitor.glb/laptop.glb's convention, confirmed
## by inspecting their node trees — a separate mesh from the bezel/base
## parts). One shared ShaderMaterial instance, safe to reuse everywhere
## since nothing overrides its uniforms per-instance.
const _SCREEN_SHADER: Shader = preload("res://src/shaders/screen_emission.gdshader")
var _screen_glow_material: ShaderMaterial

var camera_controller: CameraController
var hud: Hud
var build_grid: BuildGrid
var build_controller: BuildController
var nav_region: NavigationRegion3D
var nav_coordinator: NavCoordinator
var _autosave_timer: Timer
var _staff_agents: Dictionary = {}

## VISUAL_OVERHAUL pass: promoted from local vars so the live day-night
## update (_update_time_of_day(), driven from _process()) can update
## rotation/color/energy every frame instead of only at scene build time.
var _environment: Environment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
## VISUAL_OVERHAUL pass: the two BackWallWindow panels' materials, so
## _update_time_of_day() can dim/warm them with the sun instead of the
## fixed "always daytime" glow they had before — otherwise the only
## visible cue of the outside world stays static while the sun/interior
## lights change, and night stopped reading as meaningfully different
## from dusk (confirmed by rendering both and comparing average floor
## color — the interior fill light alone wasn't enough of a tell).
## {material: StandardMaterial3D, base_energy: float} per window, keyed
## by the tier's own window_energy from _office_palette() (the "how good
## is this office's glazing" signal) so the day-night scale multiplies
## that instead of overriding it.
var _window_materials: Array[Dictionary] = []

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
    _update_time_of_day()
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
## GIGA_GRAPHICS pass ("se ve demasiado mal, mejorá los gráficos y los
## colores" — direct user feedback on a real screenshot of the live
## build): the previous settings used Godot's default TONE_MAPPER_LINEAR
## with no exposure control, which has no highlight rolloff — stacked
## with 3 light sources (ambient + key + fill) all landing in the same
## bright range, every mid-to-light material (the mega-pack furniture's
## own albedos are legitimately light — confirmed by dumping desk_single/
## office_chair's actual StandardMaterial3D.albedo_color, not guessed —
## a warm tan desktop at (0.85, 0.73, 0.59), a blue-gray chair at
## (0.50, 0.54, 0.60)) got pushed toward flat, undifferentiated white.
## Switching to TONE_MAPPER_FILMIC (smooth highlight compression instead
## of hard clipping) + a lower tonemap_exposure + a real saturation/
## contrast boost via adjustment_* recovers the color separation that
## was already in the materials but not surviving the render pipeline.
## Confirmed by rendering 3 variants (lower ambient alone; + glow; +
## tuned exposure/key color) side by side before picking this one — the
## final version visibly shows staff role-color clothing, a warm brown
## floor against cool gray walls, and real contact shadows under desks/
## characters that were nearly invisible before.
func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("11151b")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("8c95a8")
    env.ambient_light_energy = 0.4
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 0.85
    env.adjustment_enabled = true
    env.adjustment_saturation = 1.35
    env.adjustment_contrast = 1.15
    env.adjustment_brightness = 1.0
    # A soft, cheap bloom on emissive surfaces (monitor/laptop screens,
    # the office windows' city-backdrop glow).
    env.glow_enabled = true
    env.glow_intensity = 0.6
    env.glow_bloom = 0.08
    env.glow_strength = 1.0
    env.glow_hdr_threshold = 1.0
    # VISUAL_OVERHAUL pass, priority 1: SSAO/SSIL/SDFGI need Forward+
    # (confirmed unavailable under gl_compatibility by reading Godot's own
    # RenderingServer docs, then verified live by rendering both ways) —
    # project.godot was switched to forward_plus for this reason (see
    # docs/performance/REAL_GPU_PROFILE.md for the before/after cost).
    # Values tuned by rendering the garage scene at each step, not copied
    # from the bundle template: SSAO catches contact shadows under desks/
    # crates that the single key+fill light pair leaves flat; SSIL bounces
    # a little of the warm fill color back into corners; SDFGI stayed off
    # — on the 150-staff stress scenario it cost ~9 more FPS than SSAO+SSIL
    # combined for a difference barely visible in this box-shaped interior.
    env.ssao_enabled = true
    env.ssao_radius = 1.2
    env.ssao_intensity = 1.8
    env.ssao_power = 1.5
    env.ssil_enabled = true
    env.ssil_radius = 3.0
    env.ssil_intensity = 1.4
    # CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 4 ("fog sutil"): first
    # attempt at 0.008 was rendered and rejected — in this small enclosed
    # room (14x10 units) it visibly washed out the SSAO contact shadows
    # and desaturated the whole floor into flat gray (confirmed by a
    # direct before/after pixel comparison, not eyeballed). 0.0015 is the
    # value that actually reads as "atmosphere" rather than "smoke" at
    # the same camera distance. Color/energy tracked by _update_time_of_
    # day() alongside ambient, same day-night reactivity.
    env.fog_enabled = true
    env.fog_density = 0.0015
    env.fog_sun_scatter = 0.03
    world_env.environment = env
    add_child(world_env)
    _environment = env
    # Natural key light — cool/blueish, as if daylight through the
    # BackWall windows (see _build_office()). Rotation/color/energy are
    # then driven live every frame by _update_time_of_day() using the
    # real GameState.calendar_hour/calendar_minute clock, so the values
    # set here are just the initial pose before the first update.
    var key_light := DirectionalLight3D.new()
    key_light.name = "KeyLight"
    key_light.rotation_degrees = Vector3(-55, -35, 0)
    key_light.light_color = Color("f0e8ff")
    key_light.light_energy = 1.35
    key_light.shadow_enabled = true
    add_child(key_light)
    _key_light = key_light
    # Warm interior fill — a soft amber counter-light from roughly where
    # ceiling office lighting would be, so surfaces facing away from the
    # key light aren't pure flat shadow.
    var fill_light := DirectionalLight3D.new()
    fill_light.name = "FillLight"
    fill_light.rotation_degrees = Vector3(-70, 140, 0)
    fill_light.light_color = Color("ffc98a")
    fill_light.light_energy = 0.5
    add_child(fill_light)
    _fill_light = fill_light
    _update_time_of_day()

## VISUAL_OVERHAUL pass, priority 2: sun/day-night cycle wired to the
## REAL simulation clock (GameState.calendar_hour/calendar_minute, ticked
## by SimClock/EventBus.simulation_tick) instead of a disconnected parallel
## clock — the bundle's own TIME_OF_DAY_CONTROLLER.gd template runs its own
## @export game_hour driven by _process(delta), which would drift from the
## calendar shown in the HUD and from day_advanced-gated systems (district
## drift, board pressure, etc). Reading GameState directly keeps one source
## of truth. At the default sim speed a full day is ~288 real seconds (5
## sim-minutes per real second, per SimClock.SIM_MINUTES_PER_TICK), so
## polling every rendered frame is smooth with no interpolation needed.
func _update_time_of_day() -> void:
    if not _key_light or not _fill_light or not _environment:
        return
    var hour: float = float(GameState.calendar_hour) + float(GameState.calendar_minute) / 60.0
    # Single sine period over 24h, peaking at solar noon (hour=12) and
    # troughing at solar midnight (hour=0/24). -1..1.
    var elevation: float = sin(PI * (hour - 6.0) / 12.0)
    var day_t: float = clampf((elevation + 1.0) * 0.5, 0.0, 1.0)
    # Godot's DirectionalLight3D shines along local -Z; rotating -90 on X
    # points it straight down (sun at zenith), +90 points it straight up
    # (below the horizon, no useful light) — confirmed by rendering both
    # extremes before picking this mapping.
    _key_light.rotation_degrees = Vector3(lerpf(90.0, -90.0, day_t), -35.0, 0.0)
    _key_light.light_color = _sun_color(hour)
    _key_light.light_energy = lerpf(0.05, 1.5, smoothstep(0.0, 0.18, day_t))
    _key_light.shadow_enabled = day_t > 0.03
    # Interior fill reads as "office lights on" — dims a touch under bright
    # midday sun, brightens a bit after dark, but stays modest: confirmed
    # by rendering that a full 0.75 night value (vs. day's 0.4) made
    # night barely distinguishable from dusk, since the fill alone was
    # carrying most of the room's brightness regardless of the sun.
    _fill_light.light_energy = lerpf(0.55, 0.4, day_t)
    _environment.ambient_light_energy = lerpf(0.1, 0.4, day_t)
    _environment.ambient_light_color = Color("8c95a8").lerp(Color("232838"), 1.0 - day_t)
    _environment.tonemap_exposure = lerpf(0.62, 0.85, day_t)
    _environment.fog_light_color = Color("8c95a8").lerp(Color("161a26"), 1.0 - day_t)
    # The window panels' only light cue was a fixed "always daytime" glow
    # (see _office_window()) — scaled by day_t too so the outside world
    # visibly goes dark along with the sun instead of staying a static
    # bright rectangle all night.
    var window_scale: float = lerpf(0.35, 1.0, day_t)
    for entry: Dictionary in _window_materials:
        var mat: StandardMaterial3D = entry["material"]
        mat.emission_energy_multiplier = float(entry["base_energy"]) * window_scale

func _sun_color(hour: float) -> Color:
    # Deep blue night -> warm dawn/dusk -> cool-white midday, matching the
    # established key-light palette (f0e8ff) at noon.
    if hour < 5.0 or hour >= 20.0:
        return Color("2c3350")
    if hour < 7.5:
        return Color("2c3350").lerp(Color("ffb27a"), inverse_lerp(5.0, 7.5, hour))
    if hour < 9.5:
        return Color("ffb27a").lerp(Color("f0e8ff"), inverse_lerp(7.5, 9.5, hour))
    if hour < 16.5:
        return Color("f0e8ff")
    if hour < 18.5:
        return Color("f0e8ff").lerp(Color("ff9d5c"), inverse_lerp(16.5, 18.5, hour))
    return Color("ff9d5c").lerp(Color("2c3350"), inverse_lerp(18.5, 20.0, hour))

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
    _build_exterior()

## World+NPC overhaul pass: the room only ever built two of its four
## walls (BackWall at z=-7, LeftWall at x=-9 — the other two sides were
## always open, on purpose, so the isometric camera could see in). That
## meant looking past those open sides, or over the low walls' top edge,
## showed nothing but the flat WorldEnvironment background color — "el
## alrededor del garage no puede ser negro vacío" per the brief. A real
## exterior set (sidewalk, street, trees, lamps, a couple of building
## silhouettes, a few cars driving a simple back-and-forth loop) placed
## just past the floor's own edge (|x|>9 or z>7) — not a spatial city to
## explore, a backdrop to look at, same "decorative, low-cost" scope the
## earlier CityBackdrop window pass used. Tier-independent (built once,
## never rebuilt on a real-estate move) since it's not part of the
## office itself.
func _build_exterior() -> void:
    var ext := Node3D.new()
    ext.name = "Exterior"
    add_child(ext)
    var city := "res://assets/models/mega/architecture/city/"
    # The city pack's building-exterior models are authored at a much
    # bigger scale than the room-scale furniture pack everything else in
    # this scene uses — confirmed by pulling a real perspective camera
    # back far enough to compare them side by side with the office box:
    # unscaled, a single building dwarfed the whole room. The game's
    # camera is orthogonal (no perspective falloff with distance), so
    # placing them further away doesn't shrink them on screen the way it
    # would with a normal 3D camera — scale is the only lever that works.
    var _ext_model := func(path: String, pos: Vector3, y_rot: float = 0.0, model_scale: float = 1.0) -> void:
        var packed: PackedScene = load(path)
        if packed == null:
            push_error("Campaign: could not load exterior model '%s'" % path)
            return
        var facing := Node3D.new()
        facing.position = pos
        facing.rotation_degrees = Vector3(0.0, y_rot, 0.0)
        ext.add_child(facing)
        var inst: Node3D = packed.instantiate()
        inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        inst.scale = Vector3.ONE * model_scale
        facing.add_child(inst)

    # Sidewalk running the width of the building just past the open
    # front edge (z=7), then a street beyond that, both spanning the
    # same x range the floor does. World+NPC overhaul pass's traffic
    # shared one line in both directions — two ping-pong movers on the
    # same line inevitably pass through each other eventually (it's a
    # bounded 1D path both traverse forever, not a one-shot crossing).
    # Total-rework pass ("Path3D por carril, dirección separada... sin
    # colisiones absurdas"): 3 separate lane rows, one vehicle each, so
    # no two vehicles ever share a line by construction.
    for i in 9:
        var sx: float = -8.0 + float(i) * 2.0
        _ext_model.call(city + "sidewalk_tile.glb", Vector3(sx, 0.0, 8.0), 0.0)
        _ext_model.call(city + "road_straight.glb", Vector3(sx, 0.0, 9.3), 0.0)
        _ext_model.call(city + "road_straight.glb", Vector3(sx, 0.0, 10.5), 0.0)
        _ext_model.call(city + "road_straight.glb", Vector3(sx, 0.0, 11.7), 0.0)
    # Trees and lamp posts along the sidewalk, alternating so it doesn't
    # read as a single repeated prop.
    _ext_model.call(city + "tree_city.glb", Vector3(-7.0, 0.0, 8.3), 0.0)
    _ext_model.call(city + "lamp_post.glb", Vector3(-3.5, 0.0, 8.3), 0.0)
    _ext_model.call(city + "tree_city.glb", Vector3(0.0, 0.0, 8.3), 0.0)
    _ext_model.call(city + "lamp_post.glb", Vector3(3.5, 0.0, 8.3), 0.0)
    _ext_model.call(city + "tree_city.glb", Vector3(7.0, 0.0, 8.3), 0.0)
    _ext_model.call(city + "park_bench.glb", Vector3(-5.0, 0.0, 8.3), 90.0)
    # A small skyline set back across the street — enough to read as "a
    # real block", not a single flat backdrop card. Scaled down ~4-5x
    # from native (see _ext_model's doc comment) — verified by rendering
    # a real perspective overview alongside the office box before
    # picking this factor, not guessed.
    _ext_model.call(city + "small_building_exterior.glb", Vector3(-6.0, 0.0, 14.0), 0.0, 0.22)
    _ext_model.call(city + "mid_building_exterior.glb", Vector3(-1.5, 0.0, 14.5), 0.0, 0.22)
    _ext_model.call(city + "small_building_exterior.glb", Vector3(3.5, 0.0, 14.0), 0.0, 0.22)
    # tower.glb removed here (audit pass): at the same 0.22 scale every
    # other exterior building uses, it rendered as a massive, flat,
    # incorrectly-shaded gray shape filling most of the screen from the
    # real default gameplay camera — confirmed by isolating it (removing
    # just this one placement made the artifact disappear entirely, nothing
    # else changed) and by checking its raw AABB against the other 3
    # buildings (size/pivot both look structurally normal, so this isn't a
    # simple scale-or-pivot miscalculation this pass could safely re-tune
    # blind). hq_building_exterior + 2x small + mid already read as a full
    # block without it — see docs/production/KNOWN_ISSUES.md.

    # One vehicle per lane, own dedicated line each — guarantees no two
    # ever occupy the same line, unlike the single-shared-line version
    # the world+NPC overhaul pass shipped. Lanes 1/3 run the same
    # direction (a real street can have same-direction lanes); lane 2
    # runs the opposite way, so both travel directions are represented.
    _spawn_traffic(Vector3(-9.0, 0.15, 9.3), Vector3(9.0, 0.15, 9.3), 2.6, "res://assets/models/mega/architecture/city/car_blue.glb", ext)
    _spawn_traffic(Vector3(7.0, 0.15, 10.5), Vector3(-8.0, 0.15, 10.5), 3.4, "res://assets/models/mega/architecture/city/car_orange.glb", ext)
    _spawn_traffic(Vector3(-4.0, 0.15, 11.7), Vector3(6.0, 0.15, 11.7), 2.1, "res://assets/models/mega/architecture/city/delivery_van.glb", ext)
    # CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 5 ("autos estacionados",
    # distinct from "autos/van en movimiento" above): 2 real, static
    # (non-moving, no TrafficVehicle) cars along the far curb, past the
    # 3 traffic lanes and in front of the background buildings — the
    # pack ships no dedicated "parked car" model, so these reuse the
    # same car_blue/car_orange meshes the moving lanes already use, just
    # placed once and never animated.
    _ext_model.call(city + "car_blue.glb", Vector3(-2.5, 0.15, 13.0), 90.0)
    _ext_model.call(city + "car_orange.glb", Vector3(2.0, 0.15, 13.0), -90.0)

func _spawn_traffic(from_pos: Vector3, to_pos: Vector3, speed: float, model_path: String, parent: Node3D) -> void:
    var vehicle := TrafficVehicle.new()
    vehicle.start_pos = from_pos
    vehicle.end_pos = to_pos
    vehicle.speed = speed
    var packed: PackedScene = load(model_path)
    if packed == null:
        push_error("Campaign: could not load traffic model '%s'" % model_path)
        return
    var inst: Node3D = packed.instantiate()
    inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    vehicle.add_child(inst)
    parent.add_child(vehicle)

## Rebuildable subset (walls/trim/windows/garage-door) — everything that
## changes per real-estate tier lives under _office_visuals so a move can
## free and redraw just this, not the whole office (ambient decoration/
## grid/nav/staff are untouched by a move).
func _rebuild_office_visuals() -> void:
    for child in _office_visuals.get_children():
        child.queue_free()
    _window_materials.clear()
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
        _office_model("res://assets/models/mega/architecture/garage/steel_beam.glb", "SteelBeam", Vector3(-6.0, 0.0, -5.5), 0.0, false, 0.35)
        _office_model("res://assets/models/mega/architecture/garage/storage_shelf.glb", "GarageStorageShelf", Vector3(8.3, 0.0, -6.6), 180.0, false, 0.9)
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
        # Garage vertical-slice recovery pass ("garage debe ocupar ~70%
        # del área jugable, no colocar objetos al azar — cada objeto debe
        # tener función visual o narrativa"): dressing around the 3 real
        # starter desks (MainMenu._seed_starting_workstations(), grid
        # cells (2,1)/(3,1)/(4,1) = world x -3/-1/1, z -3) — a chair,
        # monitor and mug at each, a desktop tower at two of the three
        # and a laptop at the third for variety, a whiteboard "planning
        # wall" near the back-left corner, and a sofa+coffee table "mini
        # lounge" at the opposite end of the route row from the existing
        # break room. Purely decorative like the rest of this block (not
        # registered in BuildGrid._occupied) — same scope boundary
        # KNOWN_ISSUES.md already documents for ambient decoration.
        _office_model("res://assets/models/mega/furniture/office_chair.glb", "Desk1Chair", Vector3(-3.0, 0.0, -2.3), 180.0)
        _office_model("res://assets/models/mega/computers/monitor.glb", "Desk1Monitor", Vector3(-3.0, 0.75, -3.3), 180.0)
        _office_model("res://assets/models/mega/computers/desktop_tower.glb", "Desk1Tower", Vector3(-3.5, 0.0, -3.0), 0.0)
        _office_model("res://assets/models/mega/props/mug.glb", "Desk1Mug", Vector3(-2.6, 0.75, -3.3), 0.0)
        _office_model("res://assets/models/mega/furniture/office_chair.glb", "Desk2Chair", Vector3(-1.0, 0.0, -2.3), 180.0)
        _office_model("res://assets/models/mega/computers/monitor.glb", "Desk2Monitor", Vector3(-1.0, 0.75, -3.3), 180.0)
        _office_model("res://assets/models/mega/computers/laptop.glb", "Desk2Laptop", Vector3(-0.5, 0.75, -3.3), 180.0)
        _office_model("res://assets/models/mega/furniture/office_chair.glb", "Desk3Chair", Vector3(1.0, 0.0, -2.3), 180.0)
        _office_model("res://assets/models/mega/computers/monitor.glb", "Desk3Monitor", Vector3(1.0, 0.75, -3.3), 180.0)
        _office_model("res://assets/models/mega/computers/desktop_tower.glb", "Desk3Tower", Vector3(1.5, 0.0, -3.0), 0.0)
        _office_model("res://assets/models/mega/props/mug.glb", "Desk3Mug", Vector3(1.4, 0.75, -3.3), 0.0)
        _office_model("res://assets/models/mega/furniture/whiteboard_stand.glb", "PlanningWhiteboard", Vector3(-7.0, 0.0, -4.5), 90.0, false, 0.5)
        # Radii checked against LOUNGE_SPOT (Vector3(6.0, 0.0, 0.6),
        # below) by distance MINUS the nav agent's own radius (0.3, see
        # StaffAgent._ready()) — the first pass at these numbers only
        # checked raw distance-to-obstacle-center and missed that the
        # agent's own body also needs clearance, which made LOUNGE_SPOT
        # literally unreachable (caught by a real instrumented run: the
        # agent stalled 0.35 units short of the target forever, just
        # outside its own 0.3 arrival tolerance). LoungeTable sits only
        # 0.3 from the spot by design (the agent is meant to end up right
        # next to it) — too close for any obstacle at all, so it gets
        # none, same as before this pass.
        _office_model("res://assets/models/mega/furniture/sofa_two_seat.glb", "LoungeSofa", Vector3(6.0, 0.0, 1.5), 180.0, false, 0.45)
        _office_model("res://assets/models/mega/furniture/coffee_table.glb", "LoungeTable", Vector3(6.0, 0.0, 0.3), 0.0)
        _office_model("res://assets/models/mega/props/pizza_box.glb", "LoungePizzaBox", Vector3(6.0, 0.35, 0.3), 15.0)
        _office_model("res://assets/models/mega/props/cardboard_box.glb", "StorageBox1", Vector3(6.8, 0.0, -5.0), 0.0)
        _office_model("res://assets/models/mega/props/cardboard_box.glb", "StorageBox2", Vector3(7.4, 0.0, -4.6), 25.0)
        _office_model("res://assets/models/mega/props/cardboard_box.glb", "StorageBox3", Vector3(-6.3, 0.0, -3.6), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/extension_cord.glb", "GarageExtensionCord", Vector3(0.5, 0.02, -6.6), 0.0)
        _office_model("res://assets/models/mega/architecture/garage/broom.glb", "GarageBroom", Vector3(-8.6, 0.0, 2.8), 15.0)
        # CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 1 ("ductos/pipes/breaker"
        # and "posters/señalética" were the two checklist items this
        # garage genuinely didn't have yet — every other item was already
        # covered by prior passes, confirmed by cross-checking the real
        # render against the phase's own composition list before adding
        # anything). Real, previously-unused pack assets, same fixed-spot
        # set-dressing discipline as the rest of this block.
        _office_model("res://assets/models/mega/architecture/garage/air_duct.glb", "GarageAirDuct", Vector3(4.0, 3.0, -6.8), 0.0, true)
        _office_model("res://assets/models/mega/architecture/garage/wall_pipe.glb", "GarageWallPipe", Vector3(-8.85, 0.0, -1.5), 90.0)
        _office_model("res://assets/models/mega/props/pinboard.glb", "GaragePinboard", Vector3(3.5, 1.6, -6.85), 0.0, true)
        _office_model("res://assets/models/mega/props/fire_extinguisher.glb", "GarageFireExtinguisher", Vector3(-8.7, 0.0, 3.6), 0.0)
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
## SERIOUS_REWORK_MASTER pass ("0 atravesando furniture"): obstacle_radius
## adds a real NavigationObstacle3D (same technique BuildController
## already uses for placed buildings, see its own _add_obstacle()) —
## previously 0.0/none for every ambient decorative prop this function
## places, which meant an idle-wander path could cross straight through
## large furniture like the lounge sofa or the storage shelf since it's
## outside BuildGrid's own placed-building obstacle coverage. Left 0.0
## (no change) for small/thin/wall-mounted props where this was never a
## real problem — only large floor-standing furniture in the middle of
## walkable floor gets one.
func _office_model(path: String, name_: String, pos: Vector3, y_rot_deg: float = 0.0, flat_wall_mount: bool = false, obstacle_radius: float = 0.0) -> void:
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
    _apply_screen_glow(inst)
    if obstacle_radius > 0.0:
        var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
        obstacle.radius = obstacle_radius
        obstacle.height = 1.2
        obstacle.avoidance_enabled = true
        facing.add_child(obstacle)

## Recurses into a just-instantiated prop looking for mesh parts named
## "display"/"display_N" and "screen"/"screen_N" (the mega-pack's
## glTF-import suffixing convention, same pattern StaffAgent._find_child_
## by_prefix() already handles for characters). "display" is the actual
## screen surface and gets the emissive glow material; "screen" turned
## out, confirmed by rendering both ways, to be a second, larger opaque
## front panel that fully occludes "display" from the camera — hiding it
## is what actually makes the glow visible, not a cosmetic extra. A
## no-op for every prop without either part, so this is safe to call
## unconditionally from _office_model() rather than needing a per-call
## opt-in flag.
func _apply_screen_glow(n: Node) -> void:
    if n is MeshInstance3D:
        var mesh_name: String = String(n.name)
        if mesh_name.begins_with("display"):
            if _screen_glow_material == null:
                _screen_glow_material = ShaderMaterial.new()
                _screen_glow_material.shader = _SCREEN_SHADER
            (n as MeshInstance3D).set_surface_override_material(0, _screen_glow_material)
        elif mesh_name.begins_with("screen"):
            n.visible = false
    for c in n.get_children():
        _apply_screen_glow(c)

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
    var base_energy: float = energy
    mat.emission_energy_multiplier = energy
    if city_texture != null:
        mat.albedo_texture = city_texture
        mat.emission_texture = city_texture
        base_energy = energy * CITY_EMISSION_SCALE
        mat.emission_energy_multiplier = base_energy
    mi.position = pos
    _office_visuals.add_child(mi)
    _window_materials.append({"material": mat, "base_energy": base_energy})

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
## (see BREAK_SPOT / StaffAgent.ambient_destinations), unlike every other
## ambient prop above — those live in the unwalkable margin outside the
## navmesh on purpose (KNOWN_ISSUES.md), which also makes them impossible
## to use as a real destination. BuildGrid.ROUTE_ROW (world z in [0,2],
## the full east-west aisle every staff member must already be able to
## cross) is the one strip of floor guaranteed walkable and guaranteed
## never buildable regardless of tier — placed in its western end so the
## rest of the aisle stays clear. Tier-agnostic like the rest of this
## function: every office, not just the garage, gets a break corner.
const BREAK_SPOT: Vector3 = Vector3(-6.1, 0.0, 1.0)
## World+NPC overhaul pass ("van a... whiteboard según tarea"): a second
## real ambient destination, a step in front of the garage-tier planning
## whiteboard (Vector3(-7.0, 0.0, -4.5) in _rebuild_office_visuals()) —
## offset into the room so an agent stands facing the board instead of
## walking into the wall it's mounted on. Garage-only like the whiteboard
## prop itself (not added to _build_ambient_decoration(), which is
## tier-agnostic) — wired directly where garage-tier staff get their
## ambient_destinations list, below.
const WHITEBOARD_SPOT: Vector3 = Vector3(-6.5, 0.0, -3.2)
## CLAUDE_VISUAL_EXECUTION_MASTERPACK Phase 2/3: a third real ambient
## destination, right in front of the garage-tier lounge sofa
## (`LoungeSofa`, Vector3(6.0, 0.0, 1.5) below) — tagged "lounge" so
## StaffAgent plays its real "sit" clip there instead of "talk", and one
## more real anchor point reducing how often idle agents fall back to
## pure random wandering (see AMBIENT_DESTINATION_CHANCE's doc comment).
const LOUNGE_SPOT: Vector3 = Vector3(6.0, 0.0, 0.6)
func _build_break_room() -> void:
    # SERIOUS_REWORK_MASTER pass: obstacle radii checked by real distance
    # against BREAK_SPOT (Vector3(-6.1, 0.0, 1.0)) MINUS the nav agent's
    # own radius (0.3, StaffAgent._ready()) plus a small margin — the
    # first pass at this only checked raw distance-to-obstacle-center,
    # which is wrong: the agent's own body also needs clearance to
    # stand at the target. Caught by an instrumented run showing the
    # equivalent lounge-table mistake stalling an agent 0.35 units short
    # of its target forever. `table` sits only 0.5 from the spot by
    # design (the agent ends up right next to it) — under the ~0.5
    # ceiling this margin leaves for it, so it keeps a token radius
    # rather than none.
    _static_prop("res://assets/models/mega/kitchen/fridge.glb", Vector3(-7.6, 0.0, 0.35), 90.0, 0.4)
    _static_prop("res://assets/models/mega/kitchen/vending_machine.glb", Vector3(-7.6, 0.0, 1.7), -90.0, 0.4)
    _static_prop("res://assets/models/mega/kitchen/coffee_machine.glb", Vector3(-6.6, 0.0, 1.75), 180.0, 0.35)
    _static_prop("res://assets/models/mega/kitchen/table.glb", Vector3(-5.6, 0.0, 1.0), 0.0)
    _static_prop("res://assets/models/mega/kitchen/chair.glb", Vector3(-5.6, 0.0, 0.25), 180.0, 0.2)

## y_rot_deg gets its own outer wrapper node around the pack's standard
## -90 X correction, same reason _office_model() does this instead of one
## combined Euler triple (see that function's doc comment) — confirmed
## necessary again here, not just assumed to carry over. obstacle_radius:
## see _office_model()'s matching parameter doc comment.
func _static_prop(model_path: String, pos: Vector3, y_rot_deg: float = 0.0, obstacle_radius: float = 0.0) -> void:
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
    if obstacle_radius > 0.0:
        var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
        obstacle.radius = obstacle_radius
        obstacle.height = 1.2
        obstacle.avoidance_enabled = true
        facing.add_child(obstacle)

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
    var ambient: Array[Vector3] = [BREAK_SPOT]
    var ambient_tags: Array[String] = ["break"]
    var current_tier: String = String(RealEstateManager.current_company_tier_def().get("id", "garage"))
    if current_tier == "garage" or current_tier == "garage_plus":
        ambient.append(WHITEBOARD_SPOT)
        ambient_tags.append("whiteboard")
        ambient.append(LOUNGE_SPOT)
        ambient_tags.append("lounge")
    agent.ambient_destinations = ambient
    agent.ambient_activity_tags = ambient_tags
    var role_id: String = String(StaffManager.find(staff_id).get("role", ""))
    agent.role_id = role_id
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
