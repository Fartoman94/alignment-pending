extends Control

@onready var _title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var _body_label: Label = $Panel/Margin/VBox/BodyLabel
@onready var _milestones_label: Label = $Panel/Margin/VBox/MilestonesLabel
@onready var _credits_button: Button = $Panel/Margin/VBox/ButtonRow/CreditsButton
@onready var _menu_button: Button = $Panel/Margin/VBox/ButtonRow/MenuButton

func _ready() -> void:
    var def: Dictionary = EpilogueCatalog.get_def(GameState.ending_id)
    _title_label.text = String(def.get("title", "The End"))
    _body_label.text = String(def.get("body", ""))

    var milestones: Dictionary = EndingManager.compute_milestones()
    var lines: PackedStringArray = ["Milestones:"]
    for milestone_id: String in EndingManager.MILESTONE_LABELS:
        var done: bool = bool(milestones.get(milestone_id, false))
        lines.append("%s %s" % ["[x]" if done else "[ ]", String(EndingManager.MILESTONE_LABELS[milestone_id])])
    _milestones_label.text = "\n".join(lines)

    _credits_button.pressed.connect(func() -> void: SceneRouter.go_to("res://scenes/credits.tscn"))
    _menu_button.pressed.connect(func() -> void: SceneRouter.go_to("res://scenes/main_menu.tscn"))
