extends Control

@onready var _master_slider: HSlider = $Panel/Margin/VBox/MasterRow/MasterSlider
@onready var _music_slider: HSlider = $Panel/Margin/VBox/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Panel/Margin/VBox/SfxRow/SfxSlider
@onready var _ui_volume_slider: HSlider = $Panel/Margin/VBox/UiVolumeRow/UiVolumeSlider
@onready var _ui_scale_slider: HSlider = $Panel/Margin/VBox/UiScaleRow/UiScaleSlider
@onready var _ui_scale_value: Label = $Panel/Margin/VBox/UiScaleRow/UiScaleValue
@onready var _fullscreen_check: CheckButton = $Panel/Margin/VBox/FullscreenRow/FullscreenCheck
@onready var _resolution_option: OptionButton = $Panel/Margin/VBox/ResolutionRow/ResolutionOption
@onready var _reduced_motion_check: CheckButton = $Panel/Margin/VBox/ReducedMotionRow/ReducedMotionCheck
@onready var _camera_shake_check: CheckButton = $Panel/Margin/VBox/CameraShakeRow/CameraShakeCheck
@onready var _apply_button: Button = $Panel/Margin/VBox/ButtonRow/ApplyButton
@onready var _reset_button: Button = $Panel/Margin/VBox/ButtonRow/ResetButton
@onready var _back_button: Button = $Panel/Margin/VBox/ButtonRow/BackButton

func _ready() -> void:
    _populate_resolution_options()
    _load_from_settings()
    _apply_button.pressed.connect(_on_apply_pressed)
    _reset_button.pressed.connect(_on_reset_pressed)
    _back_button.pressed.connect(_on_back_pressed)
    _ui_scale_slider.value_changed.connect(_on_ui_scale_preview_changed)

func _populate_resolution_options() -> void:
    _resolution_option.clear()
    for res: Vector2i in SettingsManager.RESOLUTIONS:
        _resolution_option.add_item("%dx%d" % [res.x, res.y])

func _load_from_settings() -> void:
    _master_slider.value = SettingsManager.master_volume
    _music_slider.value = SettingsManager.music_volume
    _sfx_slider.value = SettingsManager.sfx_volume
    _ui_volume_slider.value = SettingsManager.ui_volume
    _ui_scale_slider.value = SettingsManager.ui_scale
    _ui_scale_value.text = "%d%%" % int(round(SettingsManager.ui_scale * 100.0))
    _fullscreen_check.button_pressed = SettingsManager.fullscreen
    _resolution_option.selected = SettingsManager.resolution_index
    _reduced_motion_check.button_pressed = SettingsManager.reduced_motion
    _camera_shake_check.button_pressed = SettingsManager.camera_shake_enabled

func _on_ui_scale_preview_changed(value: float) -> void:
    _ui_scale_value.text = "%d%%" % int(round(value * 100.0))

func _on_apply_pressed() -> void:
    SettingsManager.master_volume = _master_slider.value
    SettingsManager.music_volume = _music_slider.value
    SettingsManager.sfx_volume = _sfx_slider.value
    SettingsManager.ui_volume = _ui_volume_slider.value
    SettingsManager.ui_scale = _ui_scale_slider.value
    SettingsManager.fullscreen = _fullscreen_check.button_pressed
    SettingsManager.resolution_index = _resolution_option.selected
    SettingsManager.reduced_motion = _reduced_motion_check.button_pressed
    SettingsManager.camera_shake_enabled = _camera_shake_check.button_pressed
    SettingsManager.apply_all()
    var err: Error = SettingsManager.save_settings()
    if err != OK:
        push_warning("SettingsMenu: failed to save settings (error %s)" % err)

func _on_reset_pressed() -> void:
    SettingsManager.reset_to_defaults()
    _load_from_settings()
    SettingsManager.apply_all()
    var err: Error = SettingsManager.save_settings()
    if err != OK:
        push_warning("SettingsMenu: failed to save defaults (error %s)" % err)

func _on_back_pressed() -> void:
    await SceneRouter.go_to("res://scenes/main_menu.tscn")
