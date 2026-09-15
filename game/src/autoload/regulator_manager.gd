extends Node

## One fictional regulator pressure meter (docs SYSTEMS_CATALOG S12,
## GDD "One regulator track" for the MVP). Pressure responds daily to
## deployed scale and safety_debt, and to any incident choice carrying a
## "regulatory_pressure" effect (see DataValidator.EVENT_EFFECT_KEYS).
## Crossing a threshold triggers an audit with a clear, data-driven
## requirements checklist and a disclosure choice.

const CONFIG_PATH: String = "res://data/regulator_track.json"
const SCALE_PRESSURE_PER_1K_USERS: float = 0.05
const DEBT_PRESSURE_PER_POINT: float = 0.02

var _config: Dictionary = {}

func _ready() -> void:
    _load_config()
    EventBus.day_advanced.connect(_on_day_advanced)

func _load_config() -> void:
    if not _config.is_empty():
        return
    var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        push_error("RegulatorManager: could not open %s" % CONFIG_PATH)
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary:
        _config = parsed
    else:
        push_error("RegulatorManager: %s root must be a JSON object" % CONFIG_PATH)

func regulator_name() -> String:
    return String(_config.get("name", "Regulator"))

func requirements() -> Array:
    return (_config.get("requirements", []) as Array).duplicate()

func has_active_audit() -> bool:
    return not GameState.active_audit.is_empty()

func _on_day_advanced(_day: int) -> void:
    var scale_pressure: float = (ReleaseManager.total_user_scale() / 1000.0) * SCALE_PRESSURE_PER_1K_USERS
    var debt_pressure: float = GameState.safety_debt * DEBT_PRESSURE_PER_POINT
    GameState.regulatory_pressure = clampf(GameState.regulatory_pressure + scale_pressure + debt_pressure, 0.0, 100.0)
    _maybe_trigger_audit()

func _maybe_trigger_audit() -> void:
    if has_active_audit():
        return
    var threshold: float = float(_config.get("audit_threshold", 50.0))
    if GameState.regulatory_pressure < threshold:
        return
    GameState.active_audit = {
        "id": String(_config.get("id", "regulator")),
        "triggered_day": GameState.calendar_day,
        "deadline_day": GameState.calendar_day + int(_config.get("audit_deadline_days", 14)),
        "requirements": requirements(),
    }
    EventBus.audit_triggered.emit()

## disclosure_id is "full_disclosure" or "minimal_disclosure" — the two
## data-driven consequences an audit resolves into.
func resolve_audit(disclosure_id: String) -> Error:
    if not has_active_audit():
        return ERR_DOES_NOT_EXIST
    if disclosure_id != "full_disclosure" and disclosure_id != "minimal_disclosure":
        return ERR_INVALID_PARAMETER
    var effects: Dictionary = _config.get(disclosure_id, {})
    _apply_effects(effects)
    GameState.audit_history.append({
        "id": GameState.active_audit.get("id", ""),
        "triggered_day": GameState.active_audit.get("triggered_day", 0),
        "resolved_day": GameState.calendar_day,
        "disclosure_choice": disclosure_id,
        "effects_applied": effects,
    })
    GameState.active_audit = {}
    return OK

func _apply_effects(effects: Dictionary) -> void:
    if effects.has("cash"):
        GameState.cash += float(effects["cash"])
    if effects.has("public_trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["public_trust"]), 0.0, 100.0)
    if effects.has("safety_debt"):
        GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects["safety_debt"]))
    if effects.has("regulatory_pressure"):
        GameState.regulatory_pressure = clampf(GameState.regulatory_pressure + float(effects["regulatory_pressure"]), 0.0, 100.0)
