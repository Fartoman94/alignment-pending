extends Node

## World-state simulation (P31): energy price, chip supply, talent
## market, public mood, and regulation climate each cycle smoothly over
## time (data/world_variables.json — midpoint + amplitude * sin(...)),
## with a per-campaign phase offset rolled once from campaign_seed so
## different campaigns see different-looking cycles (seeded variation).
## Each variable feeds a concrete, visible causal link into an existing
## system — see the *_multiplier()/*_delta() functions below.

## Bounds keep every causal effect small and visible rather than
## game-breaking, same discipline as P24's bounded trait impact.
const ENERGY_COST_BASE: float = 150.0
const COMPUTE_AVAILABILITY_MIN: float = 0.7
const COMPUTE_AVAILABILITY_MAX: float = 1.3
const TALENT_SALARY_MIN: float = 0.7
const TALENT_SALARY_MAX: float = 1.3
const REGULATION_CLIMATE_MIN: float = 0.5
const REGULATION_CLIMATE_MAX: float = 1.5
const MAX_DAILY_MOOD_TRUST_DELTA: float = 0.3

func _ready() -> void:
    if GameState.world_state_phase_offsets.is_empty():
        generate()
    EventBus.day_advanced.connect(_on_day_advanced)

## Deterministic per campaign_seed via SimClock's "world_state_phase"
## stream. Call this whenever the seed changes (a new campaign), not just
## at boot — same pattern as RivalManager.generate_rival().
func generate() -> void:
    var offsets: Dictionary = {}
    for variable_id: String in WorldVariableCatalog.ordered_ids():
        var def: Dictionary = WorldVariableCatalog.get_def(variable_id)
        var period: float = float(def.get("period_days", 30))
        offsets[variable_id] = SimClock.rng("world_state_phase").randf_range(0.0, period)
    GameState.world_state_phase_offsets = offsets

## The variable's current cyclical value, always within [0, 100] by
## construction (DataValidator bounds amplitude <= min(midpoint, 100-midpoint)).
func value(variable_id: String) -> float:
    var def: Dictionary = WorldVariableCatalog.get_def(variable_id)
    if def.is_empty():
        return 50.0
    var midpoint: float = float(def.get("midpoint", 50.0))
    var amplitude: float = float(def.get("amplitude", 0.0))
    var period: float = maxf(1.0, float(def.get("period_days", 30)))
    var offset: float = float(GameState.world_state_phase_offsets.get(variable_id, 0.0))
    var phase: float = TAU * (float(GameState.calendar_day) + offset) / period
    return clampf(midpoint + amplitude * sin(phase), 0.0, 100.0)

## Causal link: energy_price -> EconomyManager's daily energy cost line.
func energy_cost() -> float:
    return ENERGY_COST_BASE * (0.5 + value("energy_price") / 100.0)

## Causal link: chip_supply -> GameState.effective_compute_capacity().
func compute_availability_multiplier() -> float:
    var t: float = value("chip_supply") / 100.0
    return lerpf(COMPUTE_AVAILABILITY_MIN, COMPUTE_AVAILABILITY_MAX, t)

## Causal link: talent_market -> StaffManager's generated candidate salaries.
func talent_salary_multiplier() -> float:
    var t: float = value("talent_market") / 100.0
    return lerpf(TALENT_SALARY_MIN, TALENT_SALARY_MAX, t)

## Causal link: public_mood -> a small daily public_trust drift,
## independent of the player's own actions.
func public_mood_daily_trust_delta() -> float:
    return ((value("public_mood") - 50.0) / 50.0) * MAX_DAILY_MOOD_TRUST_DELTA

## Causal link: regulation_climate -> RegulatorManager's daily pressure
## accrual rate.
func regulation_climate_multiplier() -> float:
    var t: float = value("regulation_climate") / 100.0
    return lerpf(REGULATION_CLIMATE_MIN, REGULATION_CLIMATE_MAX, t)

func _on_day_advanced(_day: int) -> void:
    GameState.world_compute_availability_multiplier = compute_availability_multiplier()
    GameState.public_trust = clampf(GameState.public_trust + public_mood_daily_trust_delta(), 0.0, 100.0)
