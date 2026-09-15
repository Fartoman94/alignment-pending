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

    # P10: staff model, hiring/firing/payroll, stable IDs across save/load.
    var role_catalog: Dictionary = StaffRoleCatalog.load_all()
    var expected_roles: Array[String] = ["researcher", "engineer", "data_ops", "safety_analyst", "product_manager", "support_specialist"]
    for role_id: String in expected_roles:
        if not role_catalog.has(role_id):
            push_error("StaffRoleCatalog missing expected role '%s'" % role_id)
            quit(1)
            return
    print("SMOKE_OK: StaffRoleCatalog loads all 6 staff roles")

    var staff_mgr: Node = get_root().get_node("StaffManager")
    state.campaign_seed = 77777
    state.staff = []
    state.next_staff_id = 1
    state.cash = 50000.0
    sim.reset_rng_streams()
    staff_mgr.refresh_candidates()
    var first_candidate_name: String = String(staff_mgr.candidates[0].get("generated_name", ""))

    sim.reset_rng_streams()
    staff_mgr.refresh_candidates()
    var second_candidate_name: String = String(staff_mgr.candidates[0].get("generated_name", ""))
    if first_candidate_name != second_candidate_name or first_candidate_name.is_empty():
        push_error("StaffManager candidate generation is not deterministic for the same seed")
        quit(1)
        return
    print("SMOKE_OK: same seed produces the same generated staff candidates")

    var candidate_salary: float = float(staff_mgr.candidates[0].get("salary", 0.0))
    var hire_err: Error = staff_mgr.hire(0)
    if hire_err != OK or state.staff.size() != 1:
        push_error("StaffManager.hire() failed to add the candidate to the roster (error %s)" % hire_err)
        quit(1)
        return
    var hired_id: String = String(state.staff[0].get("id", ""))
    if hired_id.is_empty():
        push_error("StaffManager.hire() did not assign a stable id")
        quit(1)
        return
    if not is_equal_approx(staff_mgr.total_payroll(), candidate_salary):
        push_error("StaffManager.total_payroll() does not match the hired candidate's salary")
        quit(1)
        return
    print("SMOKE_OK: hiring adds the candidate to the roster with a stable id and correct payroll")

    var cash_before_payroll: float = state.cash
    var bus2: Node = get_root().get_node("EventBus")
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_payroll - candidate_salary):
        push_error("StaffManager did not deduct daily payroll on day_advanced")
        quit(1)
        return
    print("SMOKE_OK: daily payroll is deducted from cash on day_advanced")

    # Stable IDs across save/load: same id, not regenerated.
    var staff_save_err: Error = save_mgr.save_manual(1)
    if staff_save_err != OK:
        push_error("SaveManager failed to save staff roster (error %s)" % staff_save_err)
        quit(1)
        return
    state.staff = []
    var staff_load_err: Error = save_mgr.load_manual(1)
    if staff_load_err != OK or state.staff.size() != 1 or String(state.staff[0].get("id", "")) != hired_id:
        push_error("Staff id was not stable across save/load (error %s)" % staff_load_err)
        quit(1)
        return
    print("SMOKE_OK: staff roster and stable ids survive save/load")

    var fire_err: Error = staff_mgr.fire(hired_id)
    if fire_err != OK or not state.staff.is_empty():
        push_error("StaffManager.fire() failed to remove the staff member (error %s)" % fire_err)
        quit(1)
        return
    print("SMOKE_OK: firing removes the staff member from the roster")

    # P11: task assignment and workstations.
    var task_catalog: Dictionary = WorkTaskCatalog.load_all()
    for expected_task_id: String in ["research_sprint", "training_run", "safety_audit"]:
        if not task_catalog.has(expected_task_id):
            push_error("WorkTaskCatalog missing expected task '%s'" % expected_task_id)
            quit(1)
            return
    print("SMOKE_OK: WorkTaskCatalog loads research/training/safety task templates")

    var task_mgr: Node = get_root().get_node("TaskManager")
    state.staff = []
    state.buildings = [{"id": "test_bldg_1", "buildable_id": "desk", "cell_x": 0, "cell_y": 0, "rotated": false}]
    staff_mgr.refresh_candidates()
    var assign_err0: Error = staff_mgr.hire(0)
    if assign_err0 != OK:
        push_error("Setup for P11 test failed to hire a candidate")
        quit(1)
        return
    var worker_id: String = String(state.staff[0].get("id", ""))

    var assign_err: Error = task_mgr.assign(worker_id, "research_sprint", "test_bldg_1")
    if assign_err != OK:
        push_error("TaskManager.assign() failed for a compatible staff/task/building (error %s)" % assign_err)
        quit(1)
        return
    if String(state.staff[0].get("assigned_task", "")).is_empty():
        push_error("TaskManager.assign() did not set StaffMember.assigned_task")
        quit(1)
        return
    if not task_mgr.is_building_reserved("test_bldg_1"):
        push_error("TaskManager.assign() did not reserve the workstation")
        quit(1)
        return

    # A second, different task can't double-book the same reserved desk.
    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var second_worker_id: String = String(state.staff[1].get("id", ""))
    var double_book_err: Error = task_mgr.assign(second_worker_id, "research_sprint", "test_bldg_1")
    if double_book_err == OK:
        push_error("TaskManager.assign() allowed double-booking an already-reserved workstation")
        quit(1)
        return
    print("SMOKE_OK: assigning a compatible job reserves the workstation and rejects double-booking")

    bus2.simulation_tick.emit(100)
    var progress_after_one_tick: float = task_mgr.progress_fraction(task_mgr.find_order_for_staff(worker_id))
    if progress_after_one_tick <= 0.0 or progress_after_one_tick >= 1.0:
        push_error("TaskManager progress after a single tick should be a partial fraction (got %.3f)" % progress_after_one_tick)
        quit(1)
        return
    print("SMOKE_OK: assigned work consumes worker time and shows partial progress (%.0f%%)" % (progress_after_one_tick * 100.0))

    for i in 5:
        bus2.simulation_tick.emit(400)
    if not String(state.staff[0].get("assigned_task", "")).is_empty():
        push_error("Research task did not complete after enough simulated worker time")
        quit(1)
        return
    if task_mgr.is_building_reserved("test_bldg_1"):
        push_error("Completing a task did not free the reserved workstation")
        quit(1)
        return
    print("SMOKE_OK: enough consumed worker time completes the task and frees the workstation")

    # Stable building ids survive save/load (task assignment depends on this).
    var bldg_save_err: Error = save_mgr.save_manual(2)
    state.buildings = []
    var bldg_load_err: Error = save_mgr.load_manual(2)
    if bldg_save_err != OK or bldg_load_err != OK or state.buildings.is_empty() or String(state.buildings[0].get("id", "")) != "test_bldg_1":
        push_error("Building id was not stable across save/load (save error %s, load error %s)" % [bldg_save_err, bldg_load_err])
        quit(1)
        return
    print("SMOKE_OK: building ids survive save/load (task assignment can reference them reliably)")

    state.staff = []
    state.buildings = []
    state.work_orders = []

    # P12: compute/power/heat driven by server racks; over-capacity blocks
    # jobs/placement instead of corrupting state.
    var bc2: Node = build_controller_script.new()
    get_root().add_child(bc2)
    bc2.grid = build_grid_script.new()
    get_root().add_child(bc2.grid)
    state.cash = 1000000.0

    bc2.start_place("server_rack")
    await process_frame
    bc2._ghost.set_meta("cell", Vector2i(0, 0))
    bc2._ghost.set_meta("valid", true)
    var place1_err: Error = bc2.try_place()
    if place1_err != OK:
        push_error("Placing the first server rack failed unexpectedly (error %s)" % place1_err)
        quit(1)
        return
    var expected_compute: float = float(state.BASE_COMPUTE_CAPACITY) + 25.0
    var expected_power: float = float(state.BASE_POWER_DRAW) + 18.0
    if not is_equal_approx(state.compute_capacity, expected_compute) or not is_equal_approx(state.power_used, expected_power) or not is_equal_approx(state.heat_load, 20.0):
        push_error("Placing a server rack did not correctly update compute/power/heat (compute=%s power=%s heat=%s)" % [state.compute_capacity, state.power_used, state.heat_load])
        quit(1)
        return
    print("SMOKE_OK: placing a server rack increases compute capacity, power draw, and heat load")

    for i in range(1, 5):
        bc2.start_place("server_rack")
        await process_frame
        bc2._ghost.set_meta("cell", Vector2i(i, 0))
        bc2._ghost.set_meta("valid", true)
        var err_i: Error = bc2.try_place()
        if err_i != OK:
            push_error("Placing server rack #%d unexpectedly failed (error %s)" % [i + 1, err_i])
            quit(1)
            return
    # 5 racks placed: base(10) + 5*18 = 100 = exactly at capacity.
    if not is_equal_approx(state.power_used, float(state.BASE_POWER_CAPACITY)):
        push_error("Expected power_used to reach exactly capacity after 5 racks (got %s)" % state.power_used)
        quit(1)
        return

    var power_before_overflow: float = state.power_used
    bc2.start_place("server_rack")
    await process_frame
    bc2._ghost.set_meta("cell", Vector2i(6, 0))
    bc2._ghost.set_meta("valid", true)  # cached "valid" from the ghost; try_place() must still re-check.
    var overflow_err: Error = bc2.try_place()
    if overflow_err == OK:
        push_error("BuildController allowed a rack placement that exceeds power capacity")
        quit(1)
        return
    if not is_equal_approx(state.power_used, power_before_overflow):
        push_error("A blocked over-capacity placement corrupted power_used (was %s, now %s)" % [power_before_overflow, state.power_used])
        quit(1)
        return
    print("SMOKE_OK: a rack placement that would exceed power capacity is blocked, not silently corrupting state")

    state.staff = []
    state.work_orders = []
    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var trainer_id: String = String(state.staff[0].get("id", ""))
    var rack_building_id: String = String(state.buildings[0].get("id", ""))
    state.compute_used = state.effective_compute_capacity()
    var blocked_assign_err: Error = task_mgr.assign(trainer_id, "training_run", rack_building_id)
    if blocked_assign_err == OK:
        push_error("TaskManager allowed a training assignment with no free compute headroom")
        quit(1)
        return
    print("SMOKE_OK: a training job is blocked when there is no free compute headroom")
    state.compute_used = 0.0

    state.heat_capacity = 60.0
    state.heat_load = 120.0
    var throttled: float = state.effective_compute_capacity()
    var base_capacity: float = state.compute_capacity
    if not (throttled < base_capacity and throttled >= base_capacity * 0.3 - 0.01):
        push_error("Heat throttling formula produced an unexpected effective compute capacity (%.2f of %.2f)" % [throttled, base_capacity])
        quit(1)
        return
    print("SMOKE_OK: heat above capacity throttles effective compute instead of corrupting state")

    bc2.grid.queue_free()
    bc2.queue_free()
    await process_frame

    # P13: research tree — nodes, prerequisites, progress, unlock effects.
    var research_mgr: Node = get_root().get_node("ResearchManager")
    var node_ids: Array = ResearchNodeCatalog.ordered_ids()
    if node_ids.size() != 8:
        push_error("ResearchNodeCatalog should seed exactly 8 nodes (got %d)" % node_ids.size())
        quit(1)
        return
    print("SMOKE_OK: ResearchNodeCatalog seeds 8 research nodes")

    state.cash = 1000000.0
    state.staff = []
    state.buildings = [{"id": "research_desk_1", "buildable_id": "desk", "cell_x": 0, "cell_y": 0, "rotated": false}]
    state.research_unlocked = []
    state.research_progress = {}
    state.research_compute_bonus = 0.0

    if research_mgr.can_start("scaling_laws"):
        push_error("ResearchManager allowed starting a node whose prerequisite is not unlocked")
        quit(1)
        return
    if not research_mgr.can_start("core_architectures"):
        push_error("ResearchManager should allow starting a prerequisite-free, affordable node")
        quit(1)
        return
    print("SMOKE_OK: research prerequisites gate which nodes can start")

    var cash_before_start: float = state.cash
    var start_err: Error = research_mgr.start("core_architectures")
    if start_err != OK or not state.research_progress.has("core_architectures"):
        push_error("ResearchManager.start() failed to begin a valid node (error %s)" % start_err)
        quit(1)
        return
    var core_cost: float = float(ResearchNodeCatalog.get_def("core_architectures").get("cost", 0.0))
    if not is_equal_approx(state.cash, cash_before_start - core_cost):
        push_error("ResearchManager.start() did not deduct the node's cash cost")
        quit(1)
        return
    print("SMOKE_OK: starting research deducts cash and begins tracking progress")

    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var researcher_id: String = String(state.staff[0].get("id", ""))

    # core_architectures needs 480 minutes; each research_sprint session is
    # 240 minutes, so it takes two full sessions (re-assign in between).
    for session in 2:
        var assign_err2: Error = task_mgr.assign(researcher_id, "research_sprint", "research_desk_1", "core_architectures")
        if assign_err2 != OK:
            push_error("Failed to assign researcher to research_sprint targeting core_architectures (session %d, error %s)" % [session, assign_err2])
            quit(1)
            return
        for i in 5:
            bus2.simulation_tick.emit(400)
    if not research_mgr.is_unlocked("core_architectures"):
        push_error("core_architectures did not unlock after enough worker time across two sessions")
        quit(1)
        return
    if not state.research_unlocked.has("core_architectures"):
        push_error("Unlocked node was not recorded in GameState.research_unlocked")
        quit(1)
        return
    var expected_bonus: float = float((ResearchNodeCatalog.get_def("core_architectures").get("unlock_effect", {}) as Dictionary).get("amount", 0.0))
    if not is_equal_approx(state.research_compute_bonus, expected_bonus):
        push_error("compute_bonus unlock effect was not applied (expected %.1f, got %.1f)" % [expected_bonus, state.research_compute_bonus])
        quit(1)
        return
    print("SMOKE_OK: enough worker time across sessions unlocks a node and applies its unlock effect (compute_bonus)")

    if not research_mgr.prerequisites_met("scaling_laws"):
        push_error("Unlocking core_architectures should satisfy scaling_laws' prerequisite")
        quit(1)
        return
    print("SMOKE_OK: unlocking a node satisfies it as a prerequisite for dependent nodes")

    # A second, independent unlock effect type (safety_debt_delta), applied
    # directly to isolate the effect logic from the multi-session tick flow.
    research_mgr.start("interpretability_basics")
    var safety_before: float = state.safety_debt
    research_mgr._on_task_completed("dummy_staff", "research_sprint", "interpretability_basics")
    research_mgr._on_task_completed("dummy_staff", "research_sprint", "interpretability_basics")
    if not research_mgr.is_unlocked("interpretability_basics"):
        push_error("interpretability_basics did not unlock after enough recorded progress")
        quit(1)
        return
    var expected_safety_delta: float = float((ResearchNodeCatalog.get_def("interpretability_basics").get("unlock_effect", {}) as Dictionary).get("amount", 0.0))
    if not is_equal_approx(state.safety_debt, maxf(0.0, safety_before + expected_safety_delta)):
        push_error("safety_debt_delta unlock effect was not applied correctly (before=%.1f after=%.1f)" % [safety_before, state.safety_debt])
        quit(1)
        return
    print("SMOKE_OK: unlock effects are testable and correctly applied (safety_debt_delta)")

    # Save/load stability of research progress and unlocks.
    state.research_progress["datacenter_efficiency"] = 100.0
    var research_save_err: Error = save_mgr.save_manual(0)
    var unlocked_before_reload: Array = state.research_unlocked.duplicate()
    state.research_unlocked = []
    state.research_progress = {}
    var research_load_err: Error = save_mgr.load_manual(0)
    if research_save_err != OK or research_load_err != OK or state.research_unlocked != unlocked_before_reload or not state.research_progress.has("datacenter_efficiency"):
        push_error("Research progress/unlocks did not survive save/load (save error %s, load error %s)" % [research_save_err, research_load_err])
        quit(1)
        return
    print("SMOKE_OK: research progress and unlocked nodes persist across save/load")

    state.staff = []
    state.buildings = []
    state.work_orders = []
    state.research_unlocked = []
    state.research_progress = {}
    state.research_compute_bonus = 0.0

    # P14: model training pipeline — 3 generations, safe cancel, never
    # negative compute/cash.
    var model_mgr: Node = get_root().get_node("ModelManager")
    var tier_ids: Array = ModelTierCatalog.ordered_ids()
    if tier_ids.size() != 3:
        push_error("ModelTierCatalog should seed exactly 3 architecture tiers (got %d)" % tier_ids.size())
        quit(1)
        return
    print("SMOKE_OK: ModelTierCatalog seeds 3 architecture tiers")

    state.cash = 1000000.0
    state.staff = []
    state.buildings = [{"id": "rack_1", "buildable_id": "server_rack", "cell_x": 0, "cell_y": 0, "rotated": false}]
    state.model_projects = []
    state.models = []
    state.work_orders = []

    if not model_mgr.can_start("small"):
        push_error("ModelManager should allow starting an affordable tier")
        quit(1)
        return

    var project_err: Error = model_mgr.start_project("small")
    if project_err != OK or state.model_projects.size() != 1:
        push_error("ModelManager.start_project() failed to queue a project (error %s)" % project_err)
        quit(1)
        return
    var cash_after_start: float = state.cash
    var queued_project_id: String = String(state.model_projects[0].get("id", ""))
    var cancel_err: Error = model_mgr.cancel_project(queued_project_id)
    if cancel_err != OK or not state.model_projects.is_empty():
        push_error("ModelManager.cancel_project() failed to remove a queued project (error %s)" % cancel_err)
        quit(1)
        return
    if state.cash < 0.0 or not is_equal_approx(state.cash, cash_after_start):
        push_error("Cancelling a project should not change cash further (sunk cost only)")
        quit(1)
        return
    print("SMOKE_OK: model projects can be cancelled safely with no leftover state")

    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var engineer_id: String = String(state.staff[0].get("id", ""))
    model_mgr.start_project("small")
    var active_project_id: String = String(state.model_projects[0].get("id", ""))
    task_mgr.assign(engineer_id, "training_run", "rack_1", active_project_id)
    if String(state.staff[0].get("assigned_task", "")).is_empty():
        push_error("Setup: engineer should be assigned before testing mid-task cancellation")
        quit(1)
        return
    model_mgr.cancel_project(active_project_id)
    if not String(state.staff[0].get("assigned_task", "")).is_empty():
        push_error("Cancelling a project did not free the assigned staff member")
        quit(1)
        return
    if task_mgr.is_building_reserved("rack_1"):
        push_error("Cancelling a project did not free the reserved workstation")
        quit(1)
        return
    print("SMOKE_OK: cancelling an in-progress project frees the assigned staff and workstation")

    for gen in range(1, 4):
        var start_err2: Error = model_mgr.start_project("small")
        if start_err2 != OK:
            push_error("Failed to start generation %d project (error %s)" % [gen, start_err2])
            quit(1)
            return
        var gen_project_id: String = String(state.model_projects[0].get("id", ""))
        # small tier needs 720 minutes; each training_run session is 360,
        # so it takes two sessions.
        for session in 2:
            var assign_err3: Error = task_mgr.assign(engineer_id, "training_run", "rack_1", gen_project_id)
            if assign_err3 != OK:
                push_error("Failed to assign engineer for generation %d, session %d (error %s)" % [gen, session, assign_err3])
                quit(1)
                return
            for i in 5:
                bus2.simulation_tick.emit(400)
        if state.models.size() != gen:
            push_error("Expected %d trained model(s) after generation %d, got %d" % [gen, gen, state.models.size()])
            quit(1)
            return
        var latest_model: Dictionary = state.models[state.models.size() - 1]
        if int(latest_model.get("generation", -1)) != gen:
            push_error("Model generation field incorrect (expected %d, got %s)" % [gen, latest_model.get("generation")])
            quit(1)
            return
        if state.cash < 0.0 or state.compute_used < 0.0:
            push_error("Cash or compute went negative while training generation %d" % gen)
            quit(1)
            return
    print("SMOKE_OK: can create 3 generations sequentially, each with the correct generation number")

    state.cash = 0.0
    if model_mgr.can_start("large") or model_mgr.start_project("large") == OK:
        push_error("ModelManager allowed starting a project with insufficient cash")
        quit(1)
        return
    print("SMOKE_OK: starting a model project without enough cash is rejected, never goes negative")

    state.staff = []
    state.buildings = []
    state.work_orders = []
    state.model_projects = []
    state.models = []

    # P15: evaluation system — uncertainty ranges, hidden latent risk,
    # repeated evals cost resources and reduce uncertainty.
    var eval_mgr: Node = get_root().get_node("EvaluationManager")
    state.cash = 1000000.0
    state.staff = []
    state.buildings = [{"id": "lab_1", "buildable_id": "safety_lab", "cell_x": 0, "cell_y": 0, "rotated": false}]
    state.models = [{
        "id": "eval_model_1", "name": "Test Model", "generation": 1, "architecture_tier": "small",
        "capability": 50.0, "reliability": 50.0, "safety_confidence": 50.0, "cost_efficiency": 50.0,
        "latency_efficiency": 50.0, "autonomy": 50.0, "interpretability": 50.0, "latent_risk": 50.0,
        "evals_completed": 0, "training_cost": 8000.0, "created_at": 1,
    }]
    state.pending_evaluations = {}

    var hidden_range: Vector2 = eval_mgr.latent_risk_range("eval_model_1")
    if not (is_equal_approx(hidden_range.x, 0.0) and is_equal_approx(hidden_range.y, 100.0)):
        push_error("latent_risk should be fully hidden ([0,100]) before any evaluation")
        quit(1)
        return
    var initial_cap_range: Vector2 = eval_mgr.visible_range("eval_model_1", "capability")
    var initial_width: float = initial_cap_range.y - initial_cap_range.x
    if initial_width <= 0.0:
        push_error("A regular stat should show an uncertainty range before any evaluation, not a single value")
        quit(1)
        return
    print("SMOKE_OK: unevaluated models show an uncertainty range and a fully hidden latent risk")

    var cash_before_request: float = state.cash
    var request_err: Error = eval_mgr.request_evaluation("eval_model_1")
    if request_err != OK or not is_equal_approx(state.cash, cash_before_request - eval_mgr.EVAL_COST):
        push_error("EvaluationManager.request_evaluation() did not deduct the eval cost (error %s)" % request_err)
        quit(1)
        return
    if int(state.pending_evaluations.get("eval_model_1", 0)) != 1:
        push_error("EvaluationManager.request_evaluation() did not record a pending evaluation session")
        quit(1)
        return
    print("SMOKE_OK: requesting an evaluation costs cash and queues a worker session")

    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var evaluator_id: String = String(state.staff[0].get("id", ""))
    var assign_err4: Error = task_mgr.assign(evaluator_id, "safety_audit", "lab_1", "eval_model_1")
    if assign_err4 != OK:
        push_error("Failed to assign evaluator to safety_audit targeting eval_model_1 (error %s)" % assign_err4)
        quit(1)
        return
    for i in 5:
        bus2.simulation_tick.emit(400)
    var model_after: Dictionary = state.models[0]
    if int(model_after.get("evals_completed", 0)) != 1:
        push_error("Completing a safety_audit session did not increase evals_completed")
        quit(1)
        return
    if int(state.pending_evaluations.get("eval_model_1", 0)) != 0:
        push_error("Completing the evaluation session did not clear the pending count")
        quit(1)
        return
    var narrowed_range: Vector2 = eval_mgr.visible_range("eval_model_1", "capability")
    var narrowed_width: float = narrowed_range.y - narrowed_range.x
    if narrowed_width >= initial_width:
        push_error("An evaluation should reduce uncertainty (range width should shrink)")
        quit(1)
        return
    var revealed_risk_range: Vector2 = eval_mgr.latent_risk_range("eval_model_1")
    if is_equal_approx(revealed_risk_range.x, 0.0) and is_equal_approx(revealed_risk_range.y, 100.0):
        push_error("latent_risk should be at least partially revealed after one evaluation")
        quit(1)
        return
    print("SMOKE_OK: repeated evals cost resources, reduce uncertainty, and partially reveal latent risk")

    for i in 10:
        if eval_mgr.can_request("eval_model_1"):
            eval_mgr.request_evaluation("eval_model_1")
            task_mgr.assign(evaluator_id, "safety_audit", "lab_1", "eval_model_1")
            for t in 5:
                bus2.simulation_tick.emit(400)
    var final_depth: int = int(state.models[0].get("evals_completed", 0))
    if final_depth > int(eval_mgr.MAX_EVAL_DEPTH):
        push_error("evals_completed exceeded MAX_EVAL_DEPTH (%d > %d)" % [final_depth, eval_mgr.MAX_EVAL_DEPTH])
        quit(1)
        return
    if eval_mgr.can_request("eval_model_1"):
        push_error("A model at max eval depth should no longer accept evaluation requests")
        quit(1)
        return
    print("SMOKE_OK: evaluation depth is capped, and a maxed-out model stops accepting further requests")

    state.staff = []
    state.buildings = []
    state.work_orders = []
    state.models = []
    state.pending_evaluations = {}

    # P16: release and rollout — deployment modes, staged rollout,
    # rollback, rate limit; affects user scale, compute, incident exposure.
    var release_mgr: Node = get_root().get_node("ReleaseManager")
    var deployment_mode_ids: Array = DeploymentModeCatalog.load_all().keys()
    if deployment_mode_ids.size() != 3:
        push_error("DeploymentModeCatalog should define exactly 3 deployment modes (got %d)" % deployment_mode_ids.size())
        quit(1)
        return
    if DeploymentModeCatalog.next_mode("internal") != "beta" or DeploymentModeCatalog.next_mode("beta") != "public" or not DeploymentModeCatalog.next_mode("public").is_empty():
        push_error("DeploymentModeCatalog.next_mode() should follow Internal -> Beta -> Public")
        quit(1)
        return
    print("SMOKE_OK: 3 deployment modes seeded in Internal -> Beta -> Public order")

    state.models = [{
        "id": "release_model_1", "name": "Release Test Model", "generation": 1, "architecture_tier": "small",
        "capability": 50.0, "reliability": 50.0, "safety_confidence": 50.0, "cost_efficiency": 50.0,
        "latency_efficiency": 50.0, "autonomy": 50.0, "interpretability": 50.0, "latent_risk": 50.0,
        "evals_completed": 0, "training_cost": 8000.0, "created_at": 1,
    }]
    state.deployments = []
    state.work_orders = []

    var deploy_err: Error = release_mgr.deploy("release_model_1")
    if deploy_err != OK or state.deployments.size() != 1:
        push_error("ReleaseManager.deploy() failed to create a deployment (error %s)" % deploy_err)
        quit(1)
        return
    var deployment_id: String = String(state.deployments[0].get("id", ""))
    if String(state.deployments[0].get("mode_id", "")) != "internal":
        push_error("A new deployment should start in Internal mode")
        quit(1)
        return
    if not is_equal_approx(release_mgr.total_user_scale(), 0.0):
        push_error("A freshly deployed (0%% rollout) release should have zero user scale so far")
        quit(1)
        return
    print("SMOKE_OK: deploying a model starts an Internal-mode deployment at 0% rollout")

    bus2.day_advanced.emit(state.calendar_day)
    var deployment_after_day: Dictionary = state.deployments[0]
    if not is_equal_approx(float(deployment_after_day.get("rollout_stage", 0.0)), 1.0):
        push_error("Internal mode has rollout_days=1, so one day should complete the rollout")
        quit(1)
        return
    var internal_exposure: float = release_mgr.total_incident_exposure()
    if internal_exposure <= 0.0:
        push_error("Deployment state should affect incident exposure (expected > 0 once live)")
        quit(1)
        return
    var internal_inference: float = release_mgr.total_inference_compute()
    if internal_inference <= 0.0:
        push_error("Deployment state should affect inference compute (expected > 0 once live)")
        quit(1)
        return
    if not is_equal_approx(state.compute_used, internal_inference):
        push_error("GameState.compute_used should include inference draw from active deployments")
        quit(1)
        return
    if release_mgr.total_user_scale() <= 0.0:
        push_error("Deployment state should affect user scale (expected > 0 after rollout completes)")
        quit(1)
        return
    print("SMOKE_OK: staged rollout completes over time and affects user scale, compute, and incident exposure")

    var promote_err: Error = release_mgr.promote(deployment_id)
    if promote_err != OK or String(state.deployments[0].get("mode_id", "")) != "beta":
        push_error("ReleaseManager.promote() failed to advance Internal -> Beta (error %s)" % promote_err)
        quit(1)
        return
    if not is_equal_approx(float(state.deployments[0].get("rollout_stage", 1.0)), 0.0):
        push_error("Promoting to a new mode should restart the staged rollout at 0%")
        quit(1)
        return
    if not is_equal_approx(release_mgr.total_user_scale(), 0.0):
        push_error("A freshly promoted deployment should have zero user scale until it rolls out again")
        quit(1)
        return
    print("SMOKE_OK: promoting Internal -> Beta restarts the staged rollout")

    release_mgr.set_rate_limit(deployment_id, 0.5)
    for i in 5:
        bus2.day_advanced.emit(state.calendar_day)
    var beta_mode_def: Dictionary = DeploymentModeCatalog.get_def("beta")
    var expected_beta_scale: float = float(beta_mode_def.get("base_user_scale", 0.0)) * 0.5
    if not is_equal_approx(release_mgr.total_user_scale(), expected_beta_scale):
        push_error("Rate limit slider should scale down user scale proportionally (expected %.1f, got %.1f)" % [expected_beta_scale, release_mgr.total_user_scale()])
        quit(1)
        return
    print("SMOKE_OK: the rate limit slider proportionally throttles user scale")

    var rollback_err: Error = release_mgr.rollback(deployment_id)
    if rollback_err != OK or not state.deployments.is_empty():
        push_error("ReleaseManager.rollback() failed to remove the deployment (error %s)" % rollback_err)
        quit(1)
        return
    if not is_equal_approx(release_mgr.total_user_scale(), 0.0) or not is_equal_approx(release_mgr.total_incident_exposure(), 0.0) or not is_equal_approx(state.compute_used, 0.0):
        push_error("Rolling back should zero out user scale, incident exposure, and inference compute")
        quit(1)
        return
    print("SMOKE_OK: rollback safely reverts user scale, incident exposure, and inference compute to zero")

    release_mgr.deploy("release_model_1")
    var save_deployment_id: String = String(state.deployments[0].get("id", ""))
    var deploy_save_err: Error = save_mgr.save_manual(0)
    state.deployments = []
    var deploy_load_err: Error = save_mgr.load_manual(0)
    if deploy_save_err != OK or deploy_load_err != OK or state.deployments.is_empty() or String(state.deployments[0].get("id", "")) != save_deployment_id:
        push_error("Deployments did not survive save/load (save error %s, load error %s)" % [deploy_save_err, deploy_load_err])
        quit(1)
        return
    print("SMOKE_OK: deployments persist across save/load")

    state.models = []
    state.deployments = []
    state.work_orders = []

    # P17: users, pricing, revenue — cohort demand, price elasticity,
    # inference cost. Revenue/cost traceable; no per-user simulation.
    var revenue_mgr: Node = get_root().get_node("RevenueManager")
    var segment_ids: Array = UserSegmentCatalog.ordered_ids()
    if segment_ids.size() != 3:
        push_error("UserSegmentCatalog should seed exactly 3 segments (hobbyist/developer/business), got %d" % segment_ids.size())
        quit(1)
        return
    var share_sum: float = 0.0
    for sid: String in segment_ids:
        share_sum += float(UserSegmentCatalog.get_def(sid).get("share_of_market", 0.0))
    if not is_equal_approx(share_sum, 1.0):
        push_error("Segment share_of_market should sum to 1.0 (got %.3f)" % share_sum)
        quit(1)
        return
    print("SMOKE_OK: 3 user segments seeded with shares summing to 1.0")

    state.models = [{
        "id": "revenue_model_1", "name": "Revenue Test Model", "generation": 1, "architecture_tier": "medium",
        "capability": 70.0, "reliability": 70.0, "safety_confidence": 70.0, "cost_efficiency": 70.0,
        "latency_efficiency": 70.0, "autonomy": 30.0, "interpretability": 60.0, "latent_risk": 30.0,
        "evals_completed": 0, "training_cost": 20000.0, "created_at": 1,
    }]
    state.deployments = []
    release_mgr.deploy("revenue_model_1")
    var revenue_deployment_id: String = String(state.deployments[0].get("id", ""))
    for i in 3:
        bus2.day_advanced.emit(state.calendar_day)

    revenue_mgr.set_price(revenue_deployment_id, 1.0)
    var breakdown_cheap: Dictionary = revenue_mgr.compute_breakdown(state.deployments[0])
    revenue_mgr.set_price(revenue_deployment_id, 7.5)
    var breakdown_expensive: Dictionary = revenue_mgr.compute_breakdown(state.deployments[0])
    if not (float(breakdown_cheap.get("total_users", 0.0)) > float(breakdown_expensive.get("total_users", 0.0))):
        push_error("Raising price should reduce demand (price elasticity)")
        quit(1)
        return
    print("SMOKE_OK: price elasticity — a higher price reduces cohort demand")

    var revenue: float = float(breakdown_expensive.get("total_revenue", 0.0))
    var cost: float = float(breakdown_expensive.get("total_cost", 0.0))
    var net: float = float(breakdown_expensive.get("net", 0.0))
    if not is_equal_approx(net, revenue - cost):
        push_error("net should always equal total_revenue - total_cost (traceability)")
        quit(1)
        return
    if not breakdown_expensive.has("segments") or (breakdown_expensive["segments"] as Dictionary).size() != 3:
        push_error("compute_breakdown() should report a per-segment breakdown for all 3 segments")
        quit(1)
        return
    print("SMOKE_OK: revenue and cost are individually traceable (net = revenue - cost, per-segment breakdown)")

    revenue_mgr.set_price(revenue_deployment_id, 3.0)
    var cash_before_tick: float = state.cash
    var expected_net: float = revenue_mgr.total_daily_net()
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_tick + expected_net):
        push_error("Daily revenue/cost net should be applied to cash on day_advanced")
        quit(1)
        return
    print("SMOKE_OK: daily net revenue is applied to cash")

    state.models = []
    state.deployments = []

    quit(0)
