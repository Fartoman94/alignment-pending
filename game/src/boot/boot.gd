extends Control

const ExportedBuildSmoke := preload("res://tests/exported_build_smoke.gd")

func _ready() -> void:
    if DataValidator.run_startup_validation():
        print("Boot: startup content data validated cleanly")
    else:
        push_error("Boot: startup content data has validation errors; see above. Continuing anyway.")

    # `--qa-exported-smoke`: lets a packaged/exported binary (Linux or
    # Windows) self-check without a display, since Godot's `--script` CLI
    # flag only works against an editable project, not an exported .pck.
    # See tests/exported_build_smoke.gd for why this exists.
    if "--qa-exported-smoke" in OS.get_cmdline_user_args():
        var passed: bool = await ExportedBuildSmoke.run(get_tree())
        get_tree().quit(0 if passed else 1)
        return

    await get_tree().process_frame
    var err: Error = await SceneRouter.go_to("res://scenes/intro.tscn")
    if err != OK:
        push_error("Boot: failed to route to the intro sequence (error %s)" % err)
