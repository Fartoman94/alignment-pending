extends Node

## Detects real, tracked-state achievement conditions and unlocks them
## through PlatformService — never touches a platform SDK directly. All
## ten of docs/design/ACHIEVEMENTS_AND_META.md's draft achievements are
## wired here. The last four ("Known Unknowns", "Read the Memo", "Five
## Nines-ish", "Capacity Planning") needed real tracking state this
## project didn't have yet — an eval-warning ledger, a causal eval-
## warning-to-deployment-decision link, and two sustained-over-time
## trackers — added to GameState (pending_safety_warnings,
## eval_warning_release_count, reliability_streak_days,
## capacity_clean_this_act; see game_state.gd's docstrings for each) and
## driven from here. None of the four are simplified proxies: each reads
## the same true/tracked values the rest of the simulation uses.

## "A safety recommendation" (Read the Memo): an evaluation revealing the
## model's latent risk is *at least* this bad even at its optimistic
## (lower) bound — i.e. even the best-case reading says "risky."
const HIGH_RISK_THRESHOLD: float = 50.0
## "High reliability" (Five Nines-ish): a model's true reliability stat.
const HIGH_RELIABILITY_THRESHOLD: float = 90.0
const RELIABILITY_STREAK_DAYS_REQUIRED: int = 30
const EVAL_WARNING_RELEASES_REQUIRED: int = 3

func _ready() -> void:
    EventBus.campaign_act_changed.connect(_on_campaign_act_changed)
    EventBus.staff_roster_changed.connect(_on_staff_roster_changed)
    EventBus.deployment_changed.connect(_on_deployment_changed)
    EventBus.deployment_rolled_back.connect(_on_deployment_rolled_back)
    EventBus.day_advanced.connect(_on_day_advanced)
    EventBus.ending_triggered.connect(_on_ending_triggered)
    EventBus.task_completed.connect(_on_task_completed)

func _unlock(achievement_id: String) -> void:
    if PlatformService.is_achievement_unlocked(achievement_id):
        return
    PlatformService.unlock_achievement(achievement_id)
    EventBus.achievement_unlocked.emit(achievement_id)

func _on_campaign_act_changed(act_number: int) -> void:
    if act_number >= 5:
        _unlock("alignment_pending")
    # The act that just ended (act_number - 1, or act 1 if this is the
    # very first transition into act 2) is now closed off: if compute
    # never saturated at any point during it, that's a full clean act.
    if GameState.capacity_clean_this_act:
        _unlock("capacity_planning")
    GameState.capacity_clean_this_act = true

func _on_staff_roster_changed() -> void:
    if GameState.staff.size() >= 50:
        _unlock("everybody_gets_a_dashboard")

func _on_deployment_changed(deployment_id: String) -> void:
    var deployment: Dictionary = {}
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("id", "")) == deployment_id:
            deployment = entry
            break
    if deployment.is_empty() or String(deployment.get("mode_id", "")) != "public":
        return
    _unlock("hello_world")

    var model_id: String = String(deployment.get("model_id", ""))
    var model: Dictionary = _find_model(model_id)
    if model.is_empty():
        return

    # Known Unknowns: this release reached Public while still short of
    # full evaluation depth — an explicitly unresolved evaluation warning.
    if int(model.get("evals_completed", 0)) < EvaluationManager.MAX_EVAL_DEPTH:
        GameState.eval_warning_release_count += 1
        if GameState.eval_warning_release_count >= EVAL_WARNING_RELEASES_REQUIRED:
            _unlock("known_unknowns")

    # Read the Memo: an earlier evaluation flagged this exact model as
    # high-risk, and the player didn't ship it that same day — a real,
    # observable delay between the safety signal and the launch decision.
    if GameState.pending_safety_warnings.has(model_id):
        var warned_day: int = int(GameState.pending_safety_warnings[model_id])
        if GameState.calendar_day > warned_day:
            _unlock("read_the_memo")
        GameState.pending_safety_warnings.erase(model_id)

func _on_deployment_rolled_back(_deployment_id: String, _mode_id: String) -> void:
    _unlock("rollback_friday")

func _on_task_completed(_staff_id: String, task_id: String, target_id: String) -> void:
    if task_id != EvaluationManager.EVAL_TASK_ID or target_id.is_empty():
        return
    # EvaluationManager listens to this same signal to bump
    # evals_completed; which handler runs first depends on autoload
    # declaration order, which this shouldn't have to know about or rely
    # on. call_deferred runs after every synchronous handler for this
    # signal emission has finished, so the eval is guaranteed complete by
    # the time _check_eval_warning reads it, regardless of that order.
    call_deferred("_check_eval_warning", target_id)

func _check_eval_warning(model_id: String) -> void:
    if EvaluationManager.latent_risk_range(model_id).x >= HIGH_RISK_THRESHOLD:
        GameState.pending_safety_warnings[model_id] = GameState.calendar_day

func _on_day_advanced(_day: int) -> void:
    if EconomyManager.runway_days() < 7.0 and GameState.bankruptcy_day == -1:
        _unlock("runway_is_a_number")

    # Capacity Planning: one saturation moment permanently disqualifies
    # the current act (cleared/re-armed on the next act transition above).
    if GameState.compute_used >= GameState.effective_compute_capacity():
        GameState.capacity_clean_this_act = false

    # Five Nines-ish: every currently-Public deployment's model must clear
    # the reliability bar for the streak to keep counting. No Public
    # deployment at all does not count as "reliable" — nothing is being
    # proven reliable if nothing is live.
    var public_model_ids: Array = []
    for d: Variant in GameState.deployments:
        var deployment: Dictionary = d
        if String(deployment.get("mode_id", "")) == "public":
            public_model_ids.append(String(deployment.get("model_id", "")))
    var all_reliable: bool = not public_model_ids.is_empty()
    for model_id: String in public_model_ids:
        var model: Dictionary = _find_model(model_id)
        if float(model.get("reliability", 0.0)) < HIGH_RELIABILITY_THRESHOLD:
            all_reliable = false
            break
    if all_reliable:
        GameState.reliability_streak_days += 1
        if GameState.reliability_streak_days >= RELIABILITY_STREAK_DAYS_REQUIRED:
            _unlock("five_nines_ish")
    else:
        GameState.reliability_streak_days = 0

func _on_ending_triggered(_ending_id: String) -> void:
    var shares: Dictionary = RivalManager.market_shares()
    var player_share: float = float(shares.get("player", 0.0))
    if player_share < 0.5 and EconomyManager.daily_net() >= 0.0:
        _unlock("not_a_monopoly")

func _find_model(model_id: String) -> Dictionary:
    for m: Variant in GameState.models:
        var entry: Dictionary = m
        if String(entry.get("id", "")) == model_id:
            return entry
    return {}
