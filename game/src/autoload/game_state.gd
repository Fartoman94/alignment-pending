extends Node

const SAVE_VERSION: int = 1

# Office infrastructure baselines (P12): before any server rack is built.
const BASE_COMPUTE_CAPACITY: float = 20.0
const BASE_POWER_CAPACITY: float = 100.0
const BASE_POWER_DRAW: float = 10.0
const BASE_HEAT_CAPACITY: float = 60.0

var campaign_seed: int = 8124
var cash: float = 184200.0
var compute_capacity: float = BASE_COMPUTE_CAPACITY
## Total compute reserved/drawn = training_compute_reserved +
## inference_compute_used. Always derived — see recompute_compute_used().
var compute_used: float = 0.0
## Compute reserved by active training work orders. Kept in sync by
## TaskManager.
var training_compute_reserved: float = 0.0
## Compute drawn by active deployments' inference traffic. Kept in sync by
## ReleaseManager.
var inference_compute_used: float = 0.0
var power_capacity: float = BASE_POWER_CAPACITY
## Sum of BASE_POWER_DRAW + every placed building's power_draw. Kept in
## sync by BuildController.
var power_used: float = BASE_POWER_DRAW
## Sum of every placed building's heat_output. Kept in sync by
## BuildController. Exceeding heat_capacity throttles effective compute
## (see effective_compute_capacity()) instead of corrupting any state.
var heat_capacity: float = BASE_HEAT_CAPACITY
var heat_load: float = 0.0
## Sum of every placed building's operating_cost_per_day, deducted daily
## alongside payroll. Kept in sync by BuildController.
var daily_infrastructure_cost: float = 0.0
var public_trust: float = 43.0
var safety_debt: float = 17.0
var paused: bool = false
var simulation_speed: float = 1.0
var calendar_day: int = 1
var calendar_hour: int = 9
var calendar_minute: int = 0
## Each entry: {buildable_id: String, cell_x: int, cell_y: int, rotated: bool}.
## Kept in sync by BuildController on every place/sell.
var buildings: Array = []
var next_building_id: int = 1
## Each entry is a StaffMember dict (see docs/technical/DATA_SCHEMA.md):
## id, generated_name, role, skills, salary, morale, fatigue, values,
## relationships, assigned_task, traits, hire_date. Kept in sync by
## StaffManager on every hire/fire.
var staff: Array = []
var next_staff_id: int = 1
## Each entry: {id, task_id, staff_id, building_id, progress_minutes,
## started_day}. Kept in sync by TaskManager.
var work_orders: Array = []
var next_work_order_id: int = 1
## Research node ids the player has fully unlocked. Kept in sync by
## ResearchManager.
var research_unlocked: Array = []
## node_id -> accumulated progress_minutes toward that node's
## duration_minutes. Only holds started-but-not-yet-unlocked nodes.
var research_progress: Dictionary = {}
## Cumulative compute bonus from unlocked research (see
## ResearchNodeCatalog "compute_bonus" effects), folded into
## compute_capacity by BuildController._recompute_infrastructure().
var research_compute_bonus: float = 0.0
## Each entry: {id, tier_id, progress_minutes, started_day}. Kept in sync
## by ModelManager.
var model_projects: Array = []
var next_model_project_id: int = 1
## Each entry is a ModelArtifact dict (see docs/technical/DATA_SCHEMA.md):
## id, name, generation, architecture_tier, capability, reliability,
## safety_confidence, cost_efficiency, latency_efficiency, autonomy,
## interpretability, latent_risk, evals_completed, training_cost,
## created_at. Kept in sync by ModelManager.
var models: Array = []
var next_model_id: int = 1
## model_id -> count of paid-but-not-yet-worked evaluation sessions. Kept
## in sync by EvaluationManager.
var pending_evaluations: Dictionary = {}
## Each entry: {id, model_id, mode_id, rollout_stage (0-1), rate_limit
## (0-1), started_day, status: "active"|"rolled_back"}. Kept in sync by
## ReleaseManager.
var deployments: Array = []
var next_deployment_id: int = 1

func toggle_pause() -> void:
    paused = not paused
    EventBus.simulation_pause_changed.emit(paused)

## Heat above capacity thermally throttles usable compute instead of
## letting anything go negative/invalid. Below capacity, full capacity
## is usable.
func effective_compute_capacity() -> float:
    if heat_load <= heat_capacity or heat_load <= 0.0:
        return compute_capacity
    var cooling_efficiency: float = clampf(heat_capacity / heat_load, 0.3, 1.0)
    return compute_capacity * cooling_efficiency

func recompute_compute_used() -> void:
    compute_used = training_compute_reserved + inference_compute_used

## Resets to a fresh campaign: a new random seed, default resources, and
## day-1 calendar. Does not touch player settings (SettingsManager owns
## those separately).
func reset_to_defaults() -> void:
    campaign_seed = randi()
    cash = 184200.0
    compute_capacity = BASE_COMPUTE_CAPACITY
    compute_used = 0.0
    training_compute_reserved = 0.0
    inference_compute_used = 0.0
    power_capacity = BASE_POWER_CAPACITY
    power_used = BASE_POWER_DRAW
    heat_capacity = BASE_HEAT_CAPACITY
    heat_load = 0.0
    daily_infrastructure_cost = 0.0
    public_trust = 43.0
    safety_debt = 17.0
    paused = false
    simulation_speed = 1.0
    calendar_day = 1
    calendar_hour = 9
    calendar_minute = 0
    buildings = []
    next_building_id = 1
    staff = []
    next_staff_id = 1
    work_orders = []
    next_work_order_id = 1
    research_unlocked = []
    research_progress = {}
    research_compute_bonus = 0.0
    model_projects = []
    next_model_project_id = 1
    models = []
    next_model_id = 1
    pending_evaluations = {}
    deployments = []
    next_deployment_id = 1

## Campaign state payload only. The save format version lives one layer up,
## in SaveManager's envelope, so it isn't duplicated here.
func to_dict() -> Dictionary:
    return {
        "campaign_seed": campaign_seed,
        "cash": cash,
        "compute_capacity": compute_capacity,
        "compute_used": compute_used,
        "training_compute_reserved": training_compute_reserved,
        "inference_compute_used": inference_compute_used,
        "power_capacity": power_capacity,
        "power_used": power_used,
        "heat_capacity": heat_capacity,
        "heat_load": heat_load,
        "daily_infrastructure_cost": daily_infrastructure_cost,
        "public_trust": public_trust,
        "safety_debt": safety_debt,
        "simulation_speed": simulation_speed,
        "calendar_day": calendar_day,
        "calendar_hour": calendar_hour,
        "calendar_minute": calendar_minute,
        "buildings": buildings,
        "next_building_id": next_building_id,
        "staff": staff,
        "next_staff_id": next_staff_id,
        "work_orders": work_orders,
        "next_work_order_id": next_work_order_id,
        "research_unlocked": research_unlocked,
        "research_progress": research_progress,
        "research_compute_bonus": research_compute_bonus,
        "model_projects": model_projects,
        "next_model_project_id": next_model_project_id,
        "models": models,
        "next_model_id": next_model_id,
        "pending_evaluations": pending_evaluations,
        "deployments": deployments,
        "next_deployment_id": next_deployment_id,
    }

func from_dict(data: Dictionary) -> void:
    cash = float(data.get("cash", cash))
    campaign_seed = int(data.get("campaign_seed", campaign_seed))
    compute_capacity = float(data.get("compute_capacity", compute_capacity))
    compute_used = float(data.get("compute_used", compute_used))
    training_compute_reserved = float(data.get("training_compute_reserved", training_compute_reserved))
    inference_compute_used = float(data.get("inference_compute_used", inference_compute_used))
    power_capacity = float(data.get("power_capacity", power_capacity))
    power_used = float(data.get("power_used", power_used))
    heat_capacity = float(data.get("heat_capacity", heat_capacity))
    heat_load = float(data.get("heat_load", heat_load))
    daily_infrastructure_cost = float(data.get("daily_infrastructure_cost", daily_infrastructure_cost))
    public_trust = float(data.get("public_trust", public_trust))
    safety_debt = float(data.get("safety_debt", safety_debt))
    simulation_speed = float(data.get("simulation_speed", simulation_speed))
    calendar_day = int(data.get("calendar_day", calendar_day))
    calendar_hour = int(data.get("calendar_hour", calendar_hour))
    calendar_minute = int(data.get("calendar_minute", calendar_minute))
    var loaded_buildings: Variant = data.get("buildings", [])
    buildings = loaded_buildings if loaded_buildings is Array else []
    next_building_id = int(data.get("next_building_id", next_building_id))
    var loaded_staff: Variant = data.get("staff", [])
    staff = loaded_staff if loaded_staff is Array else []
    next_staff_id = int(data.get("next_staff_id", next_staff_id))
    var loaded_work_orders: Variant = data.get("work_orders", [])
    work_orders = loaded_work_orders if loaded_work_orders is Array else []
    next_work_order_id = int(data.get("next_work_order_id", next_work_order_id))
    var loaded_research_unlocked: Variant = data.get("research_unlocked", [])
    research_unlocked = loaded_research_unlocked if loaded_research_unlocked is Array else []
    var loaded_research_progress: Variant = data.get("research_progress", {})
    research_progress = loaded_research_progress if loaded_research_progress is Dictionary else {}
    research_compute_bonus = float(data.get("research_compute_bonus", research_compute_bonus))
    var loaded_model_projects: Variant = data.get("model_projects", [])
    model_projects = loaded_model_projects if loaded_model_projects is Array else []
    next_model_project_id = int(data.get("next_model_project_id", next_model_project_id))
    var loaded_models: Variant = data.get("models", [])
    models = loaded_models if loaded_models is Array else []
    next_model_id = int(data.get("next_model_id", next_model_id))
    var loaded_pending_evals: Variant = data.get("pending_evaluations", {})
    pending_evaluations = loaded_pending_evals if loaded_pending_evals is Dictionary else {}
    var loaded_deployments: Variant = data.get("deployments", [])
    deployments = loaded_deployments if loaded_deployments is Array else []
    next_deployment_id = int(data.get("next_deployment_id", next_deployment_id))
