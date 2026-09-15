extends Control

func _ready() -> void:
    if DataValidator.run_startup_validation():
        print("Boot: startup content data validated cleanly")
    else:
        push_error("Boot: startup content data has validation errors; see above. Continuing anyway.")
    await get_tree().process_frame
    var err: Error = await SceneRouter.go_to("res://scenes/main_menu.tscn")
    if err != OK:
        push_error("Boot: failed to route to main menu (error %s)" % err)
