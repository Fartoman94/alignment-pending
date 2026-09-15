extends Control

@onready var _back_button: Button = $Panel/Margin/VBox/BackButton

func _ready() -> void:
    _back_button.pressed.connect(func() -> void: SceneRouter.go_to("res://scenes/main_menu.tscn"))
