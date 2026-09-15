extends Node

## Automation and workforce (P29): ties AgentPermissionManager's granted
## autonomy permissions to staffing needs, morale, and org structure. How
## much that pressure actually costs or saves the company is entirely a
## function of the player's chosen WorkforcePolicyCatalog policy — no
## policy is a forced "correct" answer (DataValidator rejects a policy
## dataset where one dominates every other on every axis), so the outcome
## genuinely depends on the choice made, not a scripted conclusion.

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

## Total autonomy permissions granted across every deployment — how much
## of the company's work is currently automated. A pure function of
## already-tracked state (AgentPermissionManager), same discipline as
## BoardManager.valuation().
func automation_pressure() -> float:
    var total: int = 0
    for d: Variant in GameState.deployments:
        total += (AgentPermissionManager.granted_permissions(String((d as Dictionary).get("id", ""))) as Array).size()
    return float(total)

func active_policy() -> Dictionary:
    return WorkforcePolicyCatalog.get_def(GameState.workforce_policy)

func set_policy(policy_id: String) -> Error:
    if WorkforcePolicyCatalog.get_def(policy_id).is_empty():
        return ERR_INVALID_PARAMETER
    GameState.workforce_policy = policy_id
    EventBus.workforce_policy_changed.emit(policy_id)
    return OK

## Today's effects, unsummed, purely for display/testing — actual
## application happens in _on_day_advanced().
func daily_effects() -> Dictionary:
    var policy: Dictionary = active_policy()
    var pressure: float = automation_pressure()
    return {
        "pressure": pressure,
        "cash": float(policy.get("cash_per_pressure", 0.0)) * pressure,
        "morale": float(policy.get("morale_per_pressure", 0.0)) * pressure,
        "trust": float(policy.get("trust_per_pressure", 0.0)) * pressure,
        "safety_debt": float(policy.get("safety_debt_per_pressure", 0.0)) * pressure,
    }

func _on_day_advanced(_day: int) -> void:
    var effects: Dictionary = daily_effects()
    if is_equal_approx(float(effects.get("pressure", 0.0)), 0.0):
        return
    GameState.cash += float(effects.get("cash", 0.0))
    GameState.public_trust = clampf(GameState.public_trust + float(effects.get("trust", 0.0)), 0.0, 100.0)
    GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects.get("safety_debt", 0.0)))
    var morale_delta: float = float(effects.get("morale", 0.0))
    if not is_equal_approx(morale_delta, 0.0):
        for member: Variant in GameState.staff:
            var entry: Dictionary = member
            entry["morale"] = clampf(float(entry.get("morale", 0.0)) + morale_delta, 0.0, 100.0)
