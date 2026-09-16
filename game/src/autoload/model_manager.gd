extends Node

## Model training pipeline: configure a project (data-driven architecture
## tier), queue it, assign staff to the existing "training_run" work task
## (compute allocation/over-capacity blocking already enforced by
## TaskManager, see P12), accrue worker-time progress, and on completion
## create a ModelArtifact in GameState.models.

const TRAINING_TASK_ID: String = "training_run"

## Landing-page contract ("Manage compute, data, and safety debt at
## once"): data_ops headcount is this project's real "data" role — a
## stronger pipeline team measurably improves a newly finished model's
## capability/reliability, the same bounded "role headcount -> modifier"
## pattern already used for legal_specialist/hr_partner/ceo/cfo.
const DATA_OPS_CAPABILITY_BONUS_PER_HEAD: float = 1.5
const DATA_OPS_BONUS_MAX_HEADS: int = 5

func _ready() -> void:
    EventBus.task_completed.connect(_on_task_completed)

## Visual-target pass ("a model called PotatoLM" — landing page contract):
## a real, weak starting model, present from day one — not a training
## project the player has to finish first, a joke-tier placeholder they
## already shipped before the game begins. Called once by MainMenu._on_
## new_campaign_pressed(), never by GameState.reset_to_defaults() itself
## (which stays a true blank slate — most tests build their own scenario
## on top of it and never call this).
const STARTING_MODEL_TIER_ID: String = "small"
const STARTING_MODEL_STRENGTH_FRACTION: float = 0.4

func seed_starting_model() -> void:
    var tier: Dictionary = ModelTierCatalog.get_def(STARTING_MODEL_TIER_ID)
    if tier.is_empty():
        return
    var model_id: String = "model_%d" % GameState.next_model_id
    GameState.next_model_id += 1
    var rng: RandomNumberGenerator = SimClock.rng("model_stats")
    var capability_base: float = float(tier.get("capability_base", 50.0)) * STARTING_MODEL_STRENGTH_FRACTION + data_ops_capability_bonus()
    var safety_base: float = float(tier.get("safety_base", 50.0))
    var cost_efficiency_base: float = float(tier.get("cost_efficiency_base", 50.0)) * STARTING_MODEL_STRENGTH_FRACTION
    var autonomy_base: float = float(tier.get("autonomy_base", 20.0)) * STARTING_MODEL_STRENGTH_FRACTION
    GameState.models.append({
        "id": model_id,
        "name": "PotatoLM 0.01",
        "generation": 1,
        "architecture_tier": STARTING_MODEL_TIER_ID,
        "capability": clampf(capability_base + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "reliability": clampf(capability_base * 0.85 + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "safety_confidence": clampf(safety_base + rng.randf_range(-10.0, 10.0), 0.0, 100.0),
        "cost_efficiency": clampf(cost_efficiency_base + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "latency_efficiency": clampf(cost_efficiency_base * 0.9 + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "autonomy": clampf(autonomy_base + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "interpretability": clampf(safety_base * 0.75 + rng.randf_range(-8.0, 8.0), 0.0, 100.0),
        "latent_risk": clampf(100.0 - safety_base + rng.randf_range(-10.0, 10.0), 0.0, 100.0),
        "evals_completed": 0,
        "training_cost": 0.0,
        "created_at": GameState.calendar_day,
    })
    EventBus.model_created.emit(model_id)

func can_start(tier_id: String) -> bool:
    var tier: Dictionary = ModelTierCatalog.get_def(tier_id)
    if tier.is_empty():
        return false
    return GameState.cash >= float(tier.get("cost", 0.0))

## Commits cash and queues a new project. Progress still requires a staff
## member assigned to a training_run task targeting this project.
func start_project(tier_id: String) -> Error:
    if not can_start(tier_id):
        return ERR_INVALID_PARAMETER
    var tier: Dictionary = ModelTierCatalog.get_def(tier_id)
    GameState.cash -= float(tier.get("cost", 0.0))
    var project_id: String = "proj_%d" % GameState.next_model_project_id
    GameState.next_model_project_id += 1
    GameState.model_projects.append({
        "id": project_id, "tier_id": tier_id, "progress_minutes": 0.0,
        "started_day": GameState.calendar_day,
    })
    return OK

## Safely cancels a queued/in-progress project: frees any assigned staff
## and removes the project. The tier cost already spent is not refunded
## (a sunk cost, same as other strategy-game cancellations); cash/compute
## never go negative because nothing here can push them below zero.
func cancel_project(project_id: String) -> Error:
    var project: Dictionary = _find_project(project_id)
    if project.is_empty():
        return ERR_DOES_NOT_EXIST
    var order: Dictionary = _find_order_for_project(project_id)
    if not order.is_empty():
        TaskManager.cancel(String(order.get("staff_id", "")))
    GameState.model_projects.erase(project)
    return OK

func pick_active_project_for_assignment() -> String:
    if GameState.model_projects.is_empty():
        return ""
    return String((GameState.model_projects[0] as Dictionary).get("id", ""))

func project_tier_id(project_id: String) -> String:
    return String(_find_project(project_id).get("tier_id", ""))

func model_name(model_id: String) -> String:
    for m: Variant in GameState.models:
        var entry: Dictionary = m
        if String(entry.get("id", "")) == model_id:
            return String(entry.get("name", model_id))
    return model_id

func project_progress_fraction(project_id: String) -> float:
    var project: Dictionary = _find_project(project_id)
    if project.is_empty():
        return 0.0
    var tier: Dictionary = ModelTierCatalog.get_def(String(project.get("tier_id", "")))
    var duration: float = float(tier.get("duration_minutes", 0.0))
    if duration <= 0.0:
        return 0.0
    return clampf(float(project.get("progress_minutes", 0.0)) / duration, 0.0, 1.0)

func _find_project(project_id: String) -> Dictionary:
    for p: Variant in GameState.model_projects:
        var entry: Dictionary = p
        if String(entry.get("id", "")) == project_id:
            return entry
    return {}

func _find_order_for_project(project_id: String) -> Dictionary:
    for o: Variant in GameState.work_orders:
        var entry: Dictionary = o
        if String(entry.get("task_id", "")) == TRAINING_TASK_ID and String(entry.get("target_id", "")) == project_id:
            return entry
    return {}

func _on_task_completed(_staff_id: String, task_id: String, target_id: String) -> void:
    if task_id != TRAINING_TASK_ID or target_id.is_empty():
        return
    var project: Dictionary = _find_project(target_id)
    if project.is_empty():
        return
    var task_def: Dictionary = WorkTaskCatalog.get_def(task_id)
    var session_minutes: float = float(task_def.get("duration_minutes", 360.0))
    project["progress_minutes"] = float(project.get("progress_minutes", 0.0)) + session_minutes
    if project_progress_fraction(target_id) >= 1.0:
        _finish_project(project)

func data_ops_capability_bonus() -> float:
    var head_count: int = 0
    for member: Variant in GameState.staff:
        if String((member as Dictionary).get("role", "")) == "data_ops":
            head_count += 1
    return float(mini(head_count, DATA_OPS_BONUS_MAX_HEADS)) * DATA_OPS_CAPABILITY_BONUS_PER_HEAD

func _finish_project(project: Dictionary) -> void:
    var tier_id: String = String(project.get("tier_id", ""))
    var tier: Dictionary = ModelTierCatalog.get_def(tier_id)
    GameState.model_projects.erase(project)

    var model_id: String = "model_%d" % GameState.next_model_id
    GameState.next_model_id += 1
    var rng: RandomNumberGenerator = SimClock.rng("model_stats")
    var capability_base: float = float(tier.get("capability_base", 50.0)) + data_ops_capability_bonus()
    var safety_base: float = float(tier.get("safety_base", 50.0))
    var cost_efficiency_base: float = float(tier.get("cost_efficiency_base", 50.0))
    var autonomy_base: float = float(tier.get("autonomy_base", 20.0))
    var generation: int = GameState.models.size() + 1

    GameState.models.append({
        "id": model_id,
        "name": "%s Gen %d" % [String(tier.get("name", tier_id)), generation],
        "generation": generation,
        "architecture_tier": tier_id,
        "capability": clampf(capability_base + rng.randf_range(-10.0, 10.0), 0.0, 100.0),
        "reliability": clampf(capability_base * 0.85 + rng.randf_range(-8.0, 8.0), 0.0, 100.0),
        "safety_confidence": clampf(safety_base + rng.randf_range(-10.0, 10.0), 0.0, 100.0),
        "cost_efficiency": clampf(cost_efficiency_base + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "latency_efficiency": clampf(cost_efficiency_base * 0.9 + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "autonomy": clampf(autonomy_base + rng.randf_range(-5.0, 5.0), 0.0, 100.0),
        "interpretability": clampf(safety_base * 0.75 + rng.randf_range(-8.0, 8.0), 0.0, 100.0),
        "latent_risk": clampf(100.0 - safety_base + rng.randf_range(-10.0, 10.0), 0.0, 100.0),
        "evals_completed": 0,
        "training_cost": float(tier.get("cost", 0.0)),
        "created_at": GameState.calendar_day,
    })
    EventBus.model_created.emit(model_id)
