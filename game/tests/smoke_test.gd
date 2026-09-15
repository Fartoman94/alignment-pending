extends SceneTree

## Headless smoke checks run by tools/bootstrap.sh. Project settings can be
## read in _init(), but autoload singletons are only attached to the tree
## root once _initialize() runs, so autoload-dependent checks live there.

func _init() -> void:
    var project_name: String = ProjectSettings.get_setting("application/config/name", "")
    if project_name != "Alignment Pending":
        push_error("Unexpected project name: %s" % project_name)
        quit(1)
        return
    print("SMOKE_OK: project settings load")

    var scene_paths: Array[String] = [
        "res://scenes/boot.tscn",
        "res://scenes/main_menu.tscn",
        "res://scenes/campaign.tscn",
        "res://scenes/settings.tscn",
        "res://scenes/hud.tscn",
    ]
    for scene_path: String in scene_paths:
        if not ResourceLoader.exists(scene_path, "PackedScene"):
            push_error("Missing scene: %s" % scene_path)
            quit(1)
            return
    print("SMOKE_OK: boot/main_menu/campaign scenes resolve")

func _initialize() -> void:
    var expected_autoloads: Array[String] = ["EventBus", "GameState", "SaveManager", "SceneRouter", "SettingsManager", "SimClock"]
    for autoload_name: String in expected_autoloads:
        if not get_root().has_node(autoload_name):
            push_error("Missing expected autoload singleton: %s" % autoload_name)
            quit(1)
            return
    print("SMOKE_OK: no missing autoloads")

    var router: Node = get_root().get_node("SceneRouter")
    var bad_result: Error = router.go_to("res://scenes/does_not_exist.tscn")
    if bad_result != ERR_FILE_NOT_FOUND:
        push_error("SceneRouter did not fail safely for a missing scene (got %s)" % bad_result)
        quit(1)
        return
    print("SMOKE_OK: scene router fails safely on a missing scene")

    var settings: Node = get_root().get_node("SettingsManager")
    settings.ui_scale = 5.0
    settings.resolution_index = -3
    settings.apply_all()
    if settings.ui_scale != settings.MAX_UI_SCALE:
        push_error("SettingsManager did not clamp ui_scale (got %s)" % settings.ui_scale)
        quit(1)
        return
    if settings.get_resolution() != settings.RESOLUTIONS[0]:
        push_error("SettingsManager did not clamp resolution_index")
        quit(1)
        return
    print("SMOKE_OK: settings clamp out-of-range values to safe defaults")

    settings.reset_to_defaults()
    settings.master_volume = 0.42
    settings.ui_scale = 1.3
    settings.reduced_motion = true
    var save_err: Error = settings.save_settings()
    if save_err != OK:
        push_error("SettingsManager failed to save settings (error %s)" % save_err)
        quit(1)
        return
    settings.reset_to_defaults()
    var load_err: Error = settings.load_settings()
    if load_err != OK:
        push_error("SettingsManager failed to load settings (error %s)" % load_err)
        quit(1)
        return
    if not (is_equal_approx(settings.master_volume, 0.42) and is_equal_approx(settings.ui_scale, 1.3) and settings.reduced_motion):
        push_error("SettingsManager save/load round-trip lost data")
        quit(1)
        return
    print("SMOKE_OK: settings survive a save/load round-trip")

    # boot.tscn is excluded: its _ready() actively calls SceneRouter.go_to(),
    # which would swap this test's tree root out from under it.
    var instantiable_scenes: Array[String] = [
        "res://scenes/main_menu.tscn",
        "res://scenes/settings.tscn",
        "res://scenes/campaign.tscn",
    ]
    for scene_path: String in instantiable_scenes:
        var packed: PackedScene = load(scene_path)
        var inst: Node = packed.instantiate()
        get_root().add_child(inst)
        await process_frame
        inst.queue_free()
        await process_frame
    print("SMOKE_OK: main_menu/settings/campaign scenes instantiate and process a frame without error")

    var hud_packed: PackedScene = load("res://scenes/hud.tscn")
    var hud_inst: Node = hud_packed.instantiate()
    get_root().add_child(hud_inst)
    await process_frame
    # Every strip must be anchor-driven (not fixed-pixel positioned), so the
    # layout stays correct at both 1280x720 and 1920x1080 without per-
    # resolution tuning.
    var top_bar: Control = hud_inst.get_node("TopBar")
    var bottom_bar: Control = hud_inst.get_node("BottomBar")
    var left_panel: Control = hud_inst.get_node("LeftPanel")
    var right_panel: Control = hud_inst.get_node("RightPanel")
    var anchors_ok: bool = (
        is_equal_approx(top_bar.anchor_left, 0.0) and is_equal_approx(top_bar.anchor_right, 1.0)
        and is_equal_approx(bottom_bar.anchor_top, 1.0) and is_equal_approx(bottom_bar.anchor_bottom, 1.0)
        and is_equal_approx(left_panel.anchor_right, 0.0) and is_equal_approx(left_panel.anchor_bottom, 1.0)
        and is_equal_approx(right_panel.anchor_left, 1.0) and is_equal_approx(right_panel.anchor_right, 1.0)
    )
    if not anchors_ok:
        push_error("Hud strips are not fully anchor-driven; layout would break at other resolutions")
        quit(1)
        return
    hud_inst.queue_free()
    await process_frame
    print("SMOKE_OK: HUD strips are anchor-driven (responsive at 1280x720 and 1920x1080)")

    var state: Node = get_root().get_node("GameState")
    var save_mgr: Node = get_root().get_node("SaveManager")

    if not (state.get("SAVE_VERSION") is int) or int(state.SAVE_VERSION) < 1:
        push_error("GameState.SAVE_VERSION must be an explicit int >= 1 (got %s)" % state.get("SAVE_VERSION"))
        quit(1)
        return
    print("SMOKE_OK: save schema version is explicit (v%d)" % state.SAVE_VERSION)

    state.cash = 555555.0
    state.public_trust = 12.0
    var manual_err: Error = save_mgr.save_manual(0)
    if manual_err != OK:
        push_error("SaveManager failed to write manual slot 0 (error %s)" % manual_err)
        quit(1)
        return
    state.cash = 0.0
    state.public_trust = 0.0
    var manual_load_err: Error = save_mgr.load_manual(0)
    if manual_load_err != OK or not is_equal_approx(state.cash, 555555.0) or not is_equal_approx(state.public_trust, 12.0):
        push_error("SaveManager manual save/load round-trip lost data (error %s)" % manual_load_err)
        quit(1)
        return
    print("SMOKE_OK: manual save round-trip preserves campaign state")

    state.cash = 111.0
    save_mgr.autosave()
    state.cash = 222.0
    save_mgr.autosave()
    state.cash = 333.0
    save_mgr.autosave()
    # Corrupt the newest autosave (slot 0) directly, bypassing SaveManager.
    var corrupt_path: String = save_mgr._autosave_path(0)
    var corrupt_file: FileAccess = FileAccess.open(corrupt_path, FileAccess.WRITE)
    corrupt_file.store_string("{ not valid json or a mismatched checksum")
    corrupt_file.close()
    state.cash = -1.0
    var fallback_err: Error = save_mgr.load_newest_autosave()
    if fallback_err != OK or not is_equal_approx(state.cash, 222.0):
        push_error("SaveManager did not fall back past a corrupted newest autosave (error %s, cash=%s)" % [fallback_err, state.cash])
        quit(1)
        return
    print("SMOKE_OK: a corrupted newest autosave falls back to the next valid rotating slot")

    var seed_issues: Array = DataValidator.validate_all()
    if not seed_issues.is_empty():
        for issue in seed_issues:
            push_error("DataValidator: %s" % issue.format())
        push_error("Seed content data failed validation (%d issue(s))" % seed_issues.size())
        quit(1)
        return
    print("SMOKE_OK: seed event data validates cleanly")

    var bad_events_path: String = "user://smoke_test_bad_events.json"
    var bad_file: FileAccess = FileAccess.open(bad_events_path, FileAccess.WRITE)
    bad_file.store_string(JSON.stringify([
        {"id": "dup", "category": "reliability", "severity": 1, "title": "A", "body": "b", "choices": ["x", "y"]},
        {"id": "dup", "category": "not_a_real_category", "severity": 99, "title": "", "body": "b", "choices": ["only_one"]},
        {"category": "governance", "severity": 1, "title": "Missing id", "body": "b", "choices": ["x", "y"]},
    ]))
    bad_file.close()
    var bad_issues: Array = DataValidator.validate_event_file(bad_events_path)
    DirAccess.remove_absolute(bad_events_path)
    var expected_problems: Array[String] = ["duplicate id", "unknown category", "out of range", "non-empty string", "expected 2-4", "missing required field 'id'"]
    var all_found: bool = true
    for expected: String in expected_problems:
        var found: bool = false
        for issue in bad_issues:
            if String(issue.format()).contains(expected):
                found = true
                break
        if not found:
            push_error("DataValidator did not flag expected problem: '%s'" % expected)
            all_found = false
    if not all_found:
        quit(1)
        return
    print("SMOKE_OK: DataValidator catches duplicate ids, unknown categories, out-of-range severity, bad choices, and missing fields")

    var sim: Node = get_root().get_node("SimClock")
    var pool: Array = ["a", "b", "c", "d", "e"]

    state.campaign_seed = 4242
    sim.reset_rng_streams()
    var sequence_a: Array = []
    for i in 5:
        sequence_a.append(sim.pick_from("events", pool))

    state.campaign_seed = 4242
    sim.reset_rng_streams()
    var sequence_b: Array = []
    for i in 5:
        sequence_b.append(sim.pick_from("events", pool))

    if sequence_a != sequence_b:
        push_error("SimClock RNG stream is not deterministic for the same seed: %s vs %s" % [sequence_a, sequence_b])
        quit(1)
        return
    print("SMOKE_OK: same seed + actions produces the same event-selection sequence")

    # Fixed-tick calendar advance must be frame-rate independent: the same
    # total elapsed time should land on the same calendar regardless of how
    # many frames it was split across. Deliberately not a whole number of
    # ticks, so float summation error across 370 tiny steps can't flip
    # which side of an exact tick boundary the total lands on.
    var total_seconds: float = 37.3
    state.calendar_day = 1
    state.calendar_hour = 9
    state.calendar_minute = 0
    state.simulation_speed = 1.0
    state.paused = false
    sim.active = true
    sim._accumulator = 0.0
    sim._process(total_seconds)
    var day_a: int = state.calendar_day
    var hour_a: int = state.calendar_hour
    var minute_a: int = state.calendar_minute

    state.calendar_day = 1
    state.calendar_hour = 9
    state.calendar_minute = 0
    sim._accumulator = 0.0
    var steps: int = 370
    for i in steps:
        sim._process(total_seconds / steps)

    sim.active = false
    if state.calendar_day != day_a or state.calendar_hour != hour_a or state.calendar_minute != minute_a:
        push_error("SimClock tick advancement is not frame-rate independent (%d %02d:%02d vs %d %02d:%02d)" % [day_a, hour_a, minute_a, state.calendar_day, state.calendar_hour, state.calendar_minute])
        quit(1)
        return
    print("SMOKE_OK: SimClock fixed-tick calendar advance is frame-rate independent")

    # Loaded dynamically (not as a bare `BuildGrid`/`BuildController`
    # identifier): a static reference in this file's own source would force
    # the compiler to eagerly compile build_controller.gd — which touches
    # GameState — while loading this very script, before autoloads exist.
    var build_grid_script: GDScript = load("res://src/world/build_grid.gd")
    var build_controller_script: GDScript = load("res://src/world/build_controller.gd")
    const ROUTE_ROW: int = 3  # must match BuildGrid.ROUTE_ROW

    var grid: Node = build_grid_script.new()
    var desk_cells: Array[Vector2i] = grid.footprint_cells(Vector2i(0, 0), 1, 1, false)
    if not grid.is_area_free(desk_cells):
        push_error("BuildGrid: expected (0,0) to be free before any placement")
        quit(1)
        return
    grid.occupy(desk_cells, "test_building")
    if grid.is_area_free(desk_cells):
        push_error("BuildGrid: occupied cells were reported as free")
        quit(1)
        return
    if not grid.is_reserved(Vector2i(0, ROUTE_ROW)):
        push_error("BuildGrid: the mandatory walkway row is not reserved")
        quit(1)
        return
    var route_cells: Array[Vector2i] = grid.footprint_cells(Vector2i(2, ROUTE_ROW), 1, 1, false)
    if grid.is_area_free(route_cells):
        push_error("BuildGrid: a placement on the mandatory route row was allowed")
        quit(1)
        return
    grid.free_cells(desk_cells)
    if not grid.is_area_free(desk_cells):
        push_error("BuildGrid: cells stayed occupied after free_cells")
        quit(1)
        return
    print("SMOKE_OK: BuildGrid occupancy, overlap prevention, and mandatory-route blocking work")

    var catalog: Dictionary = BuildableCatalog.load_all()
    if not (catalog.has("desk") and catalog.has("server_rack") and catalog.has("safety_lab")):
        push_error("BuildableCatalog did not load the expected desk/server_rack/safety_lab entries")
        quit(1)
        return
    print("SMOKE_OK: BuildableCatalog loads desk/server_rack/safety_lab")

    var bc: Node = build_controller_script.new()
    get_root().add_child(bc)
    bc.grid = build_grid_script.new()
    get_root().add_child(bc.grid)
    var starting_cash: float = 100000.0
    state.cash = starting_cash

    bc.start_place("desk")
    await process_frame
    var desk_def: Dictionary = catalog["desk"]
    var target_cell: Vector2i = Vector2i(1, 1)
    bc._ghost.set_meta("cell", target_cell)
    bc._ghost.set_meta("valid", true)
    var place_err: Error = bc.try_place()
    if place_err != OK:
        push_error("BuildController.try_place failed unexpectedly (error %s)" % place_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, starting_cash - float(desk_def.get("cost", 0.0))):
        push_error("BuildController.try_place did not deduct the desk's cost")
        quit(1)
        return
    if bc.grid.is_area_free(bc.grid.footprint_cells(target_cell, 1, 1, false)):
        push_error("BuildController.try_place did not occupy the grid cell")
        quit(1)
        return
    if state.buildings.is_empty():
        push_error("BuildController.try_place did not sync GameState.buildings")
        quit(1)
        return

    # Even if the ghost's cached "valid" flag says true, try_place() must
    # re-validate against the authoritative grid before allowing an overlap.
    bc.start_place("desk")
    await process_frame
    bc._ghost.set_meta("cell", target_cell)
    bc._ghost.set_meta("valid", true)
    var overlap_err: Error = bc.try_place()
    if overlap_err == OK:
        push_error("BuildController.try_place allowed an overlapping placement")
        quit(1)
        return
    print("SMOKE_OK: BuildController placement deducts cost, occupies cells, syncs GameState.buildings, and rejects overlap")

    var cash_before_sell: float = state.cash
    var expected_refund: float = float(desk_def.get("cost", 0.0)) * float(desk_def.get("refund_ratio", 0.0))
    var sell_err: Error = bc.try_sell(target_cell)
    if sell_err != OK:
        push_error("BuildController.try_sell failed on a valid target (error %s)" % sell_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_sell + expected_refund):
        push_error("BuildController.try_sell refunded the wrong amount")
        quit(1)
        return
    if not bc.grid.is_area_free(bc.grid.footprint_cells(target_cell, 1, 1, false)):
        push_error("BuildController.try_sell did not free the grid cell")
        quit(1)
        return
    print("SMOKE_OK: BuildController sell refunds the data-driven ratio and frees the cell")

    grid.free()
    bc.grid.queue_free()
    bc.queue_free()
    await process_frame

    # P09: navigation + a simple state machine + destination reservation.
    # Loaded dynamically for the same compile-order reason as BuildGrid/
    # BuildController above (StaffAgent touches GameState.paused).
    var nav_coordinator_script: GDScript = load("res://src/world/nav_coordinator.gd")
    var staff_agent_script: GDScript = load("res://src/world/staff_agent.gd")

    var test_nav_region: NavigationRegion3D = NavigationRegion3D.new()
    var test_navmesh: NavigationMesh = NavigationMesh.new()
    test_navmesh.vertices = PackedVector3Array([
        Vector3(-7.0, 0.0, -5.0), Vector3(7.0, 0.0, -5.0),
        Vector3(7.0, 0.0, 5.0), Vector3(-7.0, 0.0, 5.0),
    ])
    test_navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    test_nav_region.navigation_mesh = test_navmesh
    get_root().add_child(test_nav_region)

    var coordinator: RefCounted = nav_coordinator_script.new()
    var agents: Array = []
    for i in 20:
        var agent: Node3D = staff_agent_script.new()
        agent.coordinator = coordinator
        agent.rng.seed = 1000 + i
        agent.position = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-4.0, 4.0))
        get_root().add_child(agent)
        agents.append(agent)

    # Let the navigation map sync and give every agent room to take at
    # least a few steps (up to a 4s idle wait, then real travel time).
    for i in 900:
        await physics_frame

    var total_distance: float = 0.0
    var stuck_agents: int = 0
    for agent in agents:
        total_distance += agent.total_distance_traveled
        if agent.total_distance_traveled <= 0.01:
            stuck_agents += 1
    if stuck_agents > 0:
        push_error("StaffAgent: %d of 20 agents never moved at all (possible deadlock)" % stuck_agents)
        quit(1)
        return
    if total_distance <= 1.0:
        push_error("StaffAgent: total movement across 20 agents was implausibly small (%.3f)" % total_distance)
        quit(1)
        return
    print("SMOKE_OK: 20 StaffAgents all made movement progress with no obvious deadlock (total distance %.1f)" % total_distance)

    state.paused = true
    await process_frame
    var distances_at_pause: Array = []
    for agent in agents:
        distances_at_pause.append(agent.total_distance_traveled)
    for i in 120:
        await physics_frame
    var moved_while_paused: bool = false
    for i in agents.size():
        if agents[i].total_distance_traveled > distances_at_pause[i] + 0.001:
            moved_while_paused = true
            break
    state.paused = false
    if moved_while_paused:
        push_error("StaffAgent: movement continued while GameState.paused was true")
        quit(1)
        return
    print("SMOKE_OK: pausing the game stops staff movement (simulation tasks)")

    for agent in agents:
        agent.queue_free()
    test_nav_region.queue_free()
    await process_frame

    quit(0)
