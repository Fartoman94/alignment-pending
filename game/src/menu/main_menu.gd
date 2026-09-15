extends Control

@onready var _continue_button: Button = $VBox/ContinueButton
@onready var _new_button: Button = $VBox/NewCampaignButton
@onready var _settings_button: Button = $VBox/SettingsButton
@onready var _quit_button: Button = $VBox/QuitButton

func _ready() -> void:
    _continue_button.disabled = not SaveManager.has_any_save()
    _new_button.pressed.connect(_on_new_campaign_pressed)
    _continue_button.pressed.connect(_on_continue_pressed)
    _settings_button.pressed.connect(_on_settings_pressed)
    _quit_button.pressed.connect(_on_quit_pressed)

func _on_new_campaign_pressed() -> void:
    await SceneRouter.go_to("res://scenes/campaign.tscn")

func _on_continue_pressed() -> void:
    var err: Error = SaveManager.load_newest_autosave()
    if err != OK:
        push_warning("MainMenu: continue failed to load an autosave (error %s)" % err)
    await SceneRouter.go_to("res://scenes/campaign.tscn")

func _on_settings_pressed() -> void:
    await SceneRouter.go_to("res://scenes/settings.tscn")

func _on_quit_pressed() -> void:
    get_tree().quit()
