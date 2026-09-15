extends Node

## Subscription plans, enterprise contracts, and capacity reservation
## (P32) for deployments, plus the churn mechanic: sustained
## under-throttling (rate_limit below CHURN_RATE_LIMIT_THRESHOLD for
## CHURN_STREAK_DAYS_TRIGGER consecutive days) permanently shrinks a
## deployment's addressable market by a small, bounded amount (acceptance:
## "rate limits can cause churn events"). RevenueManager.compute_breakdown()
## reads plan_id/enterprise_contract_signed/churned_fraction directly off
## the deployment dict; this manager just owns writing to them.

const CHURN_RATE_LIMIT_THRESHOLD: float = 0.3
const CHURN_STREAK_DAYS_TRIGGER: int = 5
const CHURN_INCREMENT: float = 0.1
const CHURN_MAX_FRACTION: float = 0.5

const CAPACITY_RESERVATION_COST_PER_UNIT: float = 200.0
const ENTERPRISE_CONTRACT_SIGNING_COST: float = 10000.0

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func _find_deployment(deployment_id: String) -> Dictionary:
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("id", "")) == deployment_id:
            return entry
    return {}

func _find_model(model_id: String) -> Dictionary:
    for m: Variant in GameState.models:
        var entry: Dictionary = m
        if String(entry.get("id", "")) == model_id:
            return entry
    return {}

func set_plan(deployment_id: String, plan_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    if SubscriptionPlanCatalog.get_def(plan_id).is_empty():
        return ERR_INVALID_PARAMETER
    if String(deployment.get("plan_id", "")) != plan_id:
        deployment["plan_id"] = plan_id
        deployment["enterprise_contract_signed"] = false
    EventBus.deployment_changed.emit(deployment_id)
    return OK

func can_sign_enterprise_contract(deployment_id: String) -> bool:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty() or bool(deployment.get("enterprise_contract_signed", false)):
        return false
    var plan_def: Dictionary = SubscriptionPlanCatalog.get_def(String(deployment.get("plan_id", "")))
    if float(plan_def.get("enterprise_contract_revenue_per_day", 0.0)) <= 0.0:
        return false
    var model: Dictionary = _find_model(String(deployment.get("model_id", "")))
    if float(model.get("reliability", 0.0)) < float(plan_def.get("min_reliability_for_contract", 100.0)):
        return false
    return GameState.cash >= ENTERPRISE_CONTRACT_SIGNING_COST

## A one-time signing cost, then a flat daily revenue bonus (see
## RevenueManager.compute_breakdown()) for as long as the deployment stays
## on a plan that carries one.
func sign_enterprise_contract(deployment_id: String) -> Error:
    if not can_sign_enterprise_contract(deployment_id):
        return ERR_INVALID_PARAMETER
    var deployment: Dictionary = _find_deployment(deployment_id)
    GameState.cash -= ENTERPRISE_CONTRACT_SIGNING_COST
    deployment["enterprise_contract_signed"] = true
    EventBus.deployment_changed.emit(deployment_id)
    return OK

func reservation_cost(amount: float) -> float:
    return maxf(0.0, amount) * CAPACITY_RESERVATION_COST_PER_UNIT

## Reserves `amount` compute units for this deployment permanently (until
## released) — GameState.effective_compute_capacity() headroom for
## everything else (training, other deployments' inference) shrinks by
## the same amount, same accounting as an in-progress training job.
func reserve_capacity(deployment_id: String, amount: float) -> Error:
    if amount <= 0.0:
        return ERR_INVALID_PARAMETER
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    var cost: float = reservation_cost(amount)
    if GameState.cash < cost:
        return ERR_INVALID_PARAMETER
    GameState.cash -= cost
    deployment["capacity_reserved"] = float(deployment.get("capacity_reserved", 0.0)) + amount
    GameState.recompute_compute_used()
    EventBus.deployment_changed.emit(deployment_id)
    return OK

func release_capacity(deployment_id: String) -> Error:
    var deployment: Dictionary = _find_deployment(deployment_id)
    if deployment.is_empty():
        return ERR_DOES_NOT_EXIST
    deployment["capacity_reserved"] = 0.0
    GameState.recompute_compute_used()
    EventBus.deployment_changed.emit(deployment_id)
    return OK

func _on_day_advanced(_day: int) -> void:
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        if String(deployment.get("mode_id", "internal")) == "internal":
            continue  # negligible base_user_scale — no meaningful churn risk yet
        var rate_limit: float = float(deployment.get("rate_limit", 1.0))
        if rate_limit < CHURN_RATE_LIMIT_THRESHOLD:
            deployment["rate_limit_low_days"] = int(deployment.get("rate_limit_low_days", 0)) + 1
        else:
            deployment["rate_limit_low_days"] = 0
        if int(deployment.get("rate_limit_low_days", 0)) >= CHURN_STREAK_DAYS_TRIGGER:
            var churned: float = clampf(float(deployment.get("churned_fraction", 0.0)) + CHURN_INCREMENT, 0.0, CHURN_MAX_FRACTION)
            deployment["churned_fraction"] = churned
            deployment["rate_limit_low_days"] = 0
            EventBus.deployment_churn_event.emit(String(deployment.get("id", "")), churned)
