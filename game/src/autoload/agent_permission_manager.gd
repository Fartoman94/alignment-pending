extends Node

## Autonomy permissions a deployed model can be granted (P28): coding,
## support, research assistance, tool access, spending authority. Each
## permission is a purely data-driven trade: a daily productivity_effects
## gain applied to cash, and a daily risk_effects cost applied to whichever
## meter that permission actually endangers (safety_debt, public_trust,
## regulatory_pressure, legal_exposure) — see data/agent_permissions.json.
## Nothing here is random; the risk is a guaranteed, visible daily cost,
## not a probability, so "explicit risk surface" is literal.

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func _find_deployment(deployment_id: String) -> Dictionary:
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("id", "")) == deployment_id:
            return entry
    return {}

func granted_permissions(deployment_id: String) -> Array:
    var deployment: Dictionary = _find_deployment(deployment_id)
    return (deployment.get("agent_permissions", []) as Array).duplicate()

func has_permission(deployment_id: String, permission_id: String) -> bool:
    return granted_permissions(deployment_id).has(permission_id)

func grant(deployment_id: String, permission_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    if AgentPermissionCatalog.get_def(permission_id).is_empty():
        return ERR_INVALID_PARAMETER
    var permissions: Array = deployment.get("agent_permissions", [])
    if permissions.has(permission_id):
        return ERR_ALREADY_IN_USE
    permissions.append(permission_id)
    deployment["agent_permissions"] = permissions
    EventBus.agent_permission_changed.emit(deployment_id, permission_id, true)
    return OK

func revoke(deployment_id: String, permission_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    var permissions: Array = deployment.get("agent_permissions", [])
    if not permissions.has(permission_id):
        return ERR_DOES_NOT_EXIST
    permissions.erase(permission_id)
    deployment["agent_permissions"] = permissions
    EventBus.agent_permission_changed.emit(deployment_id, permission_id, false)
    return OK

## Today's productivity/risk breakdown for one deployment — every granted
## permission's effects, unsummed, so the UI (and tests) can show exactly
## where each dollar and each point of risk comes from.
func deployment_permission_ledger(deployment_id: String) -> Dictionary:
    var breakdown: Array = []
    var total_productivity_cash: float = 0.0
    for permission_id: String in granted_permissions(deployment_id):
        var def: Dictionary = AgentPermissionCatalog.get_def(permission_id)
        var productivity: Dictionary = def.get("productivity_effects", {})
        var risk: Dictionary = def.get("risk_effects", {})
        total_productivity_cash += float(productivity.get("cash", 0.0))
        breakdown.append({
            "permission_id": permission_id, "name": def.get("name", permission_id),
            "productivity_effects": productivity, "risk_effects": risk,
        })
    return {"total_productivity_cash": total_productivity_cash, "permissions": breakdown}

func _on_day_advanced(_day: int) -> void:
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        for permission_id: Variant in deployment.get("agent_permissions", []):
            var def: Dictionary = AgentPermissionCatalog.get_def(String(permission_id))
            _apply_effects(def.get("productivity_effects", {}))
            _apply_effects(def.get("risk_effects", {}))

func _apply_effects(effects: Dictionary) -> void:
    if effects.has("cash"):
        GameState.cash += float(effects["cash"])
    if effects.has("public_trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["public_trust"]), 0.0, 100.0)
    if effects.has("safety_debt"):
        GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects["safety_debt"]))
    if effects.has("regulatory_pressure"):
        GameState.regulatory_pressure = clampf(GameState.regulatory_pressure + float(effects["regulatory_pressure"]), 0.0, 100.0)
    if effects.has("legal_exposure"):
        GameState.legal_exposure = clampf(GameState.legal_exposure + float(effects["legal_exposure"]), 0.0, 100.0)
