extends Node

## Capability/reliability/safety/cost evaluations with uncertainty ranges.
## A model's true stat values (GameState.models) are never shown directly;
## the player only ever sees visible_range()/latent_risk_range(), which
## narrow as evals_completed increases. Reuses the existing "safety_audit"
## work task (safety_lab + safety skill) for the worker-time cost, and the
## same target_id mechanism P13/P14 established.

const EVAL_TASK_ID: String = "safety_audit"
const EVAL_COST: float = 2000.0
const MAX_EVAL_DEPTH: int = 5

const REGULAR_STATS: Array[String] = [
    "capability", "reliability", "safety_confidence", "cost_efficiency",
    "latency_efficiency", "autonomy", "interpretability",
]
const REGULAR_BASE_SPREAD: float = 25.0
const REGULAR_SPREAD_PER_EVAL: float = 5.0
const REGULAR_MIN_SPREAD: float = 3.0

# latent_risk starts fully hidden and only narrows to a "known-ish" band,
# never to full certainty — it stays partially revealed by design.
const LATENT_RISK_BASE_SPREAD: float = 40.0
const LATENT_RISK_SPREAD_PER_EVAL: float = 8.0
const LATENT_RISK_MIN_SPREAD: float = 10.0

func _ready() -> void:
    EventBus.task_completed.connect(_on_task_completed)

func can_request(model_id: String) -> bool:
    var model: Dictionary = _find_model(model_id)
    if model.is_empty() or int(model.get("evals_completed", 0)) >= MAX_EVAL_DEPTH:
        return false
    return GameState.cash >= EVAL_COST

## Commits cash for one evaluation session. The worker-time still needs a
## staff member assigned to safety_audit targeting model_id (see
## pick_model_for_evaluation_assignment()).
func request_evaluation(model_id: String) -> Error:
    if not can_request(model_id):
        return ERR_INVALID_PARAMETER
    GameState.cash -= EVAL_COST
    GameState.pending_evaluations[model_id] = int(GameState.pending_evaluations.get(model_id, 0)) + 1
    return OK

func pick_model_for_evaluation_assignment() -> String:
    for model_id: String in GameState.pending_evaluations.keys():
        if int(GameState.pending_evaluations[model_id]) > 0:
            return model_id
    return ""

func _find_model(model_id: String) -> Dictionary:
    for m: Variant in GameState.models:
        var entry: Dictionary = m
        if String(entry.get("id", "")) == model_id:
            return entry
    return {}

func _on_task_completed(_staff_id: String, task_id: String, target_id: String) -> void:
    if task_id != EVAL_TASK_ID or target_id.is_empty():
        return
    if int(GameState.pending_evaluations.get(target_id, 0)) <= 0:
        return
    var remaining: int = int(GameState.pending_evaluations[target_id]) - 1
    if remaining <= 0:
        GameState.pending_evaluations.erase(target_id)
    else:
        GameState.pending_evaluations[target_id] = remaining
    var model: Dictionary = _find_model(target_id)
    if model.is_empty():
        return
    model["evals_completed"] = mini(int(model.get("evals_completed", 0)) + 1, MAX_EVAL_DEPTH)

## Visible [min, max] range for a regular stat: narrows with eval depth,
## never claims perfect certainty (see REGULAR_MIN_SPREAD).
func visible_range(model_id: String, stat_key: String) -> Vector2:
    var model: Dictionary = _find_model(model_id)
    if model.is_empty():
        return Vector2.ZERO
    var true_value: float = float(model.get(stat_key, 0.0))
    var spread: float = _spread_for_depth(int(model.get("evals_completed", 0)), REGULAR_BASE_SPREAD, REGULAR_SPREAD_PER_EVAL, REGULAR_MIN_SPREAD)
    return Vector2(clampf(true_value - spread, 0.0, 100.0), clampf(true_value + spread, 0.0, 100.0))

## latent_risk is fully hidden ([0, 100], i.e. "Unknown") at eval depth 0,
## then partially revealed — still a wide band, narrowing with depth.
func latent_risk_range(model_id: String) -> Vector2:
    var model: Dictionary = _find_model(model_id)
    if model.is_empty():
        return Vector2.ZERO
    var depth: int = int(model.get("evals_completed", 0))
    if depth <= 0:
        return Vector2(0.0, 100.0)
    var true_value: float = float(model.get("latent_risk", 0.0))
    var spread: float = _spread_for_depth(depth, LATENT_RISK_BASE_SPREAD, LATENT_RISK_SPREAD_PER_EVAL, LATENT_RISK_MIN_SPREAD)
    return Vector2(clampf(true_value - spread, 0.0, 100.0), clampf(true_value + spread, 0.0, 100.0))

func _spread_for_depth(depth: int, base_spread: float, per_eval: float, min_spread: float) -> float:
    return maxf(min_spread, base_spread - float(depth) * per_eval)
