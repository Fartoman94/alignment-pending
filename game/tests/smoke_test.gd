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
        "res://scenes/ending.tscn",
        "res://scenes/credits.tscn",
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
        "res://scenes/ending.tscn",
        "res://scenes/credits.tscn",
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
    # EconomyManager (P23) also reacts to day_advanced with rent/legal/support,
    # so the expected delta is payroll plus that ledger's other expenses, not
    # payroll alone.
    var economy_mgr_early: Node = get_root().get_node("EconomyManager")
    var other_daily_costs: float = float(economy_mgr_early.rent_cost()) + float(economy_mgr_early.legal_cost()) + float(economy_mgr_early.support_cost())
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_payroll - candidate_salary - other_daily_costs):
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
    # EconomyManager (P23) also reacts to day_advanced with rent/legal/support,
    # so the expected delta is revenue net minus that ledger's other expenses.
    var economy_mgr_mid: Node = get_root().get_node("EconomyManager")
    var other_daily_costs_mid: float = float(economy_mgr_mid.rent_cost()) + float(economy_mgr_mid.legal_cost()) + float(economy_mgr_mid.support_cost())
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_tick + expected_net - other_daily_costs_mid):
        push_error("Daily revenue/cost net should be applied to cash on day_advanced")
        quit(1)
        return
    print("SMOKE_OK: daily net revenue is applied to cash")

    state.models = []
    state.deployments = []

    # P18: incident engine — condition/weight/cooldown, choice resolution,
    # 20 original incidents, high severity pauses, history records
    # causes/choice.
    var incident_mgr: Node = get_root().get_node("IncidentManager")
    var incident_ids: Array = IncidentCatalog.ordered_ids()
    if incident_ids.size() != 20:
        push_error("IncidentCatalog should seed exactly 20 incidents (got %d)" % incident_ids.size())
        quit(1)
        return
    print("SMOKE_OK: IncidentCatalog seeds 20 original incidents")

    state.deployments = []
    state.staff = []
    state.models = []
    state.safety_debt = 0.0
    state.public_trust = 50.0
    state.cash = 100000.0
    state.pending_incidents = []
    state.incident_history = []
    state.incident_cooldowns = {}
    state.paused = false

    if incident_mgr.eligible_incidents().has("confidently_incorrect"):
        push_error("An incident whose prerequisites are unmet should not be eligible")
        quit(1)
        return
    state.models = [{
        "id": "inc_model", "name": "Inc Model", "generation": 1, "architecture_tier": "small",
        "capability": 50.0, "reliability": 50.0, "safety_confidence": 50.0, "cost_efficiency": 50.0,
        "latency_efficiency": 50.0, "autonomy": 20.0, "interpretability": 50.0, "latent_risk": 20.0,
        "evals_completed": 0, "training_cost": 8000.0, "created_at": 1,
    }]
    var release_mgr3: Node = get_root().get_node("ReleaseManager")
    release_mgr3.deploy("inc_model")
    if not incident_mgr.eligible_incidents().has("confidently_incorrect"):
        push_error("An incident should become eligible once its prerequisites are satisfied")
        quit(1)
        return
    print("SMOKE_OK: incident eligibility is gated by data-driven prerequisites")

    incident_mgr._trigger("data_leak_scare")
    if state.pending_incidents.is_empty() or not state.paused:
        push_error("Triggering a P0 (severity 0) incident should pause the game")
        quit(1)
        return
    var pending_entry: Dictionary = state.pending_incidents[0]
    var pending_id: String = String(pending_entry.get("id", ""))
    if not pending_entry.has("state_snapshot") or (pending_entry["state_snapshot"] as Dictionary).is_empty():
        push_error("A triggered incident should record a causal state snapshot")
        quit(1)
        return
    print("SMOKE_OK: a high-severity (P0) incident pauses the game and records its trigger state")

    if not (int(state.incident_cooldowns.get("data_leak_scare", 0)) > state.calendar_day):
        push_error("Triggering an incident should start its cooldown")
        quit(1)
        return
    if incident_mgr.eligible_incidents().has("data_leak_scare"):
        push_error("An incident on cooldown should not be eligible again immediately")
        quit(1)
        return
    print("SMOKE_OK: triggering an incident starts its cooldown, making it ineligible until it expires")

    var choices: Array = pending_entry.get("choices", [])
    var chosen_choice: Dictionary = choices[0]
    var chosen_choice_id: String = String(chosen_choice.get("id", ""))
    var cash_before_resolve: float = state.cash
    var expected_cash_effect: float = float((chosen_choice.get("effects", {}) as Dictionary).get("cash", 0.0))
    var resolve_err: Error = incident_mgr.resolve(pending_id, chosen_choice_id)
    if resolve_err != OK or not state.pending_incidents.is_empty():
        push_error("IncidentManager.resolve() failed to resolve the pending incident (error %s)" % resolve_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_resolve + expected_cash_effect):
        push_error("Resolving a choice should apply its cash effect")
        quit(1)
        return
    if state.incident_history.is_empty():
        push_error("Resolving an incident should record it in history")
        quit(1)
        return
    var history_entry: Dictionary = state.incident_history[state.incident_history.size() - 1]
    if String(history_entry.get("choice_id", "")) != chosen_choice_id or not history_entry.has("state_snapshot"):
        push_error("Incident history should record both the cause (state snapshot) and the player's choice")
        quit(1)
        return
    print("SMOKE_OK: resolving an incident applies the choice's effects and history records causes/choice")

    var save_err_inc: Error = save_mgr.save_manual(0)
    var history_len_before: int = state.incident_history.size()
    state.incident_history = []
    state.incident_cooldowns = {}
    var load_err_inc: Error = save_mgr.load_manual(0)
    if save_err_inc != OK or load_err_inc != OK or state.incident_history.size() != history_len_before or state.incident_cooldowns.is_empty():
        push_error("Incident history/cooldowns did not survive save/load (save error %s, load error %s)" % [save_err_inc, load_err_inc])
        quit(1)
        return
    print("SMOKE_OK: incident history and cooldowns persist across save/load")

    state.models = []
    state.deployments = []
    state.pending_incidents = []
    state.incident_history = []
    state.incident_cooldowns = {}
    state.paused = false

    # P19: trust and communication — hype debt, causes-visible tooltips,
    # PR cannot erase severe evidence.
    var comm_mgr: Node = get_root().get_node("CommunicationManager")
    var comm_action_ids: Array = CommunicationActionCatalog.ordered_ids()
    if comm_action_ids.size() != 3:
        push_error("CommunicationActionCatalog should seed exactly 3 actions (got %d)" % comm_action_ids.size())
        quit(1)
        return
    print("SMOKE_OK: CommunicationActionCatalog seeds 3 communication actions")

    state.cash = 100000.0
    state.public_trust = 50.0
    state.hype_debt = 0.0
    state.communication_cooldowns = {}
    state.communication_history = []
    state.incident_history = []
    state.calendar_day = 1

    var cash_before_action: float = state.cash
    var trust_before_action: float = state.public_trust
    var action_def: Dictionary = CommunicationActionCatalog.get_def("marketing_campaign")
    var perform_err: Error = comm_mgr.perform("marketing_campaign")
    if perform_err != OK:
        push_error("CommunicationManager.perform() failed for an affordable, off-cooldown action (error %s)" % perform_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_action - float(action_def.get("cost", 0.0))):
        push_error("Performing a communication action should deduct its cost")
        quit(1)
        return
    if not is_equal_approx(state.public_trust, trust_before_action + float(action_def.get("trust_delta", 0.0))):
        push_error("Performing a communication action should apply its trust_delta")
        quit(1)
        return
    if not is_equal_approx(state.hype_debt, float(action_def.get("hype_debt_delta", 0.0))):
        push_error("A marketing campaign should accrue hype debt")
        quit(1)
        return
    if comm_mgr.can_perform("marketing_campaign"):
        push_error("An action just performed should be on cooldown")
        quit(1)
        return
    print("SMOKE_OK: performing a communication action costs cash, moves trust, accrues hype debt, and starts a cooldown")

    var hype_before_tick: float = state.hype_debt
    var trust_before_tick: float = state.public_trust
    bus2.day_advanced.emit(state.calendar_day)
    var expected_conversion: float = hype_before_tick * float(comm_mgr.HYPE_CONVERSION_RATE)
    if not is_equal_approx(state.hype_debt, hype_before_tick - expected_conversion):
        push_error("Hype debt should decay by converting into trust loss daily")
        quit(1)
        return
    if not is_equal_approx(state.public_trust, trust_before_tick - expected_conversion):
        push_error("Hype debt conversion should reduce public trust by the converted amount")
        quit(1)
        return
    print("SMOKE_OK: unaddressed hype debt converts to trust loss over time")

    state.incident_history = [{
        "id": "inc_test", "incident_id": "data_leak_scare", "category": "privacy", "severity": 0,
        "title": "Data Leak Scare", "body": "...", "choices": [], "triggered_day": 1,
        "state_snapshot": {}, "choice_id": "stonewall", "resolved_day": 1,
        "effects_applied": {"public_trust": -10.0, "safety_debt": 3.0},
    }]
    var history_before: Array = state.incident_history.duplicate(true)
    state.communication_cooldowns = {}
    for action_id2: String in comm_action_ids:
        if comm_mgr.can_perform(action_id2):
            comm_mgr.perform(action_id2)
    if state.incident_history != history_before:
        push_error("A communication action mutated incident_history — PR must never erase evidence")
        quit(1)
        return
    if float((state.incident_history[0] as Dictionary).get("effects_applied", {}).get("public_trust", 0.0)) != -10.0:
        push_error("The recorded incident's effect must remain exactly as it happened")
        quit(1)
        return
    print("SMOKE_OK: PR actions never mutate incident_history — severe evidence cannot be erased")

    var causes: Array = comm_mgr.recent_trust_causes(10)
    var has_incident_cause: bool = false
    var has_comm_cause: bool = false
    for c: Variant in causes:
        var cause: Dictionary = c
        if String(cause.get("label", "")) == "Data Leak Scare":
            has_incident_cause = true
        if float(cause.get("delta", 0.0)) > 0.0:
            has_comm_cause = true
    if not has_incident_cause or not has_comm_cause:
        push_error("recent_trust_causes() should surface both incident and communication contributions")
        quit(1)
        return
    print("SMOKE_OK: recent trust causes are visible and traceable to their source (incident or PR action)")

    var save_err_comm: Error = save_mgr.save_manual(0)
    var hype_before_reload: float = state.hype_debt
    state.hype_debt = 0.0
    state.communication_history = []
    state.communication_cooldowns = {}
    var load_err_comm: Error = save_mgr.load_manual(0)
    if save_err_comm != OK or load_err_comm != OK or not is_equal_approx(state.hype_debt, hype_before_reload) or state.communication_history.is_empty():
        push_error("Hype debt and communication history did not survive save/load (save error %s, load error %s)" % [save_err_comm, load_err_comm])
        quit(1)
        return
    print("SMOKE_OK: hype debt and communication history persist across save/load")

    state.public_trust = 43.0
    state.hype_debt = 0.0
    state.communication_history = []
    state.communication_cooldowns = {}
    state.incident_history = []

    # P20/P26: rival companies — doctrine, research pace, launches,
    # deterministic effect on board/market events, catch-up mechanics, and
    # market share across the full 3-5 rival field.
    var rival_mgr: Node = get_root().get_node("RivalManager")
    var doctrine_ids: Array = RivalDoctrineCatalog.load_all().keys()
    if doctrine_ids.size() != 6:
        push_error("RivalDoctrineCatalog should seed exactly 6 doctrines (got %d)" % doctrine_ids.size())
        quit(1)
        return
    print("SMOKE_OK: RivalDoctrineCatalog seeds 6 doctrines")

    var forbidden_rival_terms: Array[String] = ["openai", "anthropic", "google", "deepmind", "meta", "microsoft", "xai", "mistral", "cohere", "claude", "gpt", "gemini", "llama"]
    for rival_name: String in rival_mgr.RIVAL_NAMES:
        var lowered_name: String = rival_name.to_lower()
        for term: String in forbidden_rival_terms:
            if lowered_name.contains(term):
                push_error("Rival name '%s' must not reference a real AI company ('%s')" % [rival_name, term])
                quit(1)
                return
    print("SMOKE_OK: no rival is named after or mapped to a real company")

    state.campaign_seed = 24680
    sim.reset_rng_streams()
    rival_mgr.generate_rival()
    if state.rivals.size() != rival_mgr.RIVAL_NAMES.size():
        push_error("generate_rival() should create one rival per RIVAL_NAMES entry (3-5 procedural rivals)")
        quit(1)
        return
    var names_seen_a: Dictionary = {}
    for r: Variant in state.rivals:
        var rival_a: Dictionary = r
        names_seen_a[String(rival_a.get("name", ""))] = true
    if names_seen_a.size() != state.rivals.size():
        push_error("Every rival should have a unique name")
        quit(1)
        return
    var roster_a: Array = []
    for r2: Variant in state.rivals:
        var rival_a2: Dictionary = r2
        roster_a.append([rival_a2.get("id"), rival_a2.get("name"), rival_a2.get("doctrine")])

    state.campaign_seed = 24680
    sim.reset_rng_streams()
    rival_mgr.generate_rival()
    var roster_b: Array = []
    for r3: Variant in state.rivals:
        var rival_b: Dictionary = r3
        roster_b.append([rival_b.get("id"), rival_b.get("name"), rival_b.get("doctrine")])
    if roster_a != roster_b:
        push_error("The same seed should deterministically generate the same rival roster (ids, names, doctrines)")
        quit(1)
        return
    print("SMOKE_OK: 3-5 procedural rivals are generated with unique names, deterministic per seed")

    state.staff = []
    state.deployments = []
    state.pending_incidents = []
    state.incident_history = []
    state.incident_cooldowns = {}
    if incident_mgr.eligible_incidents().has("board_says_ship"):
        push_error("board_says_ship should not be eligible before any rival has launched anything")
        quit(1)
        return

    var safety_guard: int = 0
    while rival_mgr.leading_generation() < 3 and safety_guard < 500:
        bus2.day_advanced.emit(state.calendar_day)
        safety_guard += 1
    if rival_mgr.leading_generation() != 3:
        push_error("The leading rival should be able to reach generation 3 (got %d after %d ticks)" % [rival_mgr.leading_generation(), safety_guard])
        quit(1)
        return
    if state.rival_launch_history.is_empty():
        push_error("rival_launch_history should record launches")
        quit(1)
        return
    for h: Variant in state.rival_launch_history:
        var launch_entry: Dictionary = h
        if rival_mgr.find_rival(String(launch_entry.get("rival_id", ""))).is_empty():
            push_error("Every launch history entry should reference a real rival_id")
            quit(1)
            return
    print("SMOKE_OK: rivals race independently and the field can reach generation 3")

    # Catch-up mechanic: a rival behind the leader gets a shorter effective
    # launch cycle than one at the front, bounded so it's never more than
    # 2x base pace.
    var leader_gen: int = rival_mgr.leading_generation()
    var any_doctrine_id: String = String(doctrine_ids[0])
    var duration_at_front: int = rival_mgr.effective_launch_days(any_doctrine_id, leader_gen)
    var duration_far_behind: int = rival_mgr.effective_launch_days(any_doctrine_id, 0)
    if leader_gen > 0 and duration_far_behind > duration_at_front:
        push_error("A rival far behind the leader should launch at least as fast as one at the front (catch-up mechanic)")
        quit(1)
        return
    var floor_multiplier: float = rival_mgr.catch_up_multiplier(-1000)
    if floor_multiplier < float(rival_mgr.CATCH_UP_FLOOR) - 0.001:
        push_error("The catch-up speedup must be bounded by CATCH_UP_FLOOR, not unbounded")
        quit(1)
        return
    print("SMOKE_OK: rivals behind the pack catch up faster, bounded so it's never more than 2x base pace")

    # The random incident picker may itself have already triggered
    # board_says_ship during those ticks (it became eligible partway
    # through), which would put it on cooldown and confound this check.
    # Reset cooldowns so this specifically re-tests the prerequisite gate.
    state.incident_cooldowns = {}
    if not incident_mgr.eligible_incidents().has("board_says_ship"):
        push_error("board_says_ship should become eligible once a rival has launched (deterministic board/market effect)")
        quit(1)
        return
    print("SMOKE_OK: rival launches deterministically affect board/market incident eligibility")

    var expected_pressure: float = 0.0
    for r4: Variant in state.rivals:
        var rival_c: Dictionary = r4
        var doctrine_def_c: Dictionary = RivalDoctrineCatalog.get_def(String(rival_c.get("doctrine", "")))
        expected_pressure += float(rival_c.get("generation", 0)) * float(doctrine_def_c.get("market_pressure_multiplier", 1.0))
    if not is_equal_approx(rival_mgr.rival_pressure(), expected_pressure):
        push_error("rival_pressure() should be the deterministic sum of every rival's own generation-and-doctrine pressure")
        quit(1)
        return
    print("SMOKE_OK: rival market pressure is a deterministic function of every rival's generation and doctrine")

    var shares: Dictionary = rival_mgr.market_shares()
    var share_total: float = float(shares.get("player", 0.0))
    for r5: Variant in state.rivals:
        share_total += float(shares.get(String((r5 as Dictionary).get("id", "")), 0.0))
    if not is_equal_approx(share_total, 1.0):
        push_error("market_shares() must sum consistently to 1.0 across the player and every rival (got %.4f)" % share_total)
        quit(1)
        return
    print("SMOKE_OK: market share sums consistently to 100% across the player and every rival")

    state.rivals = []
    state.rival_launch_history = []
    state.incident_cooldowns = {}
    state.pending_incidents = []
    state.incident_history = []

    # P21: regulator track MVP — pressure meter, audit event, disclosure
    # choice; pressure responds to scale/incidents; audit has clear
    # requirements.
    var regulator_mgr: Node = get_root().get_node("RegulatorManager")
    var reqs: Array = regulator_mgr.requirements()
    if reqs.is_empty():
        push_error("The regulator's audit must have clear (non-empty) requirements")
        quit(1)
        return
    print("SMOKE_OK: the regulator has a name and a clear, non-empty requirements checklist")

    state.regulatory_pressure = 0.0
    state.active_audit = {}
    state.audit_history = []
    state.safety_debt = 20.0
    state.deployments = []
    state.models = [{
        "id": "reg_model_1", "name": "Reg Model", "generation": 1, "architecture_tier": "medium",
        "capability": 70.0, "reliability": 70.0, "safety_confidence": 70.0, "cost_efficiency": 70.0,
        "latency_efficiency": 70.0, "autonomy": 30.0, "interpretability": 60.0, "latent_risk": 30.0,
        "evals_completed": 0, "training_cost": 20000.0, "created_at": 1,
    }]
    var release_mgr4: Node = get_root().get_node("ReleaseManager")
    release_mgr4.deploy("reg_model_1")
    for i in 3:
        bus2.day_advanced.emit(state.calendar_day)
    if state.regulatory_pressure <= 0.0:
        push_error("Regulatory pressure should respond to deployed scale and safety debt")
        quit(1)
        return
    print("SMOKE_OK: regulatory pressure responds to deployed scale and safety debt")

    var pressure_before_incident: float = state.regulatory_pressure
    incident_mgr._trigger("data_leak_scare")
    var pending: Dictionary = state.pending_incidents[state.pending_incidents.size() - 1]
    incident_mgr.resolve(String(pending.get("id", "")), "stonewall")
    if not (state.regulatory_pressure > pressure_before_incident):
        push_error("An incident choice with a regulatory_pressure effect should move the pressure meter")
        quit(1)
        return
    print("SMOKE_OK: regulatory pressure responds to incident choices")

    state.regulatory_pressure = 49.0
    state.active_audit = {}
    state.safety_debt = 100.0  # guarantees this tick's debt_pressure alone crosses the threshold
    bus2.day_advanced.emit(state.calendar_day)
    if state.active_audit.is_empty():
        push_error("Crossing the audit threshold should trigger an audit")
        quit(1)
        return
    var audit_reqs: Array = state.active_audit.get("requirements", [])
    if audit_reqs.is_empty() or audit_reqs != reqs:
        push_error("The triggered audit should carry the regulator's clear requirements checklist")
        quit(1)
        return
    print("SMOKE_OK: crossing the pressure threshold triggers an audit with clear requirements")

    var pressure_before_resolve: float = state.regulatory_pressure
    var cash_before_resolve2: float = state.cash
    var resolve_audit_err: Error = regulator_mgr.resolve_audit("full_disclosure")
    if resolve_audit_err != OK or not state.active_audit.is_empty():
        push_error("resolve_audit() should clear the active audit (error %s)" % resolve_audit_err)
        quit(1)
        return
    if not (state.regulatory_pressure < pressure_before_resolve):
        push_error("Full disclosure should meaningfully reduce regulatory pressure")
        quit(1)
        return
    if not (state.cash < cash_before_resolve2):
        push_error("Full disclosure should cost cash")
        quit(1)
        return
    if state.audit_history.is_empty() or String((state.audit_history[state.audit_history.size() - 1] as Dictionary).get("disclosure_choice", "")) != "full_disclosure":
        push_error("Resolving an audit should record the disclosure choice in history")
        quit(1)
        return
    print("SMOKE_OK: resolving an audit applies the disclosure choice's effects and records history")

    var save_err_reg: Error = save_mgr.save_manual(0)
    var pressure_before_reload: float = state.regulatory_pressure
    state.regulatory_pressure = 0.0
    state.audit_history = []
    var load_err_reg: Error = save_mgr.load_manual(0)
    if save_err_reg != OK or load_err_reg != OK or not is_equal_approx(state.regulatory_pressure, pressure_before_reload) or state.audit_history.is_empty():
        push_error("Regulatory pressure and audit history did not survive save/load (save error %s, load error %s)" % [save_err_reg, load_err_reg])
        quit(1)
        return
    print("SMOKE_OK: regulatory pressure and audit history persist across save/load")

    state.models = []
    state.deployments = []
    state.regulatory_pressure = 0.0
    state.active_audit = {}
    state.audit_history = []
    state.pending_incidents = []
    state.incident_history = []
    state.incident_cooldowns = {}
    state.safety_debt = 17.0

    # P22: vertical slice ending — milestones, deterministic epilogue
    # selection, ending trigger, credits contain no assistant references.
    # 3 prototype epilogues from P22, plus "bankruptcy" added by P23.
    var epilogue_ids: Array = EpilogueCatalog.load_all().keys()
    if epilogue_ids.size() != 4 or not epilogue_ids.has("bankruptcy"):
        push_error("EpilogueCatalog should seed 3 prototype epilogues plus bankruptcy (got %d: %s)" % [epilogue_ids.size(), epilogue_ids])
        quit(1)
        return
    print("SMOKE_OK: EpilogueCatalog seeds 3 prototype epilogues plus the bankruptcy epilogue")

    var ending_mgr: Node = get_root().get_node("EndingManager")
    state.buildings = []
    state.staff = []
    state.models = []
    state.deployments = []
    state.incident_history = []
    state.next_building_id = 1
    state.next_staff_id = 1
    state.next_deployment_id = 1
    var milestones_empty: Dictionary = ending_mgr.compute_milestones()
    for key: String in milestones_empty:
        if bool(milestones_empty[key]):
            push_error("Milestone '%s' should start false with no history" % key)
            quit(1)
            return
    state.next_building_id = 2
    state.next_staff_id = 2
    state.models = [{"id": "m"}]
    state.next_deployment_id = 2
    state.incident_history = [{"id": "i"}]
    var milestones_full: Dictionary = ending_mgr.compute_milestones()
    for key2: String in milestones_full:
        if not bool(milestones_full[key2]):
            push_error("Milestone '%s' should become true once its underlying state exists" % key2)
            quit(1)
            return
    print("SMOKE_OK: milestones are correctly derived from existing campaign state")

    state.ending_id = ""
    state.paused = false
    state.public_trust = 60.0
    state.safety_debt = 10.0
    state.cash = 0.0
    state.models = []
    state.calendar_day = int(ending_mgr.ENDING_DAY_TRIGGER)
    bus2.day_advanced.emit(state.calendar_day)
    if state.ending_id != "steady_hand" or not state.paused:
        push_error("Expected the 'steady_hand' ending with high trust/low safety debt, got '%s' (paused=%s)" % [state.ending_id, state.paused])
        quit(1)
        return
    print("SMOKE_OK: reaching the ending day triggers a deterministic epilogue and pauses the game")

    state.ending_id = ""
    state.public_trust = 10.0
    state.safety_debt = 80.0
    state.cash = 200000.0
    bus2.day_advanced.emit(state.calendar_day)
    if state.ending_id != "runaway_growth":
        push_error("Expected the 'runaway_growth' ending for high cash/low trust, got '%s'" % state.ending_id)
        quit(1)
        return

    state.ending_id = ""
    state.public_trust = 10.0
    state.safety_debt = 80.0
    state.cash = 0.0
    state.models = []
    bus2.day_advanced.emit(state.calendar_day)
    if state.ending_id != "grounded_struggle":
        push_error("Expected the 'grounded_struggle' ending as the fallback, got '%s'" % state.ending_id)
        quit(1)
        return
    print("SMOKE_OK: the three epilogues are chosen deterministically from final state")

    var credits_packed: PackedScene = load("res://scenes/credits.tscn")
    var credits_inst: Node = credits_packed.instantiate()
    get_root().add_child(credits_inst)
    await process_frame
    var roles_text: String = String(credits_inst.get_node("Panel/Margin/VBox/RolesLabel").text).to_lower()
    var forbidden_terms: Array[String] = ["claude", "anthropic", "chatgpt", "openai", "ai assistant", "language model", "copilot"]
    var found_forbidden: String = ""
    for term: String in forbidden_terms:
        if roles_text.contains(term):
            found_forbidden = term
            break
    credits_inst.queue_free()
    await process_frame
    if not found_forbidden.is_empty():
        push_error("Credits must contain project team only, no assistant joke credits (found '%s')" % found_forbidden)
        quit(1)
        return
    print("SMOKE_OK: credits contain project team only, no assistant/AI joke credits")

    state.ending_id = ""
    state.paused = false
    state.public_trust = 43.0
    state.safety_debt = 17.0
    state.cash = 184200.0
    state.buildings = []
    state.staff = []
    state.models = []
    state.deployments = []
    state.incident_history = []
    state.next_building_id = 1
    state.next_staff_id = 1
    state.next_deployment_id = 1

    # P23: economy production balance — rent/legal/support, runway
    # forecast, bankruptcy recovery window.
    var economy_mgr: Node = get_root().get_node("EconomyManager")
    state.models = []
    state.deployments = []
    state.staff = []
    state.buildings = []
    state.work_orders = []
    # The BuildController instance from the P12 compute/power test was freed
    # after that block, so this cached field is stale and nothing is left to
    # deduct it from cash — zero it out so the ledger doesn't forecast a
    # cost that will never actually be applied.
    state.daily_infrastructure_cost = 0.0
    state.cash = 100000.0
    state.bankruptcy_day = -1
    state.ending_id = ""
    state.paused = false
    # Stay well below EndingManager.ENDING_DAY_TRIGGER so the automatic
    # day-30 epilogue doesn't fire mid-sequence and consume ending_id before
    # the bankruptcy-window test below gets to check it.
    state.calendar_day = 1

    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)

    var cash_before_tick2: float = state.cash
    var ledger: Dictionary = economy_mgr.daily_ledger()
    var expected_net2: float = float(ledger.get("net", 0.0))
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_tick2 + expected_net2):
        push_error("Forecast ledger did not match the actual cash delta after one day (expected net %.4f, got %.4f)" % [expected_net2, state.cash - cash_before_tick2])
        quit(1)
        return
    print("SMOKE_OK: the daily ledger matches the actual cash change within rounding")

    var forecast5: float = economy_mgr.forecast_cash_at(5)
    for i in 5:
        bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, forecast5):
        push_error("5-day forecast (%.4f) did not match actual cash after 5 days (%.4f)" % [forecast5, state.cash])
        quit(1)
        return
    print("SMOKE_OK: the runway forecast matches the ledger over multiple days within rounding")

    state.cash = -10.0
    state.bankruptcy_day = -1
    bus2.day_advanced.emit(state.calendar_day)
    if state.bankruptcy_day < 0:
        push_error("Going negative should start the bankruptcy recovery window")
        quit(1)
        return

    state.cash = 5000.0
    bus2.day_advanced.emit(state.calendar_day)
    if state.bankruptcy_day != -1:
        push_error("Recovering cash before the window expires should clear bankruptcy")
        quit(1)
        return
    print("SMOKE_OK: bankruptcy has a recovery window, and recovering cash clears it")

    state.cash = -10.0
    state.bankruptcy_day = -1
    state.ending_id = ""
    state.paused = false
    bus2.day_advanced.emit(state.calendar_day)
    var recovery_days: int = int(economy_mgr.BANKRUPTCY_RECOVERY_DAYS)
    for i in recovery_days:
        state.calendar_day += 1
        state.cash = -10.0  # never recovers
        bus2.day_advanced.emit(state.calendar_day)
        if not state.ending_id.is_empty():
            break
    if state.ending_id != "bankruptcy":
        push_error("Exhausting the recovery window while still in the red should trigger the bankruptcy ending (got '%s')" % state.ending_id)
        quit(1)
        return
    print("SMOKE_OK: exhausting the recovery window while still bankrupt ends the campaign")

    state.ending_id = ""
    state.paused = false
    state.bankruptcy_day = -1
    state.cash = 184200.0
    state.staff = []
    state.models = []
    state.deployments = []
    state.buildings = []
    state.work_orders = []

    # P24: staff depth — traits, promotion/leadership, burnout, resignation.
    state.staff = []
    state.buildings = []
    state.work_orders = []
    state.cash = 100000.0

    staff_mgr.refresh_candidates()
    for candidate: Variant in staff_mgr.candidates:
        var candidate_traits: Array = (candidate as Dictionary).get("traits", [])
        if candidate_traits.size() > int(staff_mgr.MAX_TRAITS_PER_CANDIDATE):
            push_error("Generated candidate has more traits than MAX_TRAITS_PER_CANDIDATE")
            quit(1)
            return
        for trait_id: Variant in candidate_traits:
            if StaffTraitCatalog.get_def(String(trait_id)).is_empty():
                push_error("Generated candidate has an unknown trait id '%s'" % trait_id)
                quit(1)
                return
    print("SMOKE_OK: generated candidates carry a bounded number of valid traits")

    staff_mgr.hire(0)
    var prodigy_id: String = String(state.staff[0].get("id", ""))
    # "researcher" has primary_skill "capability" (data/staff_roles.json) —
    # pinned explicitly so this test doesn't depend on which role the RNG
    # happened to generate for candidate 0.
    state.staff[0]["role"] = "researcher"
    state.staff[0]["skills"] = {"capability": 50, "engineering": 50, "operations": 50, "safety": 50, "communication": 50}
    state.staff[0]["traits"] = ["prodigy"]  # capability +15, per data/staff_traits.json
    var prodigy_effective: int = staff_mgr.effective_skill(prodigy_id, "capability")
    if prodigy_effective != 65:
        push_error("Trait skill_deltas should shift effective_skill by exactly the trait's bounded delta (expected 65, got %d)" % prodigy_effective)
        quit(1)
        return
    if staff_mgr.effective_skill(prodigy_id, "engineering") != 50:
        push_error("A trait should only affect the skills it names, not unrelated ones")
        quit(1)
        return
    print("SMOKE_OK: traits shift effective_skill by their bounded skill_deltas, and only for the skills they name")

    staff_mgr.candidates.clear()
    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var lead_candidate_id: String = String(state.staff[1].get("id", ""))
    state.staff[1]["role"] = "researcher"
    state.staff[1]["skills"] = {"capability": 90, "engineering": 90, "operations": 90, "safety": 90, "communication": 90}
    state.staff[1]["is_lead"] = false

    var before_leadership: int = staff_mgr.effective_skill(prodigy_id, "capability")
    var lead_promote_err: Error = staff_mgr.promote(lead_candidate_id)
    if lead_promote_err != OK:
        push_error("Promoting a qualified staff member to department lead failed unexpectedly (error %s)" % lead_promote_err)
        quit(1)
        return
    var after_leadership: int = staff_mgr.effective_skill(prodigy_id, "capability")
    if after_leadership - before_leadership != int(staff_mgr.LEADERSHIP_SKILL_BONUS):
        push_error("Promoting a department lead should grant every member of that department exactly LEADERSHIP_SKILL_BONUS (expected +%d, got +%d)" % [int(staff_mgr.LEADERSHIP_SKILL_BONUS), after_leadership - before_leadership])
        quit(1)
        return
    var second_promote_err: Error = staff_mgr.promote(prodigy_id)
    if second_promote_err == OK:
        push_error("A department should only ever have one promoted lead at a time")
        quit(1)
        return
    print("SMOKE_OK: promoting a department lead grants a bounded, department-wide leadership bonus, and only one lead per department")

    state.staff[0]["assigned_task"] = "fake_wo_for_fatigue_test"
    state.staff[0]["fatigue"] = 0.0
    state.staff[0]["traits"] = []
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(float(state.staff[0].get("fatigue", 0.0)), staff_mgr.FATIGUE_GAIN_PER_DAY_ASSIGNED):
        push_error("An assigned staff member should gain fatigue at FATIGUE_GAIN_PER_DAY_ASSIGNED per day (got %s)" % state.staff[0].get("fatigue"))
        quit(1)
        return
    state.staff[0]["assigned_task"] = ""
    var fatigue_before_recovery: float = float(state.staff[0].get("fatigue", 0.0))
    bus2.day_advanced.emit(state.calendar_day)
    if not (float(state.staff[0].get("fatigue", 0.0)) < fatigue_before_recovery):
        push_error("An idle staff member's fatigue should recover, not stay flat or increase")
        quit(1)
        return
    print("SMOKE_OK: fatigue rises while assigned to work and recovers while idle")

    state.staff[0]["fatigue"] = 100.0
    state.staff[0]["morale"] = 80.0
    state.staff[0]["relationships"] = []
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(float(state.staff[0].get("morale", 0.0)), 80.0 - staff_mgr.MORALE_DECAY_HIGH_FATIGUE):
        push_error("Sustained high fatigue should decay morale by exactly MORALE_DECAY_HIGH_FATIGUE (got %s)" % state.staff[0].get("morale"))
        quit(1)
        return
    print("SMOKE_OK: sustained high fatigue erodes morale by a bounded daily amount")

    if state.staff[0].get("relationships", []).size() < 1 or state.staff[1].get("relationships", []).size() < 1:
        push_error("Coworkers in the same department should accrue a relationship entry with each other over time")
        quit(1)
        return
    var rel_affinity: float = float((state.staff[0]["relationships"][0] as Dictionary).get("affinity", -999.0))
    if not is_equal_approx(rel_affinity, staff_mgr.RELATIONSHIP_STEP):
        push_error("A fresh relationship should start at exactly RELATIONSHIP_STEP (got %s)" % rel_affinity)
        quit(1)
        return
    print("SMOKE_OK: department coworkers accrue a bounded, symmetric relationship affinity over time")

    # Resignation must never soft-lock hiring: assign the low-morale staffer
    # to a real task (so we can verify the reservation is cleanly freed),
    # then force morale under threshold and tick until they resign.
    state.buildings = [{"id": "b_p24_desk", "buildable_id": "desk"}]
    state.work_orders = []
    state.staff[0]["assigned_task"] = ""
    var resign_assign_err: Error = task_mgr.assign(prodigy_id, "research_sprint", "b_p24_desk")
    if resign_assign_err != OK:
        push_error("Could not assign the resignation-test staffer to a real task (error %s)" % resign_assign_err)
        quit(1)
        return
    state.staff[0]["morale"] = 0.0
    state.staff[0]["fatigue"] = 0.0

    var resigned: bool = false
    var resign_guard: int = 0
    while resign_guard < 400 and not resigned:
        state.staff[0]["morale"] = 0.0  # never recovers, guarantees eligibility every roll
        bus2.day_advanced.emit(state.calendar_day)
        resigned = staff_mgr.find(prodigy_id).is_empty()
        resign_guard += 1
    if not resigned:
        push_error("The low-morale staffer never resigned after %d days (RESIGNATION_CHANCE_PER_DAY may be miscalibrated)" % resign_guard)
        quit(1)
        return
    if not task_mgr.find_order_for_staff(prodigy_id).is_empty():
        push_error("Resigning should free the staffer's in-progress work order, not leave it dangling")
        quit(1)
        return
    if task_mgr.is_building_reserved("b_p24_desk"):
        push_error("Resigning should free the building the staffer had reserved")
        quit(1)
        return
    if staff_mgr.candidates.is_empty():
        push_error("The candidate pool must never be left empty — resignation must not soft-lock hiring")
        quit(1)
        return
    var rehire_err: Error = staff_mgr.hire(0)
    if rehire_err != OK:
        push_error("Hiring after a resignation should still work (no soft-lock)")
        quit(1)
        return
    print("SMOKE_OK: resignation frees the staffer's task/building reservation and never soft-locks hiring")

    state.staff = []
    state.buildings = []
    state.work_orders = []
    state.cash = 184200.0

    # P25: board and funding rounds — valuation, staged funding rounds,
    # board pressure/demands (a decision, never an instant ending).
    var board_mgr: Node = get_root().get_node("BoardManager")
    state.ending_id = ""
    state.paused = false
    state.cash = 0.0
    state.board_control_pct = 100.0
    state.board_pressure = 0.0
    state.investor_obligation_per_day = 0.0
    state.funding_rounds_raised = []
    state.active_board_demand = {}
    state.board_demand_history = []
    state.models = []
    state.deployments = []
    state.staff = []
    state.public_trust = 50.0
    state.safety_debt = 0.0

    var expected_valuation: float = float(board_mgr.VALUATION_BASE) + state.public_trust * float(board_mgr.VALUATION_PER_TRUST_POINT)
    if not is_equal_approx(board_mgr.valuation(), expected_valuation):
        push_error("BoardManager.valuation() should be a pure function of existing state (expected %.1f, got %.1f)" % [expected_valuation, board_mgr.valuation()])
        quit(1)
        return
    print("SMOKE_OK: valuation is a deterministic function of existing campaign state")

    if String(board_mgr.next_round_id()) != "seed":
        push_error("The first funding round offered should be 'seed'")
        quit(1)
        return
    if not board_mgr.can_accept_funding("seed"):
        push_error("Seed round should be available at 0 valuation requirement")
        quit(1)
        return
    if board_mgr.can_accept_funding("series_a"):
        push_error("Rounds must be raised strictly in order — series_a shouldn't be available before seed")
        quit(1)
        return

    var seed_def: Dictionary = FundingRoundCatalog.get_def("seed")
    var cash_before_seed: float = state.cash
    var control_before_seed: float = state.board_control_pct
    var seed_err: Error = board_mgr.accept_funding("seed")
    if seed_err != OK:
        push_error("Accepting the seed round failed unexpectedly (error %s)" % seed_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_seed + float(seed_def.get("amount", 0.0))):
        push_error("Accepting a funding round should add its amount to cash")
        quit(1)
        return
    if not is_equal_approx(state.board_control_pct, control_before_seed - float(seed_def.get("equity_pct", 0.0))):
        push_error("Accepting a funding round should reduce board_control_pct by its equity_pct")
        quit(1)
        return
    if not is_equal_approx(state.investor_obligation_per_day, float(seed_def.get("obligation_per_day", 0.0))):
        push_error("Accepting a funding round should add its obligation_per_day to the running total")
        quit(1)
        return
    if String(board_mgr.next_round_id()) != "series_a":
        push_error("After raising seed, series_a should be the next round offered")
        quit(1)
        return
    print("SMOKE_OK: funding changes both cash (now) and obligations (ongoing), and control is traded for it")

    if board_mgr.can_accept_funding("series_a"):
        push_error("series_a should be gated by valuation (min_valuation 150000), not available yet")
        quit(1)
        return
    var series_a_gate_err: Error = board_mgr.accept_funding("series_a")
    if series_a_gate_err == OK:
        push_error("accept_funding() should refuse a round whose valuation gate isn't met")
        quit(1)
        return

    state.models = [{"id": "m1"}, {"id": "m2"}]  # pushes valuation over series_a's min_valuation
    if not board_mgr.can_accept_funding("series_a"):
        push_error("series_a should become available once valuation clears its min_valuation gate")
        quit(1)
        return
    var obligation_before_series_a: float = state.investor_obligation_per_day
    var series_a_err: Error = board_mgr.accept_funding("series_a")
    if series_a_err != OK:
        push_error("Accepting series_a failed unexpectedly once its valuation gate was met (error %s)" % series_a_err)
        quit(1)
        return
    var series_a_def: Dictionary = FundingRoundCatalog.get_def("series_a")
    if not is_equal_approx(state.investor_obligation_per_day, obligation_before_series_a + float(series_a_def.get("obligation_per_day", 0.0))):
        push_error("Obligations from multiple rounds should accumulate")
        quit(1)
        return
    print("SMOKE_OK: later rounds are gated by valuation, and obligations accumulate across rounds")

    var ledger_p25: Dictionary = economy_mgr.daily_ledger()
    if not is_equal_approx(float(ledger_p25.get("investor_obligations", -1.0)), state.investor_obligation_per_day):
        push_error("EconomyManager.daily_ledger() should report the exact same investor_obligations the funding rounds accrued")
        quit(1)
        return
    print("SMOKE_OK: the daily ledger/runway forecast reflects investor obligations from accepted funding")

    state.board_pressure = 59.0  # control already given away this tick pushes it over the 60 threshold
    state.active_board_demand = {}
    bus2.day_advanced.emit(state.calendar_day)
    if state.active_board_demand.is_empty():
        push_error("Crossing the board pressure threshold should trigger a demand")
        quit(1)
        return
    if String(state.active_board_demand.get("ask", "")).is_empty():
        push_error("A board demand should carry a clear, non-empty ask")
        quit(1)
        return
    print("SMOKE_OK: board pressure from control given away and low runway triggers a demand with a clear ask")

    var bad_choice_err: Error = board_mgr.resolve_demand("not_a_real_choice")
    if bad_choice_err == OK:
        push_error("resolve_demand() should reject an unknown choice id")
        quit(1)
        return

    var trust_before_demand: float = state.public_trust
    var hold_the_line_def: Dictionary = board_mgr.demand_choice_effects("hold_the_line")
    var demand_resolve_err: Error = board_mgr.resolve_demand("hold_the_line")
    if demand_resolve_err != OK:
        push_error("Resolving an active board demand with a valid choice failed unexpectedly (error %s)" % demand_resolve_err)
        quit(1)
        return
    if not state.active_board_demand.is_empty():
        push_error("Resolving a demand should clear active_board_demand")
        quit(1)
        return
    if state.board_demand_history.is_empty() or String((state.board_demand_history[-1] as Dictionary).get("choice", "")) != "hold_the_line":
        push_error("Resolving a demand should record it in board_demand_history with the choice made")
        quit(1)
        return
    if not is_equal_approx(state.public_trust, trust_before_demand + float(hold_the_line_def.get("public_trust", 0.0))):
        push_error("Resolving a demand should apply that choice's data-driven effects")
        quit(1)
        return
    if not state.ending_id.is_empty():
        push_error("A board demand must always resolve into a decision, never an instant ending")
        quit(1)
        return
    print("SMOKE_OK: resolving a board demand applies its data-driven effects and is always a decision, never an instant ending")

    var double_resolve_err: Error = board_mgr.resolve_demand("hold_the_line")
    if double_resolve_err == OK:
        push_error("Resolving a demand with none active should fail, not silently succeed")
        quit(1)
        return

    state.ending_id = ""
    state.paused = false
    state.board_control_pct = 100.0
    state.board_pressure = 0.0
    state.investor_obligation_per_day = 0.0
    state.funding_rounds_raised = []
    state.active_board_demand = {}
    state.board_demand_history = []
    state.models = []
    state.deployments = []
    state.cash = 184200.0

    # P27: legal exposure system — abstract cases (no real plaintiffs),
    # settlements, injunction probability, compliance staffing.
    var legal_mgr: Node = get_root().get_node("LegalManager")
    state.calendar_day = 1
    state.cash = 500000.0
    state.legal_exposure = 0.0
    state.active_legal_case = {}
    state.legal_case_history = []
    state.legal_case_cooldowns = {}
    state.staff = []
    state.deployments = []
    state.safety_debt = 0.0

    if not is_equal_approx(legal_mgr.daily_exposure_gain(), 0.0):
        push_error("With no deployed scale and no safety debt, daily legal exposure gain should be 0")
        quit(1)
        return
    state.safety_debt = 100.0
    var gain_no_compliance: float = legal_mgr.daily_exposure_gain()
    if gain_no_compliance <= 0.0:
        push_error("Safety debt should drive legal exposure gain upward")
        quit(1)
        return

    staff_mgr.refresh_candidates()
    for i in 10:
        staff_mgr.hire(0)
    for member: Dictionary in state.staff:
        member["role"] = "safety_analyst"
    if legal_mgr.compliance_staff_count() != 10:
        push_error("compliance_staff_count() should count safety_analyst staff (expected 10, got %d)" % legal_mgr.compliance_staff_count())
        quit(1)
        return
    if legal_mgr.daily_exposure_gain() > 0.001:
        push_error("Enough compliance staffing should be able to fully offset a day's exposure gain, floored at 0 (got %.4f)" % legal_mgr.daily_exposure_gain())
        quit(1)
        return
    print("SMOKE_OK: legal exposure rises with safety debt/deployed scale and compliance staffing offsets it, floored at 0")

    state.staff = []
    state.legal_exposure = 60.0  # above every case type's trigger_min_exposure
    bus2.day_advanced.emit(state.calendar_day)
    if state.active_legal_case.is_empty():
        push_error("Crossing a case type's exposure threshold should file a case")
        quit(1)
        return
    var filed_case_type: String = String(state.active_legal_case.get("case_type_id", ""))
    var filed_case_def: Dictionary = LegalCaseTypeCatalog.get_def(filed_case_type)
    if filed_case_def.is_empty():
        push_error("A filed case should reference a real, known case type")
        quit(1)
        return
    if int(state.active_legal_case.get("deadline_day", 0)) != int(state.active_legal_case.get("filed_day", 0)) + int(filed_case_def.get("case_deadline_days", 0)):
        push_error("A filed case's deadline should be filed_day + case_deadline_days")
        quit(1)
        return
    print("SMOKE_OK: cases follow player actions — crossing the exposure threshold files a real, data-driven case")

    var bad_resolve_err: Error = legal_mgr.resolve_case("not_a_real_choice")
    if bad_resolve_err == OK:
        push_error("resolve_case() should reject an unknown choice id")
        quit(1)
        return

    var cash_before_settle: float = state.cash
    var exposure_before_settle: float = state.legal_exposure
    var settle_effects: Dictionary = filed_case_def.get("settle", {})
    var settle_err: Error = legal_mgr.resolve_case("settle")
    if settle_err != OK:
        push_error("Resolving an active case with a valid choice failed unexpectedly (error %s)" % settle_err)
        quit(1)
        return
    if not state.active_legal_case.is_empty():
        push_error("Resolving a case should clear active_legal_case")
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_settle + float(settle_effects.get("cash", 0.0))):
        push_error("Settling a case should apply its data-driven cash effect")
        quit(1)
        return
    if not is_equal_approx(state.legal_exposure, clampf(exposure_before_settle + float(settle_effects.get("legal_exposure", 0.0)), 0.0, 100.0)):
        push_error("Settling a case should apply its data-driven legal_exposure effect")
        quit(1)
        return
    if state.legal_case_history.is_empty() or String((state.legal_case_history[-1] as Dictionary).get("outcome", "")) != "settle":
        push_error("Resolving a case should record it in legal_case_history with the outcome chosen")
        quit(1)
        return
    print("SMOKE_OK: settling a case applies its documented, bounded effects and records it in history")

    state.legal_exposure = 90.0
    if legal_mgr.eligible_case_types().has(filed_case_type):
        push_error("A just-resolved case type should be on cooldown, not immediately eligible again")
        quit(1)
        return
    print("SMOKE_OK: a resolved case type goes on cooldown instead of re-triggering immediately")

    # Injunction probability / deadline default: an active case must
    # always resolve within its deadline window, one way or another —
    # never left open indefinitely.
    var forced_case_type: String = "labor_practices_claim"
    var forced_def: Dictionary = LegalCaseTypeCatalog.get_def(forced_case_type)
    state.legal_case_cooldowns = {}
    state.active_legal_case = {
        "case_type_id": forced_case_type, "instance_id": "legal_test_forced",
        "filed_day": state.calendar_day, "deadline_day": state.calendar_day + int(forced_def.get("case_deadline_days", 15)),
    }
    var deadline_days: int = int(forced_def.get("case_deadline_days", 15))
    for i in deadline_days + 1:
        state.calendar_day += 1
        bus2.day_advanced.emit(state.calendar_day)
        if state.active_legal_case.is_empty():
            break
    if not state.active_legal_case.is_empty():
        push_error("An active case must always resolve by its deadline (injunction roll or deadline default), never stay open indefinitely")
        quit(1)
        return
    var forced_outcome: String = String((state.legal_case_history[-1] as Dictionary).get("outcome", ""))
    if forced_outcome != "injunction" and forced_outcome != "deadline_default":
        push_error("Expected the forced case to resolve via injunction or deadline_default, got '%s'" % forced_outcome)
        quit(1)
        return
    if (state.legal_case_history[-1] as Dictionary).get("effects_applied", {}).is_empty():
        push_error("Every case outcome should apply a documented (non-empty) effect set")
        quit(1)
        return
    print("SMOKE_OK: an unresolved case always resolves within its deadline via a bounded, documented outcome (injunction or default)")

    state.staff = []
    state.legal_exposure = 0.0
    state.active_legal_case = {}
    state.legal_case_history = []
    state.legal_case_cooldowns = {}
    state.safety_debt = 0.0
    state.cash = 184200.0

    # P28: autonomous agent permissions — coding/support/research/tool
    # access/spending, each a data-driven productivity gain traded for an
    # explicit, bounded risk.
    var agent_mgr: Node = get_root().get_node("AgentPermissionManager")
    var permission_ids: Array = AgentPermissionCatalog.ordered_ids()
    if permission_ids.size() != 5:
        push_error("AgentPermissionCatalog should seed exactly 5 autonomy permissions (got %d)" % permission_ids.size())
        quit(1)
        return
    for permission_id: String in permission_ids:
        var perm_def: Dictionary = AgentPermissionCatalog.get_def(permission_id)
        if (perm_def.get("productivity_effects", {}) as Dictionary).is_empty() or (perm_def.get("risk_effects", {}) as Dictionary).is_empty():
            push_error("Permission '%s' must have both a productivity gain and an explicit risk surface" % permission_id)
            quit(1)
            return
    print("SMOKE_OK: AgentPermissionCatalog seeds 5 permissions, each with a productivity gain and an explicit risk surface")

    state.models = [{
        "id": "agent_model_1", "name": "Agent Test Model", "generation": 1, "architecture_tier": "small",
        "capability": 50.0, "reliability": 50.0, "safety_confidence": 50.0, "cost_efficiency": 50.0,
        "latency_efficiency": 50.0, "autonomy": 50.0, "interpretability": 50.0, "latent_risk": 50.0,
        "evals_completed": 0, "training_cost": 8000.0, "created_at": 1,
    }]
    state.deployments = []
    state.safety_debt = 0.0
    state.cash = 100000.0
    release_mgr.deploy("agent_model_1")
    var agent_deployment_id: String = String(state.deployments[0].get("id", ""))
    # Zero rate_limit keeps user_scale (and RevenueManager's net) at exactly
    # 0 regardless of rollout_stage advancing mid-tick, so the cash checks
    # below isolate AgentPermissionManager's own effect cleanly.
    release_mgr.set_rate_limit(agent_deployment_id, 0.0)

    var bad_grant_err: Error = agent_mgr.grant(agent_deployment_id, "not_a_real_permission")
    if bad_grant_err == OK:
        push_error("grant() should reject an unknown permission id")
        quit(1)
        return
    var missing_deployment_err: Error = agent_mgr.grant("not_a_real_deployment", "coding_assistance")
    if missing_deployment_err == OK:
        push_error("grant() should reject a nonexistent deployment id")
        quit(1)
        return

    var grant_err: Error = agent_mgr.grant(agent_deployment_id, "coding_assistance")
    if grant_err != OK or not agent_mgr.has_permission(agent_deployment_id, "coding_assistance"):
        push_error("Granting a valid permission to a real deployment should succeed (error %s)" % grant_err)
        quit(1)
        return
    var double_grant_err: Error = agent_mgr.grant(agent_deployment_id, "coding_assistance")
    if double_grant_err == OK:
        push_error("Granting the same permission twice should be rejected, not silently duplicated")
        quit(1)
        return
    print("SMOKE_OK: granting an autonomy permission to a real deployment works, and rejects unknown ids/duplicates")

    var coding_def: Dictionary = AgentPermissionCatalog.get_def("coding_assistance")
    var expected_productivity_cash: float = float((coding_def.get("productivity_effects", {}) as Dictionary).get("cash", 0.0))
    var expected_risk_debt: float = float((coding_def.get("risk_effects", {}) as Dictionary).get("safety_debt", 0.0))
    # Isolate the permission's own effect from the rest of the day_advanced
    # ledger (rent/legal/support/investor obligations, revenue net) that
    # also fires on this same tick — same technique as the P23 ledger tests.
    var other_daily_delta: float = revenue_mgr.total_daily_net() - economy_mgr.rent_cost() - economy_mgr.legal_cost() - economy_mgr.support_cost() - economy_mgr.investor_obligation_cost()
    var cash_before_permission_tick: float = state.cash
    var debt_before_permission_tick: float = state.safety_debt
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_permission_tick + expected_productivity_cash + other_daily_delta):
        push_error("A granted permission's productivity_effects should apply daily (expected +%.1f cash on top of the rest of the ledger)" % expected_productivity_cash)
        quit(1)
        return
    if not is_equal_approx(state.safety_debt, debt_before_permission_tick + expected_risk_debt):
        push_error("A granted permission's risk_effects should apply daily (expected +%.1f safety_debt)" % expected_risk_debt)
        quit(1)
        return
    print("SMOKE_OK: a granted permission's productivity gain and risk cost both apply daily, exactly matching its data")

    var revoke_err: Error = agent_mgr.revoke(agent_deployment_id, "coding_assistance")
    if revoke_err != OK or agent_mgr.has_permission(agent_deployment_id, "coding_assistance"):
        push_error("Revoking a granted permission should succeed and clear it (error %s)" % revoke_err)
        quit(1)
        return
    var double_revoke_err: Error = agent_mgr.revoke(agent_deployment_id, "coding_assistance")
    if double_revoke_err == OK:
        push_error("Revoking a permission that isn't granted should fail, not silently succeed")
        quit(1)
        return
    var other_daily_delta2: float = revenue_mgr.total_daily_net() - economy_mgr.rent_cost() - economy_mgr.legal_cost() - economy_mgr.support_cost() - economy_mgr.investor_obligation_cost()
    var cash_before_revoked_tick: float = state.cash
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_revoked_tick + other_daily_delta2):
        push_error("A revoked permission should stop applying its effects (only the rest of the ledger should move cash)")
        quit(1)
        return
    print("SMOKE_OK: revoking a permission stops applying its effects")

    state.models = []
    state.deployments = []
    state.safety_debt = 0.0
    state.cash = 184200.0

    # P29: automation and workforce — automation pressure from granted
    # agent permissions, and policy-dependent (never forced) outcomes.
    var automation_mgr: Node = get_root().get_node("AutomationManager")
    var policy_ids: Array = WorkforcePolicyCatalog.ordered_ids()
    if policy_ids.size() != 4:
        push_error("WorkforcePolicyCatalog should seed exactly 4 workforce policies (got %d)" % policy_ids.size())
        quit(1)
        return
    print("SMOKE_OK: WorkforcePolicyCatalog seeds 4 workforce policies")

    state.workforce_policy = "status_quo"
    state.models = [{
        "id": "automation_model_1", "name": "Automation Test Model", "generation": 1, "architecture_tier": "small",
        "capability": 50.0, "reliability": 50.0, "safety_confidence": 50.0, "cost_efficiency": 50.0,
        "latency_efficiency": 50.0, "autonomy": 50.0, "interpretability": 50.0, "latent_risk": 50.0,
        "evals_completed": 0, "training_cost": 8000.0, "created_at": 1,
    }]
    state.deployments = []
    state.cash = 100000.0
    state.safety_debt = 0.0
    state.public_trust = 50.0
    state.staff = []

    if not is_equal_approx(automation_mgr.automation_pressure(), 0.0):
        push_error("automation_pressure() should be 0 with no deployments")
        quit(1)
        return

    release_mgr.deploy("automation_model_1")
    var automation_deployment_id: String = String(state.deployments[0].get("id", ""))
    release_mgr.set_rate_limit(automation_deployment_id, 0.0)
    agent_mgr.grant(automation_deployment_id, "coding_assistance")
    agent_mgr.grant(automation_deployment_id, "tool_access")
    if not is_equal_approx(automation_mgr.automation_pressure(), 2.0):
        push_error("automation_pressure() should equal the total granted permissions across all deployments (expected 2, got %.1f)" % automation_mgr.automation_pressure())
        quit(1)
        return
    print("SMOKE_OK: automation pressure is a deterministic function of granted agent permissions")

    var bad_policy_err: Error = automation_mgr.set_policy("not_a_real_policy")
    if bad_policy_err == OK:
        push_error("set_policy() should reject an unknown policy id")
        quit(1)
        return

    var downsize_err: Error = automation_mgr.set_policy("downsize")
    if downsize_err != OK or state.workforce_policy != "downsize":
        push_error("set_policy() should switch the active policy (error %s)" % downsize_err)
        quit(1)
        return

    staff_mgr.refresh_candidates()
    staff_mgr.hire(0)
    var automation_staff_id: String = String(state.staff[0].get("id", ""))
    state.staff[0]["morale"] = 50.0
    # Neutral fatigue band (30-70): StaffManager's own P24 fatigue-based
    # morale drift only kicks in outside this range, so it contributes 0
    # this tick and doesn't confound the automation-policy morale check.
    state.staff[0]["fatigue"] = 50.0

    var downsize_def: Dictionary = WorkforcePolicyCatalog.get_def("downsize")
    var pressure: float = automation_mgr.automation_pressure()
    var expected_cash_delta: float = float(downsize_def.get("cash_per_pressure", 0.0)) * pressure
    var expected_morale_delta: float = float(downsize_def.get("morale_per_pressure", 0.0)) * pressure
    var expected_trust_delta: float = float(downsize_def.get("trust_per_pressure", 0.0)) * pressure
    # The 2 granted permissions from earlier in this block (coding_assistance,
    # tool_access) are still active and also apply their own daily cash
    # productivity on this same tick — isolate that too.
    var granted_permission_cash: float = float(agent_mgr.deployment_permission_ledger(automation_deployment_id).get("total_productivity_cash", 0.0))
    var other_daily_delta3: float = revenue_mgr.total_daily_net() - economy_mgr.rent_cost() - economy_mgr.legal_cost() - economy_mgr.support_cost() - economy_mgr.investor_obligation_cost() - staff_mgr.total_payroll() + granted_permission_cash

    var cash_before_automation_tick: float = state.cash
    var trust_before_automation_tick: float = state.public_trust
    bus2.day_advanced.emit(state.calendar_day)
    if not is_equal_approx(state.cash, cash_before_automation_tick + expected_cash_delta + other_daily_delta3):
        push_error("The active policy's cash_per_pressure * automation_pressure should apply daily (expected %+.1f)" % expected_cash_delta)
        quit(1)
        return
    if not is_equal_approx(state.public_trust, clampf(trust_before_automation_tick + expected_trust_delta, 0.0, 100.0)):
        push_error("The active policy's trust_per_pressure * automation_pressure should apply daily")
        quit(1)
        return
    if not is_equal_approx(float(staff_mgr.find(automation_staff_id).get("morale", -1.0)), clampf(50.0 + expected_morale_delta, 0.0, 100.0)):
        push_error("The active policy's morale_per_pressure * automation_pressure should apply to every staff member daily")
        quit(1)
        return
    print("SMOKE_OK: the chosen workforce policy's effects scale with automation pressure and apply daily, exactly matching its data")

    # No forced conclusion: switching to a different policy produces a
    # genuinely different outcome (not just a smaller/larger version of
    # the same one), since no policy dominates every axis.
    automation_mgr.set_policy("retrain")
    var retrain_def: Dictionary = WorkforcePolicyCatalog.get_def("retrain")
    if float(retrain_def.get("cash_per_pressure", 0.0)) >= float(downsize_def.get("cash_per_pressure", 0.0)) and float(retrain_def.get("morale_per_pressure", 0.0)) <= float(downsize_def.get("morale_per_pressure", 0.0)):
        push_error("retrain and downsize should trade off differently (retrain should cost more cash but help morale more than downsize)")
        quit(1)
        return
    print("SMOKE_OK: different policies trade off differently — outcomes depend on the policy chosen, not a forced conclusion")

    state.workforce_policy = "status_quo"
    state.staff = []
    state.models = []
    state.deployments = []
    state.safety_debt = 0.0
    state.public_trust = 50.0
    state.cash = 184200.0

    # P30: datacenter progression — abstract remote compute, purchased as
    # whole tiers instead of placed as individual racks.
    var datacenter_mgr: Node = get_root().get_node("DatacenterManager")
    var datacenter_tier_ids: Array = DatacenterTierCatalog.ORDER
    if datacenter_tier_ids.size() != 4:
        push_error("DatacenterTierCatalog should define exactly 4 tiers (got %d)" % datacenter_tier_ids.size())
        quit(1)
        return
    print("SMOKE_OK: DatacenterTierCatalog seeds 4 progressively larger tiers")

    state.datacenter_tiers_purchased = []
    state.datacenter_compute_bonus = 0.0
    state.datacenter_operating_cost = 0.0
    state.cash = 100000.0
    state.compute_capacity = 20.0
    state.heat_load = 0.0
    state.heat_capacity = 60.0

    if not is_equal_approx(state.effective_compute_capacity(), 20.0):
        push_error("With no datacenters purchased, effective_compute_capacity() should just be the office's own capacity")
        quit(1)
        return

    var out_of_order_err: Error = datacenter_mgr.purchase("continental_cluster")
    if out_of_order_err == OK:
        push_error("Tiers must be purchased strictly in order — continental_cluster shouldn't be purchasable before regional_pod")
        quit(1)
        return

    state.cash = 100.0  # not enough for regional_pod
    var poor_err: Error = datacenter_mgr.purchase("regional_pod")
    if poor_err == OK:
        push_error("purchase() should refuse a tier the player can't afford")
        quit(1)
        return

    state.cash = 100000.0
    var regional_def: Dictionary = DatacenterTierCatalog.get_def("regional_pod")
    var cash_before_datacenter: float = state.cash
    var purchase_err: Error = datacenter_mgr.purchase("regional_pod")
    if purchase_err != OK:
        push_error("Purchasing an affordable, in-order tier should succeed (error %s)" % purchase_err)
        quit(1)
        return
    if not is_equal_approx(state.cash, cash_before_datacenter - float(regional_def.get("cost", 0.0))):
        push_error("Purchasing a tier should deduct its one-time cost")
        quit(1)
        return
    if not is_equal_approx(state.effective_compute_capacity(), 20.0 + float(regional_def.get("compute_capacity_bonus", 0.0))):
        push_error("A purchased tier's compute_capacity_bonus should add directly to effective_compute_capacity(), unaffected by office heat throttling")
        quit(1)
        return
    var ledger_p30: Dictionary = economy_mgr.daily_ledger()
    if not is_equal_approx(float(ledger_p30.get("datacenters", -1.0)), float(regional_def.get("operating_cost_per_day", 0.0))):
        push_error("The daily ledger should include the purchased tier's operating cost")
        quit(1)
        return
    print("SMOKE_OK: purchasing a datacenter tier deducts its cost and adds a large, un-throttled compute bonus plus a ledger-visible operating cost")

    if String(datacenter_mgr.next_tier_id()) != "continental_cluster":
        push_error("After purchasing regional_pod, continental_cluster should be the next tier offered")
        quit(1)
        return

    # Late-game compute scaling: buy out every remaining tier and confirm
    # the bonus accumulates additively, with no per-unit placement needed.
    state.cash = 20000000.0
    var total_expected_bonus: float = float(regional_def.get("compute_capacity_bonus", 0.0))
    for tier_id: String in ["continental_cluster", "flagship_campus", "orbital_relay"]:
        datacenter_mgr.purchase(tier_id)
        total_expected_bonus += float(DatacenterTierCatalog.get_def(tier_id).get("compute_capacity_bonus", 0.0))
    if not String(datacenter_mgr.next_tier_id()).is_empty():
        push_error("Once every tier is purchased, next_tier_id() should be empty")
        quit(1)
        return
    if not is_equal_approx(state.effective_compute_capacity(), 20.0 + total_expected_bonus):
        push_error("Every purchased tier's compute bonus should accumulate additively (expected %.1f)" % (20.0 + total_expected_bonus))
        quit(1)
        return
    print("SMOKE_OK: every datacenter tier can be purchased in order, and their compute bonuses accumulate additively for late-game scale")

    state.datacenter_tiers_purchased = []
    state.datacenter_compute_bonus = 0.0
    state.datacenter_operating_cost = 0.0
    state.compute_capacity = state.BASE_COMPUTE_CAPACITY
    state.heat_capacity = state.BASE_HEAT_CAPACITY
    state.heat_load = 0.0
    state.cash = 184200.0

    quit(0)
