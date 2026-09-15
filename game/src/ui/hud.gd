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
@onready var _heat_label: Label = $TopBar/Margin/HBox/HeatLabel
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
@onready var _incident_empty_label: Label = $LeftPanel/Margin/VBox/EmptyLabel
@onready var _incident_list: VBoxContainer = $LeftPanel/Margin/VBox/IncidentList
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
    EventBus.incident_raised.connect(_on_incident_raised)
    _sync_speed_buttons()
    _refresh_resource_strip()
    _refresh_inspector_empty()
    _refresh_incident_inbox()

func _process(_delta: float) -> void:
    _refresh_resource_strip()

func _refresh_resource_strip() -> void:
    _cash_label.text = "$%s" % _format_money(GameState.cash)
    var effective_compute: float = GameState.effective_compute_capacity()
    _compute_label.text = "COMPUTE %d%%" % int(roundf(GameState.compute_used / GameState.compute_capacity * 100.0))
    _compute_label.tooltip_text = "%.0f / %.0f used (%.0f effective after heat throttling). Training jobs need free headroom." % [
        GameState.compute_used, GameState.compute_capacity, effective_compute,
    ]
    _power_label.text = "POWER %d%%" % int(roundf(GameState.power_used / GameState.power_capacity * 100.0))
    _power_label.tooltip_text = "%.0f / %.0f drawn. Building a rack that would exceed capacity is blocked." % [
        GameState.power_used, GameState.power_capacity,
    ]
    _trust_label.text = "TRUST %d" % int(roundf(GameState.public_trust))
    _trust_label.tooltip_text = _format_trust_causes_tooltip()
    _safety_label.text = "SAFETY DEBT %d" % int(roundf(GameState.safety_debt))
    var heat_pct: int = int(roundf(GameState.heat_load / GameState.heat_capacity * 100.0)) if GameState.heat_capacity > 0.0 else 0
    _heat_label.text = "HEAT %d%%" % heat_pct
    _heat_label.tooltip_text = "%.0f / %.0f. Over capacity throttles effective compute instead of corrupting state." % [
        GameState.heat_load, GameState.heat_capacity,
    ]
    _date_label.text = SimClock.format_calendar()
    _pause_button.text = "Resume" if GameState.paused else "Pause"

func _format_money(v: float) -> String:
    return "%d" % int(v)

func _format_trust_causes_tooltip() -> String:
    var causes: Array = CommunicationManager.recent_trust_causes(4)
    if causes.is_empty():
        return "Trust: %d. No recorded causes yet." % int(round(GameState.public_trust))
    var lines: PackedStringArray = ["Recent causes:"]
    for c: Variant in causes:
        var entry: Dictionary = c
        lines.append("Day %d: %s (%+.0f)" % [int(entry.get("day", 0)), String(entry.get("label", "?")), float(entry.get("delta", 0.0))])
    return "\n".join(lines)

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
    if section_name == "Research":
        _show_research_panel()
        return
    if section_name == "Models":
        _show_models_panel()
        return
    if section_name == "Company":
        _show_company_panel()
        return
    if section_name == "World":
        _show_world_panel()
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

func _on_incident_raised(_incident_id: StringName) -> void:
    _refresh_incident_inbox()

func _refresh_incident_inbox() -> void:
    for child in _incident_list.get_children():
        child.queue_free()
    var pending: Array = GameState.pending_incidents
    _incident_empty_label.visible = pending.is_empty()
    for p: Variant in pending:
        var entry: Dictionary = p
        var pending_id: String = String(entry.get("id", ""))
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        var severity: int = int(entry.get("severity", 2))
        label.text = "%s%s" % ["[P%d] " % severity if severity <= 0 else "", String(entry.get("title", "?"))]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.add_child(label)
        var respond_btn: Button = Button.new()
        respond_btn.text = "Respond"
        respond_btn.pressed.connect(func() -> void: _show_incident_detail(pending_id))
        row.add_child(respond_btn)
        _incident_list.add_child(row)

func _show_incident_detail(pending_id: String) -> void:
    var entry: Dictionary = IncidentManager.find_pending(pending_id)
    if entry.is_empty():
        return
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = String(entry.get("title", "Incident"))
    _inspector_body.text = "%s\n\nCategory: %s   Severity: P%d" % [
        String(entry.get("body", "")), String(entry.get("category", "?")), int(entry.get("severity", 2)),
    ]
    for c: Variant in (entry.get("choices", []) as Array):
        var choice: Dictionary = c
        var choice_id: String = String(choice.get("id", ""))
        var btn: Button = Button.new()
        var effects: Dictionary = choice.get("effects", {})
        var effect_parts: PackedStringArray = []
        for key: String in effects:
            effect_parts.append("%s %+.0f" % [key, float(effects[key])])
        var effect_text: String = "" if effect_parts.is_empty() else " (%s)" % ", ".join(effect_parts)
        btn.text = "%s%s" % [String(choice.get("label", choice_id)), effect_text]
        btn.pressed.connect(func() -> void:
            IncidentManager.resolve(pending_id, choice_id)
            _refresh_incident_inbox()
            _refresh_inspector_empty()
        )
        _dynamic_content.add_child(btn)

func _show_build_palette() -> void:
    _clear_dynamic_content()
    _inspector_title.text = "Build"
    _inspector_body.text = "Choose what to place. R rotates, click places. Esc cancels."
    var catalog: Dictionary = BuildableCatalog.load_all()
    for buildable_id: String in catalog:
        var def: Dictionary = catalog[buildable_id]
        var btn: Button = Button.new()
        btn.text = "%s ($%d)" % [String(def.get("name", buildable_id)), int(def.get("cost", 0))]
        if def.has("compute_units") or def.has("power_draw") or def.has("heat_output"):
            btn.tooltip_text = "+%d compute, +%d power draw, +%d heat, $%d/day upkeep" % [
                int(def.get("compute_units", 0)), int(def.get("power_draw", 0)),
                int(def.get("heat_output", 0)), int(def.get("operating_cost_per_day", 0)),
            ]
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

func _show_research_panel() -> void:
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = "Research"
    _inspector_body.text = "Assign a researcher to a desk (Staff > Inspect > Assign) to make progress on a started node."

    for node_id: String in ResearchNodeCatalog.ordered_ids():
        var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        var prereqs: Array = def.get("prerequisites", [])
        var prereq_names: PackedStringArray = []
        for prereq: Variant in prereqs:
            prereq_names.append(String(ResearchNodeCatalog.get_def(String(prereq)).get("name", prereq)))
        var prereq_text: String = "" if prereq_names.is_empty() else " (needs %s)" % ", ".join(prereq_names)

        var status: String
        if ResearchManager.is_unlocked(node_id):
            status = "Unlocked"
        elif ResearchManager.is_active(node_id):
            status = "In progress %d%%" % int(round(ResearchManager.node_progress_fraction(node_id) * 100.0))
        elif ResearchManager.prerequisites_met(node_id):
            status = "Available"
        else:
            status = "Locked"

        label.text = "[%s] %s — $%d%s — %s" % [
            String(def.get("branch", "?")).capitalize(), String(def.get("name", node_id)),
            int(def.get("cost", 0)), prereq_text, status,
        ]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.add_child(label)

        if not ResearchManager.is_unlocked(node_id) and not ResearchManager.is_active(node_id):
            var start_btn: Button = Button.new()
            start_btn.text = "Start"
            start_btn.disabled = not ResearchManager.can_start(node_id)
            start_btn.pressed.connect(func() -> void:
                ResearchManager.start(node_id)
                _show_research_panel()
            )
            row.add_child(start_btn)

        _dynamic_content.add_child(row)

func _show_models_panel() -> void:
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = "Models"
    _inspector_body.text = "Trained: %d   Configure a project below, then assign a researcher (Staff > Inspect > Assign)." % GameState.models.size()

    for tier_id: String in ModelTierCatalog.ordered_ids():
        var tier: Dictionary = ModelTierCatalog.get_def(tier_id)
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        label.text = "%s — $%d" % [String(tier.get("name", tier_id)), int(tier.get("cost", 0))]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.tooltip_text = "capability~%d safety~%d cost_eff~%d autonomy~%d" % [
            int(tier.get("capability_base", 0)), int(tier.get("safety_base", 0)),
            int(tier.get("cost_efficiency_base", 0)), int(tier.get("autonomy_base", 0)),
        ]
        row.add_child(label)
        var start_btn: Button = Button.new()
        start_btn.text = "Start Training"
        start_btn.disabled = not ModelManager.can_start(tier_id)
        start_btn.pressed.connect(func() -> void:
            ModelManager.start_project(tier_id)
            _show_models_panel()
        )
        row.add_child(start_btn)
        _dynamic_content.add_child(row)

    if not GameState.model_projects.is_empty():
        var projects_header: Label = Label.new()
        projects_header.text = "In progress"
        _dynamic_content.add_child(projects_header)
        for project: Variant in GameState.model_projects:
            var p: Dictionary = project
            var project_id: String = String(p.get("id", ""))
            var tier_def: Dictionary = ModelTierCatalog.get_def(String(p.get("tier_id", "")))
            var prow: HBoxContainer = HBoxContainer.new()
            var plabel: Label = Label.new()
            plabel.text = "%s (%d%%)" % [String(tier_def.get("name", "?")), int(round(ModelManager.project_progress_fraction(project_id) * 100.0))]
            plabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            prow.add_child(plabel)
            var cancel_btn: Button = Button.new()
            cancel_btn.text = "Cancel"
            cancel_btn.pressed.connect(func() -> void:
                ModelManager.cancel_project(project_id)
                _show_models_panel()
            )
            prow.add_child(cancel_btn)
            _dynamic_content.add_child(prow)

    if not GameState.models.is_empty():
        var models_header: Label = Label.new()
        models_header.text = "Trained models (ranges shown, not exact — evaluate to narrow them)"
        _dynamic_content.add_child(models_header)
        for model: Variant in GameState.models:
            var m: Dictionary = model
            var model_id: String = String(m.get("id", ""))
            var depth: int = int(m.get("evals_completed", 0))
            var cap_range: Vector2 = EvaluationManager.visible_range(model_id, "capability")
            var safety_range: Vector2 = EvaluationManager.visible_range(model_id, "safety_confidence")
            var risk_range: Vector2 = EvaluationManager.latent_risk_range(model_id)
            var risk_text: String = "Unknown" if depth <= 0 else "%d-%d" % [int(risk_range.x), int(risk_range.y)]
            var row: HBoxContainer = HBoxContainer.new()
            var mlabel: Label = Label.new()
            mlabel.text = "%s — capability %d-%d, safety %d-%d, latent risk %s (eval depth %d/%d)" % [
                String(m.get("name", "?")), int(cap_range.x), int(cap_range.y),
                int(safety_range.x), int(safety_range.y), risk_text, depth, EvaluationManager.MAX_EVAL_DEPTH,
            ]
            mlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            mlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            row.add_child(mlabel)
            var eval_btn: Button = Button.new()
            eval_btn.text = "Evaluate ($%d)" % int(EvaluationManager.EVAL_COST)
            eval_btn.disabled = not EvaluationManager.can_request(model_id)
            eval_btn.pressed.connect(func() -> void:
                EvaluationManager.request_evaluation(model_id)
                _show_models_panel()
            )
            row.add_child(eval_btn)
            _dynamic_content.add_child(row)
            _add_deployment_controls(model_id)

## Deploy/Promote/Rollback + rate-limit slider for one trained model,
## reflecting Internal/Beta/Public staged rollout (docs/design/UI_UX.md's
## release screen actions, minus "Delay" which is just not deploying yet).
func _add_deployment_controls(model_id: String) -> void:
    var deployment: Dictionary = {}
    for d: Variant in GameState.deployments:
        if String((d as Dictionary).get("model_id", "")) == model_id:
            deployment = d
            break

    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    if deployment.is_empty():
        label.text = "  Not deployed"
        row.add_child(label)
        var deploy_btn: Button = Button.new()
        deploy_btn.text = "Deploy (Internal)"
        deploy_btn.pressed.connect(func() -> void:
            ReleaseManager.deploy(model_id)
            _show_models_panel()
        )
        row.add_child(deploy_btn)
        _dynamic_content.add_child(row)
        return

    var deployment_id: String = String(deployment.get("id", ""))
    var mode_id: String = String(deployment.get("mode_id", ""))
    var mode_def: Dictionary = DeploymentModeCatalog.get_def(mode_id)
    label.text = "  %s — rollout %d%%, users ~%d, exposure ~%d" % [
        String(mode_def.get("name", mode_id)),
        int(round(float(deployment.get("rollout_stage", 0.0)) * 100.0)),
        int(ReleaseManager.current_user_scale(deployment)),
        int(ReleaseManager.total_incident_exposure()),
    ]
    row.add_child(label)

    var next_mode: String = DeploymentModeCatalog.next_mode(mode_id)
    if not next_mode.is_empty():
        var promote_btn: Button = Button.new()
        promote_btn.text = "Promote to %s" % String(DeploymentModeCatalog.get_def(next_mode).get("name", next_mode))
        promote_btn.pressed.connect(func() -> void:
            ReleaseManager.promote(deployment_id)
            _show_models_panel()
        )
        row.add_child(promote_btn)

    var rollback_btn: Button = Button.new()
    rollback_btn.text = "Rollback"
    rollback_btn.pressed.connect(func() -> void:
        ReleaseManager.rollback(deployment_id)
        _show_models_panel()
    )
    row.add_child(rollback_btn)
    _dynamic_content.add_child(row)

    var slider_row: HBoxContainer = HBoxContainer.new()
    var slider_label: Label = Label.new()
    slider_label.text = "  Rate limit"
    slider_label.custom_minimum_size = Vector2(90, 0)
    slider_row.add_child(slider_label)
    var slider: HSlider = HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.05
    slider.value = float(deployment.get("rate_limit", 1.0))
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(func(value: float) -> void:
        ReleaseManager.set_rate_limit(deployment_id, value)
    )
    slider_row.add_child(slider)
    _dynamic_content.add_child(slider_row)

    var price: float = float(deployment.get("price", RevenueManager.DEFAULT_PRICE))
    var breakdown: Dictionary = RevenueManager.compute_breakdown(deployment)
    var price_row: HBoxContainer = HBoxContainer.new()
    var price_label: Label = Label.new()
    price_label.text = "  Price $%.2f" % price
    price_label.custom_minimum_size = Vector2(90, 0)
    price_row.add_child(price_label)
    var price_slider: HSlider = HSlider.new()
    price_slider.min_value = 0.0
    price_slider.max_value = 50.0
    price_slider.step = 0.5
    price_slider.value = price
    price_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    price_slider.value_changed.connect(func(value: float) -> void:
        RevenueManager.set_price(deployment_id, value)
        _show_models_panel()
    )
    price_row.add_child(price_slider)
    _dynamic_content.add_child(price_row)

    var revenue_label: Label = Label.new()
    revenue_label.text = "  ~%d users/day — revenue $%.0f, inference cost $%.0f, net $%.0f/day" % [
        int(round(float(breakdown.get("total_users", 0.0)))),
        float(breakdown.get("total_revenue", 0.0)),
        float(breakdown.get("total_cost", 0.0)),
        float(breakdown.get("net", 0.0)),
    ]
    revenue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _dynamic_content.add_child(revenue_label)

## Trust/hype/communication actions plus the incident history log. PR
## actions here can only ever nudge trust (see
## CommunicationActionCatalog's data-validated cap) — the incident log
## itself is read-only and never touched by any action on this panel, so
## severe evidence stays visible no matter how much PR is bought.
func _show_company_panel() -> void:
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = "Company"
    _inspector_body.text = "Trust %d   Hype debt %d — unresolved hype converts to trust loss over time.\n%s regulatory pressure: %d/100" % [
        int(round(GameState.public_trust)), int(round(GameState.hype_debt)),
        RegulatorManager.regulator_name(), int(round(GameState.regulatory_pressure)),
    ]

    var ledger: Dictionary = EconomyManager.daily_ledger()
    var runway: float = EconomyManager.runway_days()
    var runway_text: String = "no limit" if is_inf(runway) else "%d days" % int(floor(runway))
    var ledger_label: Label = Label.new()
    ledger_label.text = "Daily ledger: payroll -$%d, infra -$%d, rent -$%d, legal -$%d, support -$%d, revenue +$%d → net %+.0f/day. Runway: %s." % [
        int(ledger.get("payroll", 0.0)), int(ledger.get("infrastructure", 0.0)), int(ledger.get("rent", 0.0)),
        int(ledger.get("legal", 0.0)), int(ledger.get("support", 0.0)), int(ledger.get("revenue", 0.0)),
        float(ledger.get("net", 0.0)), runway_text,
    ]
    ledger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _dynamic_content.add_child(ledger_label)
    if GameState.bankruptcy_day >= 0:
        var bankruptcy_label: Label = Label.new()
        bankruptcy_label.text = "BANKRUPTCY: recover before cash goes negative again, or in %d day(s) the company folds." % EconomyManager.bankruptcy_days_remaining()
        bankruptcy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _dynamic_content.add_child(bankruptcy_label)

    if RegulatorManager.has_active_audit():
        var audit_header: Label = Label.new()
        audit_header.text = "Audit in progress — due day %d" % int(GameState.active_audit.get("deadline_day", 0))
        _dynamic_content.add_child(audit_header)
        for req: Variant in (GameState.active_audit.get("requirements", []) as Array):
            var req_label: Label = Label.new()
            req_label.text = "- %s" % String(req)
            req_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            _dynamic_content.add_child(req_label)
        var audit_row: HBoxContainer = HBoxContainer.new()
        var full_btn: Button = Button.new()
        full_btn.text = "Full disclosure"
        full_btn.pressed.connect(func() -> void:
            RegulatorManager.resolve_audit("full_disclosure")
            _show_company_panel()
        )
        audit_row.add_child(full_btn)
        var minimal_btn: Button = Button.new()
        minimal_btn.text = "Minimal disclosure"
        minimal_btn.pressed.connect(func() -> void:
            RegulatorManager.resolve_audit("minimal_disclosure")
            _show_company_panel()
        )
        audit_row.add_child(minimal_btn)
        _dynamic_content.add_child(audit_row)

    var actions_header: Label = Label.new()
    actions_header.text = "Communication actions"
    _dynamic_content.add_child(actions_header)
    for action_id: String in CommunicationActionCatalog.ordered_ids():
        var def: Dictionary = CommunicationActionCatalog.get_def(action_id)
        var row: HBoxContainer = HBoxContainer.new()
        var label: Label = Label.new()
        label.text = "%s — $%d (trust %+.0f, hype %+.0f)" % [
            String(def.get("name", action_id)), int(def.get("cost", 0)),
            float(def.get("trust_delta", 0.0)), float(def.get("hype_debt_delta", 0.0)),
        ]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        row.add_child(label)
        var btn: Button = Button.new()
        btn.text = "Do"
        btn.disabled = not CommunicationManager.can_perform(action_id)
        btn.pressed.connect(func() -> void:
            CommunicationManager.perform(action_id)
            _show_company_panel()
        )
        row.add_child(btn)
        _dynamic_content.add_child(row)

    var history_header: Label = Label.new()
    history_header.text = "Incident history (evidence — never erasable)"
    _dynamic_content.add_child(history_header)
    if GameState.incident_history.is_empty():
        var none_label: Label = Label.new()
        none_label.text = "No incidents yet."
        _dynamic_content.add_child(none_label)
    else:
        var history: Array = GameState.incident_history.duplicate()
        history.reverse()
        for h: Variant in history:
            var entry: Dictionary = h
            var effects: Dictionary = entry.get("effects_applied", {})
            var hist_label: Label = Label.new()
            hist_label.text = "Day %d [P%d] %s — chose \"%s\" (trust %+.0f, safety debt %+.0f)" % [
                int(entry.get("resolved_day", 0)), int(entry.get("severity", 2)), String(entry.get("title", "?")),
                String(entry.get("choice_id", "?")), float(effects.get("public_trust", 0.0)), float(effects.get("safety_debt", 0.0)),
            ]
            hist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            _dynamic_content.add_child(hist_label)

func _show_world_panel() -> void:
    EventBus.build_tool_changed.emit("")
    _clear_dynamic_content()
    _inspector_title.text = "World"
    if GameState.rival.is_empty():
        _inspector_body.text = "No rival identified yet."
        return
    var doctrine_def: Dictionary = RivalDoctrineCatalog.get_def(String(GameState.rival.get("doctrine", "")))
    _inspector_body.text = "%s\nDoctrine: %s\nGeneration %d launched — next launch in ~%d%% progress\nMarket pressure: %.1f" % [
        String(GameState.rival.get("name", "?")), String(doctrine_def.get("name", "?")),
        int(GameState.rival.get("generation", 0)), int(round(RivalManager.launch_progress_fraction() * 100.0)),
        RivalManager.rival_pressure(),
    ]
    if not GameState.rival_launch_history.is_empty():
        var header: Label = Label.new()
        header.text = "Launch history"
        _dynamic_content.add_child(header)
        var history: Array = GameState.rival_launch_history.duplicate()
        history.reverse()
        for h: Variant in history:
            var entry: Dictionary = h
            var label: Label = Label.new()
            label.text = "Day %d — generation %d" % [int(entry.get("day", 0)), int(entry.get("generation", 0))]
            _dynamic_content.add_child(label)

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
    var status_line: String = "Idle"
    var assigned_task: String = String(member.get("assigned_task", ""))
    if not assigned_task.is_empty():
        var order: Dictionary = TaskManager.find_order_for_staff(staff_id)
        if not order.is_empty():
            var task_def: Dictionary = WorkTaskCatalog.get_def(String(order.get("task_id", "")))
            var order_task_id: String = String(order.get("task_id", ""))
            var order_target: String = String(order.get("target_id", ""))
            var target_suffix: String = ""
            if not order_target.is_empty():
                var target_name: String = order_target
                if order_task_id == ResearchManager.RESEARCH_TASK_ID:
                    target_name = String(ResearchNodeCatalog.get_def(order_target).get("name", order_target))
                elif order_task_id == ModelManager.TRAINING_TASK_ID:
                    var order_tier_id: String = ModelManager.project_tier_id(order_target)
                    target_name = String(ModelTierCatalog.get_def(order_tier_id).get("name", order_tier_id))
                elif order_task_id == EvaluationManager.EVAL_TASK_ID:
                    target_name = ModelManager.model_name(order_target)
                target_suffix = " → %s" % target_name
            status_line = "Working: %s%s (%d%%)" % [
                String(task_def.get("name", "?")), target_suffix, int(round(TaskManager.progress_fraction(order) * 100.0)),
            ]
    _inspector_body.text = "Role: %s\nSalary: $%d/day\nMorale: %d%%\nFatigue: %d%%\nHired day %d\nSkills: %s\nStatus: %s" % [
        member.get("role", "?"), int(member.get("salary", 0.0)), int(member.get("morale", 0)),
        int(member.get("fatigue", 0)), int(member.get("hire_date", 0)), ", ".join(skill_parts), status_line,
    ]

    if not assigned_task.is_empty():
        var cancel_btn: Button = Button.new()
        cancel_btn.text = "Cancel task"
        cancel_btn.pressed.connect(func() -> void:
            TaskManager.cancel(staff_id)
            _show_staff_detail(staff_id)
        )
        _dynamic_content.add_child(cancel_btn)
    else:
        for task_id: String in WorkTaskCatalog.load_all():
            var task_def: Dictionary = WorkTaskCatalog.load_all()[task_id]
            var required_skill: String = String(task_def.get("required_skill", ""))
            if int(skills.get(required_skill, 0)) <= 0:
                continue
            # research_sprint/training_run need an active started
            # node/project to apply progress to; none active means there's
            # nothing to work on yet.
            var assign_target: String = ""
            var target_label: String = ""
            if task_id == ResearchManager.RESEARCH_TASK_ID:
                assign_target = ResearchManager.pick_active_node_for_assignment()
                if assign_target.is_empty():
                    continue
                target_label = String(ResearchNodeCatalog.get_def(assign_target).get("name", assign_target))
            elif task_id == ModelManager.TRAINING_TASK_ID:
                assign_target = ModelManager.pick_active_project_for_assignment()
                if assign_target.is_empty():
                    continue
                var tier_id: String = ModelManager.project_tier_id(assign_target)
                target_label = String(ModelTierCatalog.get_def(tier_id).get("name", tier_id))
            elif task_id == EvaluationManager.EVAL_TASK_ID:
                assign_target = EvaluationManager.pick_model_for_evaluation_assignment()
                if assign_target.is_empty():
                    continue
                target_label = ModelManager.model_name(assign_target)
            var candidates: Array = TaskManager.available_buildings_for_task(task_id)
            if candidates.is_empty():
                continue
            var assign_btn: Button = Button.new()
            var label_suffix: String = "" if target_label.is_empty() else " (%s)" % target_label
            assign_btn.text = "Assign: %s%s" % [String(task_def.get("name", task_id)), label_suffix]
            var target_building_id: String = String((candidates[0] as Dictionary).get("id", ""))
            assign_btn.pressed.connect(func() -> void:
                TaskManager.assign(staff_id, task_id, target_building_id, assign_target)
                _show_staff_detail(staff_id)
            )
            _dynamic_content.add_child(assign_btn)

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
