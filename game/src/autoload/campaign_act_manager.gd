extends Node

## Five-act milestone system (P36, docs/design/WORLD_AND_NARRATIVE.md
## "Narrative acts"). GameState.current_act only ever ratchets forward,
## driven entirely by capability/scale milestones already tracked
## elsewhere in the sim — never a calendar timer, so the campaign
## progresses at whatever pace the player actually plays at.

## Alignment Pending (Act V) triggers once capability clearly outruns
## governance: either a model's capability crosses this bar, or safety
## debt does.
const ACT_5_CAPABILITY_THRESHOLD: float = 85.0
const ACT_5_SAFETY_DEBT_THRESHOLD: float = 60.0

func _ready() -> void:
    EventBus.model_created.connect(func(_id: String) -> void: _check_progression())
    EventBus.deployment_changed.connect(func(_id: String) -> void: _check_progression())
    EventBus.datacenter_tier_purchased.connect(func(_id: String) -> void: _check_progression())
    EventBus.agent_permission_changed.connect(func(_dep: String, _perm: String, _granted: bool) -> void: _check_progression())
    EventBus.day_advanced.connect(func(_day: int) -> void: _check_progression())

func current_act() -> int:
    return GameState.current_act

func act_def(number: int) -> Dictionary:
    return CampaignActCatalog.get_def(number)

## True once the milestone that unlocks act `number` (i.e. the one that
## ends act `number - 1`) has been met.
func milestone_met_for(number: int) -> bool:
    match number:
        2:
            return GameState.next_model_id > 1 and not GameState.deployments.is_empty()
        3:
            return not GameState.datacenter_tiers_purchased.is_empty()
        4:
            for d: Variant in GameState.deployments:
                if not ((d as Dictionary).get("agent_permissions", []) as Array).is_empty():
                    return true
            return false
        5:
            if GameState.safety_debt >= ACT_5_SAFETY_DEBT_THRESHOLD:
                return true
            for m: Variant in GameState.models:
                if float((m as Dictionary).get("capability", 0.0)) >= ACT_5_CAPABILITY_THRESHOLD:
                    return true
            return false
        _:
            return false

## Advances current_act as far as the milestones already met allow, one
## step at a time (never skips an act, never regresses).
func _check_progression() -> void:
    while GameState.current_act < 5 and milestone_met_for(GameState.current_act + 1):
        GameState.current_act += 1
        EventBus.campaign_act_changed.emit(GameState.current_act)
