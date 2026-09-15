extends Node

## Condition/weight/cooldown incident engine. Once per day_advanced, picks
## a weighted-random incident among those whose prerequisites are met and
## cooldown has expired (deterministic per campaign seed via
## SimClock.rng("incidents")), and triggers it. High severity (P0, 0)
## auto-pauses. History records the triggering state snapshot and the
## player's eventual choice, for traceability.

## Data-driven prerequisite vocabulary: min_<metric>/max_<metric> in
## data/events_seed.json compares against these. Keep in sync with
## DataValidator.EVENT_CONDITION_METRICS.
func _metric_value(metric: String) -> float:
    match metric:
        "safety_debt":
            return GameState.safety_debt
        "public_trust":
            return GameState.public_trust
        "cash":
            return GameState.cash
        "deployed_models_count":
            return float(GameState.deployments.size())
        "staff_count":
            return float(GameState.staff.size())
        "models_count":
            return float(GameState.models.size())
        "calendar_day":
            return float(GameState.calendar_day)
        "compute_used_ratio":
            var capacity: float = GameState.effective_compute_capacity()
            return GameState.compute_used / capacity if capacity > 0.0 else 0.0
        "total_user_scale":
            return ReleaseManager.total_user_scale()
        "total_incident_exposure":
            return ReleaseManager.total_incident_exposure()
        "rival_generation":
            return float(RivalManager.rival_generation())
        "rival_pressure":
            return RivalManager.rival_pressure()
        _:
            return 0.0

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func _prerequisites_met(prerequisites: Dictionary) -> bool:
    for key: String in prerequisites:
        var value: float = float(prerequisites[key])
        if key.begins_with("min_"):
            if _metric_value(key.substr(4)) < value:
                return false
        elif key.begins_with("max_"):
            if _metric_value(key.substr(4)) > value:
                return false
    return true

func _is_off_cooldown(incident_id: String) -> bool:
    return GameState.calendar_day >= int(GameState.incident_cooldowns.get(incident_id, 0))

func eligible_incidents() -> Array:
    var out: Array = []
    for incident_id: String in IncidentCatalog.ordered_ids():
        if not _is_off_cooldown(incident_id):
            continue
        var def: Dictionary = IncidentCatalog.get_def(incident_id)
        if _prerequisites_met(def.get("prerequisites", {})):
            out.append(incident_id)
    return out

## Weighted-random pick among eligible incidents, deterministic per seed.
func _on_day_advanced(_day: int) -> void:
    var eligible: Array = eligible_incidents()
    if eligible.is_empty():
        return
    var weights: Array[float] = []
    var total_weight: float = 0.0
    for incident_id: String in eligible:
        var w: float = float(IncidentCatalog.get_def(incident_id).get("weight", 1.0))
        weights.append(w)
        total_weight += w
    if total_weight <= 0.0:
        return
    var roll: float = SimClock.rng("incidents").randf_range(0.0, total_weight)
    var cumulative: float = 0.0
    var chosen_id: String = eligible[0]
    for i in eligible.size():
        cumulative += weights[i]
        if roll <= cumulative:
            chosen_id = eligible[i]
            break
    _trigger(chosen_id)

func _trigger(incident_id: String) -> void:
    var def: Dictionary = IncidentCatalog.get_def(incident_id)
    GameState.incident_cooldowns[incident_id] = GameState.calendar_day + int(def.get("cooldown_days", 30))

    var instance_id: String = "inc_%d" % GameState.next_incident_instance_id
    GameState.next_incident_instance_id += 1
    var severity: int = int(def.get("severity", 2))
    var entry: Dictionary = {
        "id": instance_id,
        "incident_id": incident_id,
        "category": def.get("category", ""),
        "severity": severity,
        "title": def.get("title", ""),
        "body": def.get("body", ""),
        "choices": def.get("choices", []),
        "triggered_day": GameState.calendar_day,
        # A snapshot of the state that caused this, for a traceable history.
        "state_snapshot": {
            "safety_debt": GameState.safety_debt,
            "public_trust": GameState.public_trust,
            "cash": GameState.cash,
        },
    }
    GameState.pending_incidents.append(entry)

    if severity <= 0 and not GameState.paused:
        GameState.paused = true
        EventBus.simulation_pause_changed.emit(true)

    EventBus.incident_raised.emit(incident_id)

func find_pending(pending_id: String) -> Dictionary:
    for p: Variant in GameState.pending_incidents:
        var entry: Dictionary = p
        if String(entry.get("id", "")) == pending_id:
            return entry
    return {}

## Applies the chosen choice's effects, moves the incident from pending to
## history (recording the choice and the effects actually applied).
func resolve(pending_id: String, choice_id: String) -> Error:
    var entry: Dictionary = find_pending(pending_id)
    if entry.is_empty():
        return ERR_DOES_NOT_EXIST
    var chosen_choice: Dictionary = {}
    for c: Variant in (entry.get("choices", []) as Array):
        if String((c as Dictionary).get("id", "")) == choice_id:
            chosen_choice = c
            break
    if chosen_choice.is_empty():
        return ERR_INVALID_PARAMETER

    var effects: Dictionary = chosen_choice.get("effects", {})
    _apply_effects(effects)

    GameState.pending_incidents.erase(entry)
    entry["choice_id"] = choice_id
    entry["resolved_day"] = GameState.calendar_day
    entry["effects_applied"] = effects
    GameState.incident_history.append(entry)
    return OK

func _apply_effects(effects: Dictionary) -> void:
    if effects.has("cash"):
        GameState.cash += float(effects["cash"])
    if effects.has("public_trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["public_trust"]), 0.0, 100.0)
    if effects.has("safety_debt"):
        GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects["safety_debt"]))
