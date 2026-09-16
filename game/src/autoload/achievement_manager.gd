extends Node

## Detects real, tracked-state achievement conditions and unlocks them
## through PlatformService — never touches a platform SDK directly. Six
## of docs/design/ACHIEVEMENTS_AND_META.md's ten draft achievements are
## wired here; the other four ("Known Unknowns", "Read the Memo", "Five
## Nines-ish", "Capacity Planning") need tracking systems this project
## doesn't have yet (an eval-warning ledger, causal incident-to-launch
## linking, and sustained-metric-over-time tracking respectively) — see
## docs/production/IMPLEMENTATION_STATUS.md.

func _ready() -> void:
    EventBus.campaign_act_changed.connect(_on_campaign_act_changed)
    EventBus.staff_roster_changed.connect(_on_staff_roster_changed)
    EventBus.deployment_changed.connect(_on_deployment_changed)
    EventBus.deployment_rolled_back.connect(_on_deployment_rolled_back)
    EventBus.day_advanced.connect(_on_day_advanced)
    EventBus.ending_triggered.connect(_on_ending_triggered)

func _unlock(achievement_id: String) -> void:
    if PlatformService.is_achievement_unlocked(achievement_id):
        return
    PlatformService.unlock_achievement(achievement_id)
    EventBus.achievement_unlocked.emit(achievement_id)

func _on_campaign_act_changed(act_number: int) -> void:
    if act_number >= 5:
        _unlock("alignment_pending")

func _on_staff_roster_changed() -> void:
    if GameState.staff.size() >= 50:
        _unlock("everybody_gets_a_dashboard")

func _on_deployment_changed(deployment_id: String) -> void:
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        if String(deployment.get("id", "")) == deployment_id and String(deployment.get("mode_id", "")) == "public":
            _unlock("hello_world")
            return

func _on_deployment_rolled_back(_deployment_id: String, _mode_id: String) -> void:
    _unlock("rollback_friday")

func _on_day_advanced(_day: int) -> void:
    if EconomyManager.runway_days() < 7.0 and GameState.bankruptcy_day == -1:
        _unlock("runway_is_a_number")

func _on_ending_triggered(_ending_id: String) -> void:
    var shares: Dictionary = RivalManager.market_shares()
    var player_share: float = float(shares.get("player", 0.0))
    if player_share < 0.5 and EconomyManager.daily_net() >= 0.0:
        _unlock("not_a_monopoly")
