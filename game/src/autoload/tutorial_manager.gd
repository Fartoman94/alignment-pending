extends Node

## Contextual tutorial (P38): a skippable, ordered sequence of steps
## (data/tutorial_steps.json) guiding a new player through training and
## releasing their first model. Each step's completion is read from
## already-tracked GameState (never new bookkeeping beyond dismissal), so
## it's genuinely contextual — it reacts to what the player has actually
## done, not a scripted click-through.

func is_step_complete(step_id: String) -> bool:
    if GameState.tutorial_completed_steps.has(step_id):
        return true
    var def: Dictionary = TutorialStepCatalog.get_def(step_id)
    var metric: String = String(def.get("completion_metric", "manual"))
    if metric == "manual":
        return false
    return _metric_value(metric)

func _metric_value(metric: String) -> bool:
    match metric:
        "server_rack_built":
            for b: Variant in GameState.buildings:
                if String((b as Dictionary).get("buildable_id", "")) == "server_rack":
                    return true
            return false
        "staff_hired":
            return GameState.next_staff_id > 1
        "model_trained":
            return not GameState.models.is_empty()
        "model_evaluated":
            for m: Variant in GameState.models:
                if int((m as Dictionary).get("evals_completed", 0)) > 0:
                    return true
            return false
        "model_deployed":
            return GameState.next_deployment_id > 1
        _:
            return false

## The first not-yet-complete step in authored order, or {} once every
## step is done (or the whole tutorial was skipped).
func current_step() -> Dictionary:
    if GameState.tutorial_skipped_all:
        return {}
    for step_id: String in TutorialStepCatalog.ordered_ids():
        if not is_step_complete(step_id):
            return TutorialStepCatalog.get_def(step_id)
    return {}

## Dismisses one step — works for a "manual" step's acknowledgement
## button, and doubles as an explicit skip for a metric-based step (every
## step is skippable, not just the optional ones).
func dismiss_step(step_id: String) -> Error:
    if TutorialStepCatalog.get_def(step_id).is_empty():
        return ERR_INVALID_PARAMETER
    if not GameState.tutorial_completed_steps.has(step_id):
        GameState.tutorial_completed_steps.append(step_id)
    return OK

func skip_all() -> void:
    GameState.tutorial_skipped_all = true
