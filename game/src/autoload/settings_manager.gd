extends Node

## Persists and applies audio, display and accessibility settings.
## Separate from GameState/SaveManager: settings are a player-machine
## preference, not campaign save data, and survive across campaigns.

const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_VERSION: int = 1

const MIN_UI_SCALE: float = 0.8
const MAX_UI_SCALE: float = 1.6

const RESOLUTIONS: Array[Vector2i] = [
    Vector2i(1280, 720),
    Vector2i(1600, 900),
    Vector2i(1920, 1080),
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

func get_resolution() -> Vector2i:
    resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)
    return RESOLUTIONS[resolution_index]

func apply_all() -> void:
    _apply_audio()
    _apply_ui_scale()
    _apply_window_mode()

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
    return OK
