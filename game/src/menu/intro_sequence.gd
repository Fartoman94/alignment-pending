extends Control

## Brief, skippable title-sequence beats shown once before the main menu
## (`ULTIMATE_IMPLEMENTATION_BUNDLE`'s "Intro breve y clara" ask). Content
## kept as a plain typed const here rather than a new data/*.json file —
## it's fixed narrative copy referenced nowhere else, not a tunable
## content catalog like the gameplay JSON files this project otherwise
## validates through DataValidator.
const BEATS: Array[Dictionary] = [
    {"text": "ALIGNMENT PENDING", "duration": 1.8},
    {"text": "Build. Train. Deploy. Deal with it.", "duration": 1.8},
    {"text": "Every great company starts in a garage.", "duration": 2.0},
    {"text": "Hire your first employees. Ship your first model.", "duration": 2.0},
]
const FADE_DURATION_SEC: float = 0.4

@onready var _label: Label = $Label
@onready var _skip_hint: Label = $SkipHint
var _index: int = -1
var _advancing: bool = false

func _ready() -> void:
    LocalizationManager.localize_control_tree(self)
    _label.modulate.a = 0.0
    if SettingsManager.reduced_motion:
        # No timed fade sequence for reduced-motion players — go straight
        # to the menu, same "skip the non-essential animation" treatment
        # P42 already applies to every other purely decorative effect.
        _finish()
        return
    _advance()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed or event is InputEventJoypadButton and event.pressed:
        _finish()
        get_viewport().set_input_as_handled()

func _advance() -> void:
    if _advancing:
        return
    _index += 1
    if _index >= BEATS.size():
        _finish()
        return
    var beat: Dictionary = BEATS[_index]
    _label.text = LocalizationManager.tr_text(String(beat.get("text", "")))
    var duration: float = float(beat.get("duration", 2.0))
    var tween: Tween = create_tween()
    tween.tween_property(_label, "modulate:a", 1.0, FADE_DURATION_SEC)
    tween.tween_interval(maxf(0.0, duration - FADE_DURATION_SEC * 2.0))
    tween.tween_property(_label, "modulate:a", 0.0, FADE_DURATION_SEC)
    tween.finished.connect(_advance)

func _finish() -> void:
    if _advancing:
        return
    _advancing = true
    await SceneRouter.go_to("res://scenes/main_menu.tscn")
