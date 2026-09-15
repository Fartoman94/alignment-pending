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
# docs/technical/INPUT_CAMERA.md / P07 spec: pause/1x/2x/4x, not 1x/2x/3x.
const SPEED_TIER_VALUES: Array[float] = [1.0, 2.0, 4.0]
@onready var _inspector_title: Label = $RightPanel/Margin/VBox/Title
@onready var _inspector_body: Label = $RightPanel/Margin/VBox/Body
@onready var _dynamic_content: VBoxContainer = $RightPanel/Margin/VBox/DynamicContent
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
        _speed_buttons[i].pressed.connect(_on_speed_pressed.bind(i))
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
    _date_label.text = SimClock.format_calendar()
    _pause_button.text = "Resume" if GameState.paused else "Pause"

func _format_money(v: float) -> String:
    return "%d" % int(v)

func _on_pause_pressed() -> void:
    GameState.toggle_pause()

func _on_pause_changed(_paused: bool) -> void:
    _refresh_resource_strip()

func _on_speed_pressed(tier_index: int) -> void:
    GameState.simulation_speed = SPEED_TIER_VALUES[tier_index]
    _sync_speed_buttons()

func _sync_speed_buttons() -> void:
    for i in _speed_buttons.size():
        _speed_buttons[i].button_pressed = is_equal_approx(SPEED_TIER_VALUES[i], GameState.simulation_speed)

func _on_section_pressed(section_name: String) -> void:
    if section_name == "Build":
        _show_build_palette()
        return
    if section_name == "Staff":
        _show_staff_panel()
        return
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = section_name
    _inspector_body.text = "%s is not implemented yet." % section_name

func _refresh_inspector_empty() -> void:
    _clear_dynamic_content()
    _inspector_title.text = "Inspector"
    _inspector_body.text = "Nothing selected."

func _on_selection_changed(kind: StringName, entity_id: String) -> void:
    if entity_id.is_empty():
        _refresh_inspector_empty()
        return
    _clear_dynamic_content()
    _inspector_title.text = String(kind).capitalize()
    _inspector_body.text = "Selected: %s" % entity_id

func _clear_dynamic_content() -> void:
    for child in _dynamic_content.get_children():
        child.queue_free()

func _show_build_palette() -> void:
    _clear_dynamic_content()
    _inspector_title.text = "Build"
    _inspector_body.text = "Choose what to place. R rotates, click places. Esc cancels."
    var catalog: Dictionary = BuildableCatalog.load_all()
    for buildable_id: String in catalog:
        var def: Dictionary = catalog[buildable_id]
        var btn: Button = Button.new()
        btn.text = "%s ($%d)" % [String(def.get("name", buildable_id)), int(def.get("cost", 0))]
        btn.pressed.connect(func() -> void: EventBus.build_tool_changed.emit(buildable_id))
        _dynamic_content.add_child(btn)
    var sell_btn: Button = Button.new()
    sell_btn.text = "Sell"
    sell_btn.pressed.connect(func() -> void: EventBus.build_tool_changed.emit("sell"))
    _dynamic_content.add_child(sell_btn)
    var cancel_btn: Button = Button.new()
    cancel_btn.text = "Cancel"
    cancel_btn.pressed.connect(func() -> void: EventBus.build_tool_changed.emit(""))
    _dynamic_content.add_child(cancel_btn)

func _show_staff_panel() -> void:
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = "Staff"
    _inspector_body.text = "Roster: %d   Daily payroll: $%d" % [GameState.staff.size(), int(StaffManager.total_payroll())]

    for member: Variant in GameState.staff:
        var entry: Dictionary = member
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        label.text = "%s — %s ($%d/day, morale %d%%)" % [
            entry.get("generated_name", "?"), entry.get("role", "?"),
            int(entry.get("salary", 0.0)), int(entry.get("morale", 0)),
        ]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.add_child(label)
        var staff_id: String = String(entry.get("id", ""))
        var inspect_btn: Button = Button.new()
        inspect_btn.text = "Inspect"
        inspect_btn.pressed.connect(func() -> void: _show_staff_detail(staff_id))
        row.add_child(inspect_btn)
        var fire_btn: Button = Button.new()
        fire_btn.text = "Fire"
        fire_btn.pressed.connect(func() -> void:
            StaffManager.fire(staff_id)
            _show_staff_panel()
        )
        row.add_child(fire_btn)
        _dynamic_content.add_child(row)

    var separator: Label = Label.new()
    separator.text = "Candidates"
    _dynamic_content.add_child(separator)

    for i in StaffManager.candidates.size():
        var candidate: Dictionary = StaffManager.candidates[i]
        var row2: HBoxContainer = HBoxContainer.new()
        var label2: Label = Label.new()
        label2.text = "%s — %s ($%d/day)" % [
            candidate.get("generated_name", "?"), candidate.get("role", "?"), int(candidate.get("salary", 0.0)),
        ]
        label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row2.add_child(label2)
        var hire_btn: Button = Button.new()
        hire_btn.text = "Hire"
        var candidate_index: int = i
        hire_btn.pressed.connect(func() -> void:
            StaffManager.hire(candidate_index)
            _show_staff_panel()
        )
        row2.add_child(hire_btn)
        _dynamic_content.add_child(row2)

func _show_staff_detail(staff_id: String) -> void:
    var member: Dictionary = StaffManager.find(staff_id)
    if member.is_empty():
        _show_staff_panel()
        return
    _clear_dynamic_content()
    _inspector_title.text = String(member.get("generated_name", "Staff"))
    var skills: Dictionary = member.get("skills", {})
    var skill_parts: PackedStringArray = []
    for key: String in skills:
        skill_parts.append("%s %d" % [String(key).capitalize(), int(skills[key])])
    _inspector_body.text = "Role: %s\nSalary: $%d/day\nMorale: %d%%\nFatigue: %d%%\nHired day %d\nSkills: %s" % [
        member.get("role", "?"), int(member.get("salary", 0.0)), int(member.get("morale", 0)),
        int(member.get("fatigue", 0)), int(member.get("hire_date", 0)), ", ".join(skill_parts),
    ]
    var fire_btn: Button = Button.new()
    fire_btn.text = "Fire"
    fire_btn.pressed.connect(func() -> void:
        StaffManager.fire(staff_id)
        _show_staff_panel()
    )
    _dynamic_content.add_child(fire_btn)
    var back_btn: Button = Button.new()
    back_btn.text = "Back"
    back_btn.pressed.connect(_show_staff_panel)
    _dynamic_content.add_child(back_btn)
