class_name Hud
extends CanvasLayer

## Reusable HUD shell: top resource strip, bottom section nav, left
## objectives panel, right contextual inspector. Anchor-based layout so it
## stays correct at 1280x720 and 1920x1080 without per-resolution tuning.
## Section buttons and the inspector are wired to be populated by future
## systems (build/staff/research/...); today they only show honest
## placeholders instead of doing nothing.

@onready var _cash_label: Label = $TopBar/Margin/HBox/CashLabel
@onready var _compute_label: Label = $TopBar/Margin/HBox/ComputeLabel
@onready var _power_label: Label = $TopBar/Margin/HBox/PowerLabel
@onready var _trust_label: Label = $TopBar/Margin/HBox/TrustLabel
@onready var _safety_label: Label = $TopBar/Margin/HBox/SafetyDebtLabel
@onready var _date_label: Label = $TopBar/Margin/HBox/DateLabel
@onready var _pause_button: Button = $TopBar/Margin/HBox/TimeControls/PauseButton
@onready var _speed_buttons: Array[Button] = [
    $TopBar/Margin/HBox/TimeControls/Speed1Button,
    $TopBar/Margin/HBox/TimeControls/Speed2Button,
    $TopBar/Margin/HBox/TimeControls/Speed3Button,
]
@onready var _inspector_title: Label = $RightPanel/Margin/VBox/Title
@onready var _inspector_body: Label = $RightPanel/Margin/VBox/Body
@onready var _section_buttons: Array[Button] = [
    $BottomBar/Margin/HBox/BuildButton,
    $BottomBar/Margin/HBox/StaffButton,
    $BottomBar/Margin/HBox/ResearchButton,
    $BottomBar/Margin/HBox/ModelsButton,
    $BottomBar/Margin/HBox/DeploymentsButton,
    $BottomBar/Margin/HBox/CompanyButton,
    $BottomBar/Margin/HBox/WorldButton,
]

func _ready() -> void:
    _pause_button.pressed.connect(_on_pause_pressed)
    for i in _speed_buttons.size():
        _speed_buttons[i].pressed.connect(_on_speed_pressed.bind(i + 1))
    for btn: Button in _section_buttons:
        btn.pressed.connect(_on_section_pressed.bind(btn.text))
    EventBus.selection_changed.connect(_on_selection_changed)
    EventBus.simulation_pause_changed.connect(_on_pause_changed)
    _sync_speed_buttons()
    _refresh_resource_strip()
    _refresh_inspector_empty()

func _process(_delta: float) -> void:
    _refresh_resource_strip()

func _refresh_resource_strip() -> void:
    _cash_label.text = "$%s" % _format_money(GameState.cash)
    _compute_label.text = "COMPUTE %d%%" % int(roundf(GameState.compute_used / GameState.compute_capacity * 100.0))
    _power_label.text = "POWER %d%%" % int(roundf(GameState.power_used / GameState.power_capacity * 100.0))
    _trust_label.text = "TRUST %d" % int(roundf(GameState.public_trust))
    _safety_label.text = "SAFETY DEBT %d" % int(roundf(GameState.safety_debt))
    _date_label.text = "DAY 1"  # TODO(P07): replace with the simulation clock's campaign date.
    _pause_button.text = "Resume" if GameState.paused else "Pause"

func _format_money(v: float) -> String:
    return "%d" % int(v)

func _on_pause_pressed() -> void:
    GameState.toggle_pause()

func _on_pause_changed(_paused: bool) -> void:
    _refresh_resource_strip()

func _on_speed_pressed(tier: int) -> void:
    GameState.simulation_speed = float(tier)
    _sync_speed_buttons()

func _sync_speed_buttons() -> void:
    var active_tier: int = int(round(GameState.simulation_speed))
    for i in _speed_buttons.size():
        _speed_buttons[i].button_pressed = (i + 1 == active_tier)

func _on_section_pressed(section_name: String) -> void:
    _inspector_title.text = section_name
    _inspector_body.text = "%s is not implemented yet." % section_name

func _refresh_inspector_empty() -> void:
    _inspector_title.text = "Inspector"
    _inspector_body.text = "Nothing selected."

func _on_selection_changed(kind: StringName, entity_id: String) -> void:
    if entity_id.is_empty():
        _refresh_inspector_empty()
        return
    _inspector_title.text = String(kind).capitalize()
    _inspector_body.text = "Selected: %s" % entity_id
