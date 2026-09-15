extends Node

## Investors, valuation, funding rounds, and board demands (P25). Funding
## rounds are raised strictly in order (FundingRoundCatalog.ORDER, same
## pattern as DeploymentModeCatalog's Internal -> Beta -> Public) and each
## one trades cash-now for founder control (GameState.board_control_pct)
## and a recurring cash obligation (GameState.investor_obligation_per_day,
## read by EconomyManager.daily_ledger() so it actually shows up in the
## runway forecast). Board pressure builds from control given away and low
## runway; crossing the threshold raises a demand that always resolves into
## a choice (see resolve_demand()) — never an instant ending.

const BOARD_TRACK_PATH: String = "res://data/board_track.json"

const CONTROL_PRESSURE_PER_POINT: float = 0.05
const LOW_RUNWAY_THRESHOLD_DAYS: float = 30.0
const LOW_RUNWAY_PRESSURE_PER_DAY: float = 2.0

const VALUATION_BASE: float = 50000.0
const VALUATION_PER_DAILY_REVENUE: float = 40.0
const VALUATION_PER_MODEL: float = 30000.0
const VALUATION_PER_TRUST_POINT: float = 1000.0
const VALUATION_PENALTY_PER_SAFETY_DEBT: float = 500.0

var _board_config: Dictionary = {}

func _ready() -> void:
    _load_config()
    EventBus.day_advanced.connect(_on_day_advanced)

func _load_config() -> void:
    if not _board_config.is_empty():
        return
    var file: FileAccess = FileAccess.open(BOARD_TRACK_PATH, FileAccess.READ)
    if file == null:
        push_error("BoardManager: could not open %s" % BOARD_TRACK_PATH)
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary:
        _board_config = parsed
    else:
        push_error("BoardManager: %s root must be a JSON object" % BOARD_TRACK_PATH)

func board_name() -> String:
    return String(_board_config.get("name", "The Board"))

## A pure function of existing, already-tracked state — nothing new to
## keep in sync. Never negative.
func valuation() -> float:
    var value: float = VALUATION_BASE
    value += RevenueManager.total_daily_revenue() * VALUATION_PER_DAILY_REVENUE
    value += float(GameState.models.size()) * VALUATION_PER_MODEL
    value += GameState.public_trust * VALUATION_PER_TRUST_POINT
    value -= GameState.safety_debt * VALUATION_PENALTY_PER_SAFETY_DEBT
    return maxf(0.0, value)

## The next round available to raise, or "" once every round has been
## raised.
func next_round_id() -> String:
    return FundingRoundCatalog.round_after(GameState.funding_rounds_raised.size())

func can_accept_funding(round_id: String) -> bool:
    var next_id: String = next_round_id()
    if next_id.is_empty() or round_id != next_id:
        return false
    var round_def: Dictionary = FundingRoundCatalog.get_def(round_id)
    if round_def.is_empty():
        return false
    return valuation() >= float(round_def.get("min_valuation", 0.0))

## Raises the given round: cash now, in exchange for equity (control) and a
## recurring daily obligation. Rounds must be raised in order and gated by
## valuation, same discipline as DeploymentModeCatalog's staged rollout.
func accept_funding(round_id: String) -> Error:
    if not can_accept_funding(round_id):
        return ERR_INVALID_PARAMETER
    var round_def: Dictionary = FundingRoundCatalog.get_def(round_id)
    GameState.cash += float(round_def.get("amount", 0.0))
    GameState.board_control_pct = clampf(GameState.board_control_pct - float(round_def.get("equity_pct", 0.0)), 0.0, 100.0)
    GameState.investor_obligation_per_day += float(round_def.get("obligation_per_day", 0.0))
    GameState.funding_rounds_raised.append(round_id)
    EventBus.funding_round_accepted.emit(round_id)
    return OK

func has_active_demand() -> bool:
    return not GameState.active_board_demand.is_empty()

## The effects a given demand choice ("yield_to_board"/"hold_the_line")
## would apply, without applying them — lets UI/tests preview or verify a
## choice's consequences.
func demand_choice_effects(choice_id: String) -> Dictionary:
    return _board_config.get(choice_id, {})

func _on_day_advanced(_day: int) -> void:
    var control_pressure: float = (100.0 - GameState.board_control_pct) * CONTROL_PRESSURE_PER_POINT
    var runway_pressure: float = LOW_RUNWAY_PRESSURE_PER_DAY if EconomyManager.runway_days() < LOW_RUNWAY_THRESHOLD_DAYS else 0.0
    GameState.board_pressure = clampf(GameState.board_pressure + control_pressure + runway_pressure, 0.0, 100.0)
    _maybe_trigger_demand()

func _maybe_trigger_demand() -> void:
    if has_active_demand():
        return
    var threshold: float = float(_board_config.get("demand_threshold", 60.0))
    if GameState.board_pressure < threshold:
        return
    GameState.active_board_demand = {
        "id": String(_board_config.get("id", "board")),
        "name": board_name(),
        "ask": String(_board_config.get("ask", "")),
        "triggered_day": GameState.calendar_day,
        "deadline_day": GameState.calendar_day + int(_board_config.get("demand_deadline_days", 14)),
    }
    EventBus.board_demand_triggered.emit()

## choice_id is "yield_to_board" or "hold_the_line" — the two data-driven
## consequences a demand resolves into. Always applies bounded effects,
## never an ending: a demand is a decision, not a game-over.
func resolve_demand(choice_id: String) -> Error:
    if not has_active_demand():
        return ERR_DOES_NOT_EXIST
    if choice_id != "yield_to_board" and choice_id != "hold_the_line":
        return ERR_INVALID_PARAMETER
    var effects: Dictionary = _board_config.get(choice_id, {})
    _apply_effects(effects)
    GameState.board_demand_history.append({
        "id": GameState.active_board_demand.get("id", ""),
        "triggered_day": GameState.active_board_demand.get("triggered_day", 0),
        "resolved_day": GameState.calendar_day,
        "choice": choice_id,
        "effects_applied": effects,
    })
    GameState.active_board_demand = {}
    return OK

func _apply_effects(effects: Dictionary) -> void:
    if effects.has("cash"):
        GameState.cash += float(effects["cash"])
    if effects.has("public_trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["public_trust"]), 0.0, 100.0)
    if effects.has("safety_debt"):
        GameState.safety_debt = maxf(0.0, GameState.safety_debt + float(effects["safety_debt"]))
    if effects.has("regulatory_pressure"):
        GameState.regulatory_pressure = clampf(GameState.regulatory_pressure + float(effects["regulatory_pressure"]), 0.0, 100.0)
    if effects.has("board_pressure"):
        GameState.board_pressure = clampf(GameState.board_pressure + float(effects["board_pressure"]), 0.0, 100.0)
