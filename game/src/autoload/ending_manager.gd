extends Node

## Vertical-slice mini-campaign (P22): ends at a fixed day with one of 3
## prototype epilogues, deterministically chosen from final state. The
## full branching narrative epilogue system is a later phase-3-content
## prompt — this is deliberately just enough to let a new player finish a
## coherent slice.

const ENDING_DAY_TRIGGER: int = 30

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

func _on_day_advanced(_day: int) -> void:
    if has_ended():
        return
    if GameState.calendar_day >= ENDING_DAY_TRIGGER:
        _trigger_ending()

func _trigger_ending() -> void:
    GameState.ending_id = _determine_ending()
    if not GameState.paused:
        GameState.paused = true
        EventBus.simulation_pause_changed.emit(true)
    EventBus.ending_triggered.emit(GameState.ending_id)

## Deterministic, not random: the same final state always yields the same
## epilogue.
func _determine_ending() -> String:
    if GameState.public_trust >= 55.0 and GameState.safety_debt <= 25.0:
        return "steady_hand"
    elif GameState.cash >= 150000.0 or GameState.models.size() >= 2:
        return "runaway_growth"
    else:
        return "grounded_struggle"
