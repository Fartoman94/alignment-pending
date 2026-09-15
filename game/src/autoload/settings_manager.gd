extends Node

## Persists and applies audio, display and accessibility settings.
## Separate from GameState/SaveManager: settings are a player-machine
## preference, not campaign save data, and survive across campaigns.

const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_VERSION: int = 1

const MIN_UI_SCALE: float = 0.8
const MAX_UI_SCALE: float = 1.6

const MIN_TOOLTIP_DELAY_SEC: float = 0.1
const MAX_TOOLTIP_DELAY_SEC: float = 2.0
const DEFAULT_TOOLTIP_DELAY_SEC: float = 0.5

const RESOLUTIONS: Array[Vector2i] = [
    Vector2i(1280, 720),
    Vector2i(1600, 900),
    Vector2i(1920, 1080),
]

## P42: full remapping. The single canonical source of every rebindable
## action and its default key — CameraController/Campaign/BuildController
## each still register their own fallback default defensively (in case
## they run before this autoload, e.g. an isolated test), but as long as
## SettingsManager applies first (it's near the top of the autoload
## order), this list — plus any player override in `keybinds` — wins.
const REMAPPABLE_ACTIONS: Array[Dictionary] = [
    {"action": "pan_left", "label": "Pan camera left", "default_key": KEY_A},
    {"action": "pan_right", "label": "Pan camera right", "default_key": KEY_D},
    {"action": "pan_up", "label": "Pan camera up", "default_key": KEY_W},
    {"action": "pan_down", "label": "Pan camera down", "default_key": KEY_S},
    {"action": "rotate_left", "label": "Rotate camera left", "default_key": KEY_Q},
    {"action": "rotate_right", "label": "Rotate camera right", "default_key": KEY_E},
    {"action": "focus_selected", "label": "Focus selection", "default_key": KEY_F},
    {"action": "toggle_pause", "label": "Pause / resume", "default_key": KEY_SPACE},
    {"action": "return_to_menu", "label": "Return to menu", "default_key": KEY_ESCAPE},
    {"action": "build_rotate", "label": "Rotate build ghost", "default_key": KEY_R},
]

var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.85
var ui_volume: float = 1.0
var ui_scale: float = 1.0
var fullscreen: bool = false
var resolution_index: int = 0
var reduced_motion: bool = false
var camera_shake_enabled: bool = true
var high_contrast: bool = false
var colorblind_mode: bool = false
## "Pause while reading events" (UI_UX.md): beyond the P0/critical
## incidents that already always force-pause, this extends the pause to
## every incident so a player who needs more time to read never has the
## sim keep running underneath them.
var pause_on_incident: bool = false
var tooltip_delay_sec: float = DEFAULT_TOOLTIP_DELAY_SEC
## action -> Key (int). Only holds entries the player has actually
## rebound away from REMAPPABLE_ACTIONS' default.
var keybinds: Dictionary = {}

var _high_contrast_theme: Theme

func _ready() -> void:
    load_settings()
    apply_all()

func reset_to_defaults() -> void:
    master_volume = 1.0
    music_volume = 0.7
    sfx_volume = 0.85
    ui_volume = 1.0
    ui_scale = 1.0
    fullscreen = false
    resolution_index = 0
    reduced_motion = false
    camera_shake_enabled = true
    high_contrast = false
    colorblind_mode = false
    pause_on_incident = false
    tooltip_delay_sec = DEFAULT_TOOLTIP_DELAY_SEC
    keybinds = {}

func get_resolution() -> Vector2i:
    resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)
    return RESOLUTIONS[resolution_index]

func apply_all() -> void:
    _apply_audio()
    _apply_ui_scale()
    _apply_window_mode()
    _apply_accessibility()
    _apply_keybinds()

func _apply_audio() -> void:
    _set_bus_linear("Master", master_volume)
    _set_bus_linear("Music", music_volume)
    _set_bus_linear("SFX", sfx_volume)
    _set_bus_linear("UI", ui_volume)

func _set_bus_linear(bus_name: String, linear: float) -> void:
    var idx: int = AudioServer.get_bus_index(bus_name)
    if idx == -1:
        return
    var clamped: float = clampf(linear, 0.0, 1.0)
    AudioServer.set_bus_mute(idx, clamped <= 0.0001)
    if clamped > 0.0001:
        AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))

func _apply_ui_scale() -> void:
    ui_scale = clampf(ui_scale, MIN_UI_SCALE, MAX_UI_SCALE)
    if is_inside_tree() and get_tree().root != null:
        get_tree().root.content_scale_factor = ui_scale

func _apply_window_mode() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
    DisplayServer.window_set_mode(mode)
    if not fullscreen:
        DisplayServer.window_set_size(get_resolution())

## Readable tooltip timing + high-contrast theme. Colorblind redundancy
## isn't a single global switch (see BuildController's ghost indicator);
## this only applies the two settings that genuinely are global.
func _apply_accessibility() -> void:
    tooltip_delay_sec = clampf(tooltip_delay_sec, MIN_TOOLTIP_DELAY_SEC, MAX_TOOLTIP_DELAY_SEC)
    ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", tooltip_delay_sec)
    if is_inside_tree() and get_tree().root != null:
        get_tree().root.theme = _get_high_contrast_theme() if high_contrast else null

## Built once, procedurally (no imported theme resource): pure white text
## on pure black panels/buttons with a bright cyan focus/hover accent —
## maximum-contrast palette, not just "a bit darker/lighter".
func _get_high_contrast_theme() -> Theme:
    if _high_contrast_theme != null:
        return _high_contrast_theme
    var theme: Theme = Theme.new()
    theme.set_color("font_color", "Label", Color.WHITE)
    theme.set_color("font_color", "Button", Color.WHITE)
    theme.set_color("font_color", "RichTextLabel", Color.WHITE)
    theme.set_color("font_hover_color", "Button", Color(0.0, 1.0, 1.0))
    theme.set_color("font_pressed_color", "Button", Color(0.0, 1.0, 1.0))
    var panel_style: StyleBoxFlat = StyleBoxFlat.new()
    panel_style.bg_color = Color.BLACK
    panel_style.border_color = Color.WHITE
    panel_style.set_border_width_all(2)
    theme.set_stylebox("panel", "Panel", panel_style)
    var button_style: StyleBoxFlat = StyleBoxFlat.new()
    button_style.bg_color = Color.BLACK
    button_style.border_color = Color.WHITE
    button_style.set_border_width_all(2)
    theme.set_stylebox("normal", "Button", button_style)
    _high_contrast_theme = theme
    return _high_contrast_theme

## Idempotent: always leaves exactly one physical-key event per action,
## either the player's override (`keybinds`) or the catalog default —
## safe to call repeatedly (e.g. every apply_all()) without accumulating
## duplicate/stale bindings.
func _apply_keybinds() -> void:
    for entry: Dictionary in REMAPPABLE_ACTIONS:
        var action: String = String(entry.get("action", ""))
        if action.is_empty():
            continue
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        InputMap.action_erase_events(action)
        var keycode: Key = int(keybinds.get(action, int(entry.get("default_key", KEY_NONE)))) as Key
        var ev: InputEventKey = InputEventKey.new()
        ev.physical_keycode = keycode
        InputMap.action_add_event(action, ev)

## Rebinds one action to a new physical key, applies it immediately (the
## InputMap is global engine state, not scoped to the settings screen),
## and persists it right away — remap capture is expected to take effect
## the instant the player presses the new key, unlike the slider/checkbox
## rows which wait for "Apply & Save".
func rebind_action(action: String, keycode: Key) -> Error:
    if not REMAPPABLE_ACTIONS.any(func(e: Dictionary) -> bool: return String(e.get("action", "")) == action):
        return ERR_INVALID_PARAMETER
    keybinds[action] = int(keycode)
    _apply_keybinds()
    return save_settings()

func default_key_for(action: String) -> Key:
    for entry: Dictionary in REMAPPABLE_ACTIONS:
        if String(entry.get("action", "")) == action:
            return int(entry.get("default_key", KEY_NONE)) as Key
    return KEY_NONE

func current_key_for(action: String) -> Key:
    return int(keybinds.get(action, default_key_for(action))) as Key

func save_settings() -> Error:
    var cfg: ConfigFile = ConfigFile.new()
    cfg.set_value("meta", "settings_version", SETTINGS_VERSION)
    cfg.set_value("audio", "master", master_volume)
    cfg.set_value("audio", "music", music_volume)
    cfg.set_value("audio", "sfx", sfx_volume)
    cfg.set_value("audio", "ui", ui_volume)
    cfg.set_value("display", "ui_scale", ui_scale)
    cfg.set_value("display", "fullscreen", fullscreen)
    cfg.set_value("display", "resolution_index", resolution_index)
    cfg.set_value("accessibility", "reduced_motion", reduced_motion)
    cfg.set_value("accessibility", "camera_shake_enabled", camera_shake_enabled)
    cfg.set_value("accessibility", "high_contrast", high_contrast)
    cfg.set_value("accessibility", "colorblind_mode", colorblind_mode)
    cfg.set_value("accessibility", "pause_on_incident", pause_on_incident)
    cfg.set_value("accessibility", "tooltip_delay_sec", tooltip_delay_sec)
    for action: String in keybinds:
        cfg.set_value("keybinds", action, int(keybinds[action]))
    return cfg.save(SETTINGS_PATH)

## Always leaves the manager at a fully-defined, safe state: unreadable or
## newer-than-known config files fall back to defaults instead of partial data.
func load_settings() -> Error:
    reset_to_defaults()
    if not FileAccess.file_exists(SETTINGS_PATH):
        return ERR_FILE_NOT_FOUND
    var cfg: ConfigFile = ConfigFile.new()
    var err: Error = cfg.load(SETTINGS_PATH)
    if err != OK:
        push_warning("SettingsManager: failed to load settings.cfg (error %s); using defaults" % err)
        return err
    var version: int = int(cfg.get_value("meta", "settings_version", 0))
    if version > SETTINGS_VERSION:
        push_warning("SettingsManager: settings.cfg is a newer version (%s > %s); using defaults" % [version, SETTINGS_VERSION])
        return ERR_INVALID_DATA
    master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
    music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
    sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
    ui_volume = clampf(float(cfg.get_value("audio", "ui", ui_volume)), 0.0, 1.0)
    ui_scale = clampf(float(cfg.get_value("display", "ui_scale", ui_scale)), MIN_UI_SCALE, MAX_UI_SCALE)
    fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
    resolution_index = clampi(int(cfg.get_value("display", "resolution_index", resolution_index)), 0, RESOLUTIONS.size() - 1)
    reduced_motion = bool(cfg.get_value("accessibility", "reduced_motion", reduced_motion))
    camera_shake_enabled = bool(cfg.get_value("accessibility", "camera_shake_enabled", camera_shake_enabled))
    high_contrast = bool(cfg.get_value("accessibility", "high_contrast", high_contrast))
    colorblind_mode = bool(cfg.get_value("accessibility", "colorblind_mode", colorblind_mode))
    pause_on_incident = bool(cfg.get_value("accessibility", "pause_on_incident", pause_on_incident))
    tooltip_delay_sec = clampf(float(cfg.get_value("accessibility", "tooltip_delay_sec", tooltip_delay_sec)), MIN_TOOLTIP_DELAY_SEC, MAX_TOOLTIP_DELAY_SEC)
    keybinds = {}
    if cfg.has_section("keybinds"):
        for action: String in cfg.get_section_keys("keybinds"):
            keybinds[action] = int(cfg.get_value("keybinds", action, default_key_for(action)))
    return OK
