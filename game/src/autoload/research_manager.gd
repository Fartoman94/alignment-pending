extends Node

## Data-driven research tree: prerequisites, cash cost to start, worker time
## to complete (via TaskManager's "research_sprint" task), and an unlock
## effect applied once. GameState.research_unlocked/research_progress
## persist; ResearchNodeCatalog is the static content definition.

const RESEARCH_TASK_ID: String = "research_sprint"

func _ready() -> void:
    EventBus.task_completed.connect(_on_task_completed)

func is_unlocked(node_id: String) -> bool:
    return GameState.research_unlocked.has(node_id)

## Started (progress recorded) but not yet unlocked.
func is_active(node_id: String) -> bool:
    return GameState.research_progress.has(node_id) and not is_unlocked(node_id)

func prerequisites_met(node_id: String) -> bool:
    var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
    var prereqs: Array = def.get("prerequisites", [])
    for prereq: Variant in prereqs:
        if not is_unlocked(String(prereq)):
            return false
    return true

func can_start(node_id: String) -> bool:
    var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
    if def.is_empty() or is_unlocked(node_id) or is_active(node_id):
        return false
    if not prerequisites_met(node_id):
        return false
    return GameState.cash >= float(def.get("cost", 0.0))

## Commits cash and marks the node active (progress starts at 0). Actual
## progress still requires a staff member assigned to a research_sprint
## task targeting this node.
func start(node_id: String) -> Error:
    if not can_start(node_id):
        return ERR_INVALID_PARAMETER
    var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
    GameState.cash -= float(def.get("cost", 0.0))
    GameState.research_progress[node_id] = 0.0
    return OK

## The active node with the lowest progress fraction, or "" if none are
## active — used by the HUD to auto-target a research_sprint assignment
## without a separate node-picker.
func pick_active_node_for_assignment() -> String:
    var best_id: String = ""
    var best_fraction: float = INF
    for node_id: String in GameState.research_progress.keys():
        if is_unlocked(node_id):
            continue
        var fraction: float = node_progress_fraction(node_id)
        if fraction < best_fraction:
            best_fraction = fraction
            best_id = node_id
    return best_id

func node_progress_fraction(node_id: String) -> float:
    var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
    var duration: float = float(def.get("duration_minutes", 0.0))
    if duration <= 0.0:
        return 0.0
    return clampf(float(GameState.research_progress.get(node_id, 0.0)) / duration, 0.0, 1.0)

func _on_task_completed(_staff_id: String, task_id: String, target_id: String) -> void:
    if task_id != RESEARCH_TASK_ID or target_id.is_empty():
        return
    if not GameState.research_progress.has(target_id) or is_unlocked(target_id):
        return
    var task_def: Dictionary = WorkTaskCatalog.get_def(task_id)
    var session_minutes: float = float(task_def.get("duration_minutes", 240.0))
    GameState.research_progress[target_id] = float(GameState.research_progress[target_id]) + session_minutes
    if node_progress_fraction(target_id) >= 1.0:
        _unlock(target_id)

func _unlock(node_id: String) -> void:
    GameState.research_progress.erase(node_id)
    GameState.research_unlocked.append(node_id)
    var def: Dictionary = ResearchNodeCatalog.get_def(node_id)
    var effect: Dictionary = def.get("unlock_effect", {})
    var effect_type: String = String(effect.get("type", ""))
    var amount: float = float(effect.get("amount", 0.0))
    match effect_type:
        "compute_bonus":
            GameState.research_compute_bonus += amount
        "safety_debt_delta":
            GameState.safety_debt = maxf(0.0, GameState.safety_debt + amount)
        "trust_delta":
            GameState.public_trust = clampf(GameState.public_trust + amount, 0.0, 100.0)
        _:
            push_warning("ResearchManager: unknown unlock_effect type '%s' for node '%s'" % [effect_type, node_id])
    EventBus.research_unlocked.emit(node_id)
