extends RefCounted

## Smoke checks run *inside a packaged/exported binary* (Linux or Windows),
## triggered by passing `--qa-exported-smoke` on the command line and read
## by src/boot/boot.gd before it routes to the main menu.
##
## This exists because Godot's `--script` CLI flag only works against an
## editable project directory (what tools/bootstrap.sh and tests/smoke_test.gd
## use) — it is silently ignored against a packaged export, which always
## falls back to `run/main_scene`. That's a real engine constraint, not a
## project bug (see docs/qa/EXPORTED_BUILD_SMOKE.md), so validating the
## actual shipped .pck needs a check the shipped game itself can run.
##
## This deliberately does not re-run all ~200 assertions in
## tests/smoke_test.gd (that suite already covers logic exhaustively against
## source). It only checks the things that can differ between "runs from
## res:// via the editor" and "runs from an embedded/packaged .pck":
## catalog/data loading, scene instancing, and save/settings round-trips.

static func run(tree: SceneTree) -> bool:
    print("QA_EXPORTED_SMOKE: starting")
    # boot.tscn's own _ready() (which awaits this) is still on the call
    # stack, and the tree root is mid-"setting up children" for that same
    # frame — add_child() on root would fail until it clears, one frame
    # later.
    await tree.process_frame

    var expected_autoloads: Array[String] = [
        "EventBus", "GameState", "SaveManager", "SceneRouter", "SettingsManager", "SimClock",
        "StaffManager", "ResearchManager", "ModelManager", "IncidentManager", "LocalizationManager",
    ]
    for autoload_name: String in expected_autoloads:
        if not tree.root.has_node(autoload_name):
            push_error("QA_EXPORTED_SMOKE: missing autoload %s in packaged build" % autoload_name)
            return false
    print("QA_EXPORTED_SMOKE_OK: autoloads present in packaged build")

    # Walk res://src/data itself (rather than a hardcoded list) so this
    # check can't go stale as catalogs are added, and so it also proves
    # directory listing works against the packaged .pck, not just direct
    # resource loads.
    var data_dir: DirAccess = DirAccess.open("res://src/data")
    if data_dir == null:
        push_error("QA_EXPORTED_SMOKE: res://src/data is not readable from the packaged build")
        return false
    var checked_count: int = 0
    data_dir.list_dir_begin()
    var entry: String = data_dir.get_next()
    while entry != "":
        # A packaged export lists these as "name.gd.remap" (the physical
        # pck entry), not "name.gd" (the logical res:// path editor/
        # headless-source runs see) — strip the remap suffix so load()
        # gets the logical path, which ResourceLoader resolves either way.
        var script_name: String = entry.trim_suffix(".remap") if entry.ends_with(".gd.remap") else entry
        if script_name.ends_with(".gd"):
            var script_path: String = "res://src/data/%s" % script_name
            var script_res: Script = load(script_path)
            if script_res == null:
                push_error("QA_EXPORTED_SMOKE: data catalog script failed to load from package: %s" % script_path)
                return false
            checked_count += 1
        entry = data_dir.get_next()
    data_dir.list_dir_end()
    if checked_count < 20:
        push_error("QA_EXPORTED_SMOKE: only found %d data catalog scripts in the package, expected 20+" % checked_count)
        return false
    print("QA_EXPORTED_SMOKE_OK: all %d res://src/data catalog scripts load from the embedded package" % checked_count)

    var scene_paths: Array[String] = [
        "res://scenes/main_menu.tscn",
        "res://scenes/settings.tscn",
        "res://scenes/campaign.tscn",
        "res://scenes/hud.tscn",
    ]
    for scene_path: String in scene_paths:
        var packed: PackedScene = load(scene_path)
        if packed == null:
            push_error("QA_EXPORTED_SMOKE: scene failed to load from package: %s" % scene_path)
            return false
        var inst: Node = packed.instantiate()
        tree.root.add_child(inst)
        await tree.process_frame
        inst.queue_free()
        await tree.process_frame
    print("QA_EXPORTED_SMOKE_OK: key scenes instantiate from the embedded package")

    var settings: Node = tree.root.get_node("SettingsManager")
    settings.reset_to_defaults()
    settings.master_volume = 0.37
    var settings_save_err: Error = settings.save_settings()
    settings.reset_to_defaults()
    var settings_load_err: Error = settings.load_settings()
    if settings_save_err != OK or settings_load_err != OK or not is_equal_approx(settings.master_volume, 0.37):
        push_error("QA_EXPORTED_SMOKE: settings save/load round-trip failed in packaged build")
        return false
    print("QA_EXPORTED_SMOKE_OK: settings persist to the real user:// path in a packaged build")

    var state: Node = tree.root.get_node("GameState")
    var save_mgr: Node = tree.root.get_node("SaveManager")
    state.cash = 918273.0
    var save_err: Error = save_mgr.save_manual(0)
    state.cash = 0.0
    var load_err: Error = save_mgr.load_manual(0)
    if save_err != OK or load_err != OK or not is_equal_approx(state.cash, 918273.0):
        push_error("QA_EXPORTED_SMOKE: save/load round-trip failed in packaged build (save=%s load=%s)" % [save_err, load_err])
        return false
    print("QA_EXPORTED_SMOKE_OK: manual save/load round-trips to the real user:// path in a packaged build")

    print("QA_EXPORTED_SMOKE: all checks passed")
    return true
