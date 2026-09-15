extends Node

## Ending evaluator (P37): once the campaign reaches Act V — Alignment
## Pending (P36's milestone-driven final act, never a fixed day), this
## checks a deterministic, priority-ordered list of tracked-state
## conditions every day and triggers the first one that matches. 9
## GDD-named endings (docs/design/WORLD_AND_NARRATIVE.md /
## docs/design/GDD.md "Victory/end states"): 8 regular plus 1 secret
## ("Simulation Within Simulation", checked first since it's the most
## specific). The last condition checked is unconditionally true, so an
## ending is always eventually reached once Act V begins. Bankruptcy
## (EconomyManager) is a separate, immediate failure state, not gated by
## the act system.

## Every milestone is derived from state that already exists elsewhere
## (an ever-incrementing id counter, or a never-shrinking array) — no new
## tracking infrastructure needed.
const MILESTONE_LABELS: Dictionary = {
    "first_building": "Built your first piece of office equipment",
    "first_hire": "Hired your first team member",
    "first_model": "Trained your first model",
    "first_deployment": "Shipped a deployment",
    "first_incident_resolved": "Weathered your first incident",
}

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func has_ended() -> bool:
    return not GameState.ending_id.is_empty()

func compute_milestones() -> Dictionary:
    return {
        "first_building": GameState.next_building_id > 1,
        "first_hire": GameState.next_staff_id > 1,
        "first_model": not GameState.models.is_empty(),
        "first_deployment": GameState.next_deployment_id > 1,
        "first_incident_resolved": not GameState.incident_history.is_empty(),
    }

## Act V is reached purely through capability/scale milestones
## (CampaignActManager) — never a calendar timer.
func _on_day_advanced(_day: int) -> void:
    if has_ended():
        return
    if GameState.current_act >= 5:
        trigger_ending(_determine_ending())

## Forces a specific ending (e.g. EconomyManager calling
## trigger_ending("bankruptcy") when the recovery window expires) instead
## of the evaluator's own determination. No-op if the campaign already
## ended.
func trigger_ending(ending_id: String) -> void:
    if has_ended():
        return
    GameState.ending_id = ending_id
    GameState.ending_summary = _build_ending_summary()
    if not GameState.paused:
        GameState.paused = true
        EventBus.simulation_pause_changed.emit(true)
    EventBus.ending_triggered.emit(ending_id)

## A frozen snapshot of tracked consequences, filled into the epilogue's
## body template (EpilogueCatalog) — facts, not a computed moral score.
func _build_ending_summary() -> Dictionary:
    var market_share: float = 0.0
    if not GameState.rivals.is_empty():
        market_share = float(RivalManager.market_shares().get("player", 0.0))
    return {
        "final_day": GameState.calendar_day,
        "final_cash": int(round(GameState.cash)),
        "final_trust": int(round(GameState.public_trust)),
        "final_safety_debt": int(round(GameState.safety_debt)),
        "models_trained": GameState.models.size(),
        "deployments_launched": maxi(0, GameState.next_deployment_id - 1),
        "staff_count": GameState.staff.size(),
        "incidents_resolved": GameState.incident_history.size(),
        "market_share_pct": int(round(market_share * 100.0)),
    }

func _max_model_capability() -> float:
    var best: float = 0.0
    for m: Variant in GameState.models:
        best = maxf(best, float((m as Dictionary).get("capability", 0.0)))
    return best

func _public_deployment_count() -> int:
    var count: int = 0
    for d: Variant in GameState.deployments:
        if String((d as Dictionary).get("mode_id", "")) == "public":
            count += 1
    return count

## Every current deployment has been granted every autonomy permission —
## discoverable, not hinted at anywhere in the UI.
func _all_deployments_fully_autonomous() -> bool:
    if GameState.deployments.is_empty():
        return false
    var total_permissions: int = AgentPermissionCatalog.ordered_ids().size()
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        if ((deployment.get("agent_permissions", []) as Array).size()) < total_permissions:
            return false
    return true

## Deterministic, priority-ordered, never random: the same final state
## always yields the same epilogue. Checked most-specific-first; the last
## entry is unconditional, guaranteeing an ending is always reached.
func _determine_ending() -> String:
    if _all_deployments_fully_autonomous():
        return "simulation_within_simulation"
    if GameState.safety_debt <= 5.0 and _max_model_capability() >= 80.0 and GameState.legal_exposure <= 10.0 and GameState.regulatory_pressure <= 30.0:
        return "alignment_achieved"
    if GameState.regulatory_pressure >= 60.0 and GameState.audit_history.size() >= 2 and GameState.cash >= 100000.0:
        return "regulatory_capture"
    if _public_deployment_count() >= 2 and GameState.safety_debt >= 40.0:
        return "open_release_cascade"
    if GameState.public_trust >= 65.0 and GameState.safety_debt <= 20.0 and not GameState.models.is_empty() and GameState.legal_exposure <= 20.0:
        return "responsible_stewardship"
    if GameState.cash >= 400000.0 or float(RivalManager.market_shares().get("player", 0.0)) >= 0.5:
        return "market_monarch"
    if AutomationManager.automation_pressure() >= 5.0 and GameState.workforce_policy != "status_quo" and GameState.cash >= 150000.0:
        return "automation_dividend"
    if GameState.cash >= 500000.0 and GameState.staff.size() <= 3 and GameState.public_trust >= 35.0 and GameState.public_trust <= 65.0:
        return "quiet_acquisition"
    return "the_long_pause"
