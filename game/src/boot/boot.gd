extends Control

func _ready() -> void:
    await get_tree().process_frame
    var err: Error = await SceneRouter.go_to("res://scenes/main_menu.tscn")
    if err != OK:
        push_error("Boot: failed to route to main menu (error %s)" % err)
