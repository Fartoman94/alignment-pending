extends SceneTree

func _init() -> void:
    var project_name: String = ProjectSettings.get_setting("application/config/name", "")
    if project_name != "Alignment Pending":
        push_error("Unexpected project name: %s" % project_name)
        quit(1)
        return
    print("SMOKE_OK: project settings load")
    quit(0)
