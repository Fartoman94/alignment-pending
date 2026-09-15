extends Node

## Internal/Beta/Public deployment modes, staged rollout, rollback, and a
## rate-limit slider. Deployment state affects user scale (rollout_stage x
## rate_limit x mode.base_user_scale), inference compute (folded into
## GameState.compute_used alongside TaskManager's training reservations —
## see GameState.recompute_compute_used()), and incident exposure (a pure
## derived value; the incident engine that will consume it is a later
## system, per CLAUDE.md "don't implement future prompts opportunistically").

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)
    _recompute_inference()

func is_deployed(model_id: String) -> bool:
    return not _find_deployment_for_model(model_id).is_empty()

func can_deploy(model_id: String) -> bool:
    if is_deployed(model_id):
        return false
    var model_exists: bool = false
    for m: Variant in GameState.models:
        if String((m as Dictionary).get("id", "")) == model_id:
            model_exists = true
            break
    return model_exists

## Starts an Internal deployment (staged rollout begins at 0%); use
## promote() to move Internal -> Beta -> Public.
func deploy(model_id: String) -> Error:
    if not can_deploy(model_id):
        return ERR_INVALID_PARAMETER
    var deployment_id: String = "dep_%d" % GameState.next_deployment_id
    GameState.next_deployment_id += 1
    GameState.deployments.append({
        "id": deployment_id, "model_id": model_id, "mode_id": "internal",
        "rollout_stage": 0.0, "rate_limit": 1.0, "price": RevenueManager.DEFAULT_PRICE,
        "started_day": GameState.calendar_day, "agent_permissions": [],
        "plan_id": "pro", "enterprise_contract_signed": false, "capacity_reserved": 0.0,
        "rate_limit_low_days": 0, "churned_fraction": 0.0,
    })
    _recompute_inference()
    EventBus.deployment_changed.emit(deployment_id)
    return OK

## Promotes Internal -> Beta -> Public. Resets rollout_stage to 0 since the
## new mode's user-scale target is larger (a fresh staged ramp-up).
func promote(deployment_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    var next_mode: String = DeploymentModeCatalog.next_mode(String(deployment.get("mode_id", "")))
    if next_mode.is_empty():
        return ERR_UNAVAILABLE
    deployment["mode_id"] = next_mode
    deployment["rollout_stage"] = 0.0
    _recompute_inference()
    EventBus.deployment_changed.emit(deployment_id)
    return OK

## Reverts the deployment to nothing: user scale/exposure/inference draw
## for this model all drop to zero. Cash already spent training/evaluating
## the model is unaffected (a separate, already-sunk cost).
func rollback(deployment_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    GameState.deployments.erase(deployment)
    _recompute_inference()
    EventBus.deployment_changed.emit(deployment_id)
    return OK

func set_rate_limit(deployment_id: String, fraction: float) -> void:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return
    deployment["rate_limit"] = clampf(fraction, 0.0, 1.0)
    _recompute_inference()
    EventBus.deployment_changed.emit(deployment_id)

func current_user_scale(deployment: Dictionary) -> float:
    var mode: Dictionary = DeploymentModeCatalog.get_def(String(deployment.get("mode_id", "")))
    var base: float = float(mode.get("base_user_scale", 0.0))
    return base * float(deployment.get("rollout_stage", 0.0)) * float(deployment.get("rate_limit", 1.0))

func total_user_scale() -> float:
    var total: float = 0.0
    for d: Variant in GameState.deployments:
        total += current_user_scale(d)
    return total

## Sum of each active deployment's (user_scale / 1000) * mode's
## inference_compute_per_1k_users.
func total_inference_compute() -> float:
    var total: float = 0.0
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        var mode: Dictionary = DeploymentModeCatalog.get_def(String(deployment.get("mode_id", "")))
        var rate: float = float(mode.get("inference_compute_per_1k_users", 0.0))
        total += (current_user_scale(deployment) / 1000.0) * rate
    return total

## A pure derived exposure figure: how much surface area the company has
## for an incident to occur through. Not yet consumed by anything (the
## incident engine is a later system) but directly testable now, per this
## prompt's acceptance criteria.
func total_incident_exposure() -> float:
    var total: float = 0.0
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        var mode: Dictionary = DeploymentModeCatalog.get_def(String(deployment.get("mode_id", "")))
        total += current_user_scale(deployment) * float(mode.get("exposure_multiplier", 0.0))
    return total

func _on_day_advanced(_day: int) -> void:
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        var mode: Dictionary = DeploymentModeCatalog.get_def(String(deployment.get("mode_id", "")))
        var rollout_days: float = maxf(1.0, float(mode.get("rollout_days", 1.0)))
        deployment["rollout_stage"] = clampf(float(deployment.get("rollout_stage", 0.0)) + 1.0 / rollout_days, 0.0, 1.0)
    _recompute_inference()

func _recompute_inference() -> void:
    GameState.inference_compute_used = total_inference_compute()
    GameState.recompute_compute_used()

func _find_deployment(deployment_id: String) -> Dictionary:
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("id", "")) == deployment_id:
            return entry
    return {}

func _find_deployment_for_model(model_id: String) -> Dictionary:
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("model_id", "")) == model_id:
            return entry
    return {}
