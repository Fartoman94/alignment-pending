extends Node

## Public trust changes, communication actions, and hype debt. PR can
## communicate but cannot erase evidence: every communication action's
## trust_delta is small and DataValidator-capped
## (COMMUNICATION_MAX_TRUST_DELTA), and no action here ever touches
## GameState.incident_history — the record of what actually happened stays
## exactly as IncidentManager wrote it, forever.

const HYPE_CONVERSION_RATE: float = 0.05

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func can_perform(action_id: String) -> bool:
    var def: Dictionary = CommunicationActionCatalog.get_def(action_id)
    if def.is_empty():
        return false
    if GameState.cash < float(def.get("cost", 0.0)):
        return false
    return GameState.calendar_day >= int(GameState.communication_cooldowns.get(action_id, 0))

func perform(action_id: String) -> Error:
    if not can_perform(action_id):
        return ERR_INVALID_PARAMETER
    var def: Dictionary = CommunicationActionCatalog.get_def(action_id)
    var trust_delta: float = float(def.get("trust_delta", 0.0))
    var hype_delta: float = float(def.get("hype_debt_delta", 0.0))
    GameState.cash -= float(def.get("cost", 0.0))
    GameState.public_trust = clampf(GameState.public_trust + trust_delta, 0.0, 100.0)
    GameState.hype_debt = maxf(0.0, GameState.hype_debt + hype_delta)
    GameState.communication_cooldowns[action_id] = GameState.calendar_day + int(def.get("cooldown_days", 7))
    GameState.communication_history.append({
        "action_id": action_id, "day": GameState.calendar_day,
        "trust_delta": trust_delta, "hype_debt_delta": hype_delta,
    })
    return OK

## If performance never backs up the hype, it converts to trust loss over
## time — you can't just keep marketing forever without consequence.
func _on_day_advanced(_day: int) -> void:
    if GameState.hype_debt <= 0.0:
        return
    var converted: float = GameState.hype_debt * HYPE_CONVERSION_RATE
    GameState.hype_debt = maxf(0.0, GameState.hype_debt - converted)
    GameState.public_trust = clampf(GameState.public_trust - converted, 0.0, 100.0)

## Merges recent incident- and communication-driven trust changes into one
## chronological "why did trust move" list, for HUD tooltips
## (docs/design/UI_UX.md: "Every metric change should have a tooltip
## explaining top causes").
func recent_trust_causes(limit: int = 4) -> Array:
    var causes: Array = []
    for h: Variant in GameState.incident_history:
        var entry: Dictionary = h
        var effects: Dictionary = entry.get("effects_applied", {})
        if effects.has("public_trust"):
            causes.append({
                "label": String(entry.get("title", entry.get("incident_id", "Incident"))),
                "delta": float(effects["public_trust"]),
                "day": int(entry.get("resolved_day", entry.get("triggered_day", 0))),
            })
    for c: Variant in GameState.communication_history:
        var entry: Dictionary = c
        var delta: float = float(entry.get("trust_delta", 0.0))
        if not is_zero_approx(delta):
            var action_def: Dictionary = CommunicationActionCatalog.get_def(String(entry.get("action_id", "")))
            causes.append({
                "label": String(action_def.get("name", entry.get("action_id", "Communication"))),
                "delta": delta,
                "day": int(entry.get("day", 0)),
            })
    causes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) > int(b["day"]))
    if causes.size() > limit:
        causes.resize(limit)
    return causes
