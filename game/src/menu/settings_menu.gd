extends Control

const TABS_PATH: String = "Panel/Margin/VBox/Tabs"

@onready var _master_slider: HSlider = get_node(TABS_PATH + "/Display & Audio/MasterRow/MasterSlider")
@onready var _music_slider: HSlider = get_node(TABS_PATH + "/Display & Audio/MusicRow/MusicSlider")
@onready var _sfx_slider: HSlider = get_node(TABS_PATH + "/Display & Audio/SfxRow/SfxSlider")
@onready var _ui_volume_slider: HSlider = get_node(TABS_PATH + "/Display & Audio/UiVolumeRow/UiVolumeSlider")
@onready var _ui_scale_slider: HSlider = get_node(TABS_PATH + "/Display & Audio/UiScaleRow/UiScaleSlider")
@onready var _ui_scale_value: Label = get_node(TABS_PATH + "/Display & Audio/UiScaleRow/UiScaleValue")
@onready var _fullscreen_check: CheckButton = get_node(TABS_PATH + "/Display & Audio/FullscreenRow/FullscreenCheck")
@onready var _resolution_option: OptionButton = get_node(TABS_PATH + "/Display & Audio/ResolutionRow/ResolutionOption")
@onready var _reduced_motion_check: CheckButton = get_node(TABS_PATH + "/Accessibility/ReducedMotionRow/ReducedMotionCheck")
@onready var _camera_shake_check: CheckButton = get_node(TABS_PATH + "/Accessibility/CameraShakeRow/CameraShakeCheck")
@onready var _high_contrast_check: CheckButton = get_node(TABS_PATH + "/Accessibility/HighContrastRow/HighContrastCheck")
@onready var _colorblind_check: CheckButton = get_node(TABS_PATH + "/Accessibility/ColorblindRow/ColorblindCheck")
@onready var _pause_on_incident_check: CheckButton = get_node(TABS_PATH + "/Accessibility/PauseOnIncidentRow/PauseOnIncidentCheck")
@onready var _tooltip_delay_slider: HSlider = get_node(TABS_PATH + "/Accessibility/TooltipDelayRow/TooltipDelaySlider")
@onready var _tooltip_delay_value: Label = get_node(TABS_PATH + "/Accessibility/TooltipDelayRow/TooltipDelayValue")
@onready var _keybind_list: VBoxContainer = get_node(TABS_PATH + "/Keybinds/Scroll/List")
@onready var _apply_button: Button = $Panel/Margin/VBox/ButtonRow/ApplyButton
@onready var _reset_button: Button = $Panel/Margin/VBox/ButtonRow/ResetButton
@onready var _back_button: Button = $Panel/Margin/VBox/ButtonRow/BackButton

## action -> the Button currently waiting to capture the next keypress
## (only ever one at a time; starting a new capture cancels any other).
var _capturing_action: String = ""
var _keybind_buttons: Dictionary = {}

func _ready() -> void:
    _populate_resolution_options()
    _build_keybind_rows()
    _load_from_settings()
    _apply_button.pressed.connect(_on_apply_pressed)
    _reset_button.pressed.connect(_on_reset_pressed)
    _back_button.pressed.connect(_on_back_pressed)
    _ui_scale_slider.value_changed.connect(_on_ui_scale_preview_changed)
    _tooltip_delay_slider.value_changed.connect(_on_tooltip_delay_preview_changed)
    _master_slider.grab_focus()

func _populate_resolution_options() -> void:
    _resolution_option.clear()
    for res: Vector2i in SettingsManager.RESOLUTIONS:
        _resolution_option.add_item("%dx%d" % [res.x, res.y])

## One row per SettingsManager.REMAPPABLE_ACTIONS entry: a label, the
## current key's name, and a Rebind button that starts capture.
func _build_keybind_rows() -> void:
    for child in _keybind_list.get_children():
        child.queue_free()
    _keybind_buttons.clear()
    for entry: Dictionary in SettingsManager.REMAPPABLE_ACTIONS:
        var action: String = String(entry.get("action", ""))
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        label.custom_minimum_size = Vector2(190, 0)
        label.text = String(entry.get("label", action))
        row.add_child(label)
        var rebind_btn: Button = Button.new()
        rebind_btn.custom_minimum_size = Vector2(140, 0)
        rebind_btn.text = OS.get_keycode_string(SettingsManager.current_key_for(action))
        rebind_btn.pressed.connect(_on_rebind_pressed.bind(action, rebind_btn))
        row.add_child(rebind_btn)
        _keybind_list.add_child(row)
        _keybind_buttons[action] = rebind_btn

func _on_rebind_pressed(action: String, button: Button) -> void:
    _capturing_action = action
    button.text = "Press a key..."

func _unhandled_key_input(event: InputEvent) -> void:
    if _capturing_action.is_empty():
        return
    if not (event is InputEventKey) or not (event as InputEventKey).pressed:
        return
    var key_event: InputEventKey = event
    SettingsManager.rebind_action(_capturing_action, key_event.physical_keycode)
    var button: Button = _keybind_buttons.get(_capturing_action)
    if button != null:
        button.text = OS.get_keycode_string(key_event.physical_keycode)
    _capturing_action = ""
    get_viewport().set_input_as_handled()

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
    _high_contrast_check.button_pressed = SettingsManager.high_contrast
    _colorblind_check.button_pressed = SettingsManager.colorblind_mode
    _pause_on_incident_check.button_pressed = SettingsManager.pause_on_incident
    _tooltip_delay_slider.value = SettingsManager.tooltip_delay_sec
    _tooltip_delay_value.text = "%.1fs" % SettingsManager.tooltip_delay_sec
    for action: String in _keybind_buttons:
        (_keybind_buttons[action] as Button).text = OS.get_keycode_string(SettingsManager.current_key_for(action))

func _on_ui_scale_preview_changed(value: float) -> void:
    _ui_scale_value.text = "%d%%" % int(round(value * 100.0))

func _on_tooltip_delay_preview_changed(value: float) -> void:
    _tooltip_delay_value.text = "%.1fs" % value

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
    SettingsManager.high_contrast = _high_contrast_check.button_pressed
    SettingsManager.colorblind_mode = _colorblind_check.button_pressed
    SettingsManager.pause_on_incident = _pause_on_incident_check.button_pressed
    SettingsManager.tooltip_delay_sec = _tooltip_delay_slider.value
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
