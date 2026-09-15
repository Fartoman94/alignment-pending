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
    var expected_autoloads: Array[String] = ["EventBus", "GameState", "SaveManager", "SceneRouter", "SettingsManager"]
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

    quit(0)
