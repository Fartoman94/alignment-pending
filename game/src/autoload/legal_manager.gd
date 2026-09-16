extends Node

## Abstract legal exposure (P27): a 0-100 risk meter driven by player
## actions (deployed scale, safety debt), offset by compliance staffing.
## Crossing a case type's threshold files an abstract case (no real
## plaintiffs — archetypes only, data/legal_case_types.json). An open case
## resolves one of three ways, always through data-driven, bounded
## effects: the player settles or fights it (resolve_case()), a daily
## injunction-probability roll hits first, or it hits its deadline and
## defaults — so a case can never sit open forever.

const SCALE_EXPOSURE_PER_1K_USERS: float = 0.04
const DEBT_EXPOSURE_PER_POINT: float = 0.03
## Compliance staffing (safety_analyst headcount) offsets the day's
## exposure gain, floored at 0 — mitigation can cancel a day's increase
## but never itself drives exposure negative.
const MITIGATION_PER_COMPLIANCE_STAFF: float = 0.5
## legal_specialist (added by the real-estate/company-progression pass,
## finalization pack's "NPCs con función real": "legal baja exposición")
## mitigates the same exposure meter safety_analyst always has, on the same
## per-head rate — a dedicated compliance hire is exactly what this role is
## for.
const COMPLIANCE_ROLE_IDS: Array[String] = ["safety_analyst", "legal_specialist"]

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func has_active_case() -> bool:
    return not GameState.active_legal_case.is_empty()

func compliance_staff_count() -> int:
    var count: int = 0
    for member: Variant in GameState.staff:
        if COMPLIANCE_ROLE_IDS.has(String((member as Dictionary).get("role", ""))):
            count += 1
    return count

func daily_exposure_gain() -> float:
    var scale_exposure: float = (ReleaseManager.total_user_scale() / 1000.0) * SCALE_EXPOSURE_PER_1K_USERS
    var debt_exposure: float = GameState.safety_debt * DEBT_EXPOSURE_PER_POINT
    var mitigation: float = float(compliance_staff_count()) * MITIGATION_PER_COMPLIANCE_STAFF
    return maxf(0.0, scale_exposure + debt_exposure - mitigation)

func _is_on_cooldown(case_type_id: String) -> bool:
    return GameState.calendar_day < int(GameState.legal_case_cooldowns.get(case_type_id, 0))

func eligible_case_types() -> Array:
    var eligible: Array = []
    for id: String in LegalCaseTypeCatalog.load_all():
        var def: Dictionary = LegalCaseTypeCatalog.get_def(id)
        if GameState.legal_exposure >= float(def.get("trigger_min_exposure", 100.0)) and not _is_on_cooldown(id):
            eligible.append(id)
    return eligible

func _on_day_advanced(_day: int) -> void:
    GameState.legal_exposure = clampf(GameState.legal_exposure + daily_exposure_gain(), 0.0, 100.0)
    if has_active_case():
        _advance_active_case()
    else:
        _maybe_file_case()

func _maybe_file_case() -> void:
    var eligible: Array = eligible_case_types()
    if eligible.is_empty():
        return
    var case_type_id: String = String(SimClock.pick_from("legal_case", eligible))
    var def: Dictionary = LegalCaseTypeCatalog.get_def(case_type_id)
    var instance_id: String = "legal_%d" % GameState.next_legal_case_instance_id
    GameState.next_legal_case_instance_id += 1
    GameState.active_legal_case = {
        "case_type_id": case_type_id,
        "instance_id": instance_id,
        "filed_day": GameState.calendar_day,
        "deadline_day": GameState.calendar_day + int(def.get("case_deadline_days", 20)),
    }
    EventBus.legal_case_filed.emit(case_type_id)

## Daily injunction-probability roll, then the deadline default — checked
## in that order so a case is never left open indefinitely.
func _advance_active_case() -> void:
    var case_type_id: String = String(GameState.active_legal_case.get("case_type_id", ""))
    var def: Dictionary = LegalCaseTypeCatalog.get_def(case_type_id)
    var probability: float = float(def.get("injunction_probability_per_day", 0.0))
    if SimClock.rng("legal_injunction").randf() < probability:
        _resolve_active_case("injunction", def.get("injunction", {}))
        return
    if GameState.calendar_day >= int(GameState.active_legal_case.get("deadline_day", 0)):
        _resolve_active_case("deadline_default", def.get("settle", {}))

## choice_id is "settle" or "fight" — the two player-chosen, data-driven
## resolutions. ("injunction"/"deadline_default" are system-resolved; see
## _advance_active_case().)
func resolve_case(choice_id: String) -> Error:
    if not has_active_case():
        return ERR_DOES_NOT_EXIST
    if choice_id != "settle" and choice_id != "fight":
        return ERR_INVALID_PARAMETER
    var case_type_id: String = String(GameState.active_legal_case.get("case_type_id", ""))
    var def: Dictionary = LegalCaseTypeCatalog.get_def(case_type_id)
    _resolve_active_case(choice_id, def.get(choice_id, {}))
    return OK

func _resolve_active_case(outcome: String, effects: Dictionary) -> void:
    var case_type_id: String = String(GameState.active_legal_case.get("case_type_id", ""))
    var def: Dictionary = LegalCaseTypeCatalog.get_def(case_type_id)
    _apply_effects(effects)
    GameState.legal_case_history.append({
        "case_type_id": case_type_id,
        "instance_id": GameState.active_legal_case.get("instance_id", ""),
        "filed_day": GameState.active_legal_case.get("filed_day", 0),
        "resolved_day": GameState.calendar_day,
        "outcome": outcome,
        "effects_applied": effects,
    })
    GameState.legal_case_cooldowns[case_type_id] = GameState.calendar_day + int(def.get("cooldown_days", 15))
    GameState.active_legal_case = {}
    EventBus.legal_case_resolved.emit(case_type_id, outcome)

func _apply_effects(effects: Dictionary) -> void:
    if effects.has("cash"):
        GameState.cash += float(effects["cash"])
    if effects.has("public_trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["public_trust"]), 0.0, 100.0)
    if effects.has("safety_debt"):
        GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects["safety_debt"]))
    if effects.has("legal_exposure"):
        GameState.legal_exposure = clampf(GameState.legal_exposure + float(effects["legal_exposure"]), 0.0, 100.0)
