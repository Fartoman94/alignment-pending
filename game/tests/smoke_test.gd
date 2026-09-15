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

    quit(0)
