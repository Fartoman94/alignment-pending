extends Node

## Fixed-timestep simulation clock (calendar) and named deterministic RNG
## streams. Only advances while `active` (Campaign sets this on enter/exit)
## and not GameState.paused. Fixed logical ticks (not raw frame delta) keep
## calendar progression identical regardless of frame rate.

const REAL_SECONDS_PER_TICK: float = 1.0
const SIM_MINUTES_PER_TICK: int = 5

var active: bool = false

var _accumulator: float = 0.0
var _rng_streams: Dictionary = {}

func _process(delta: float) -> void:
    if not active or GameState.paused:
        return
    _accumulator += delta * GameState.simulation_speed
    while _accumulator >= REAL_SECONDS_PER_TICK:
        _accumulator -= REAL_SECONDS_PER_TICK
        _tick()

func _tick() -> void:
    _advance_minutes(SIM_MINUTES_PER_TICK)
    EventBus.simulation_tick.emit(SIM_MINUTES_PER_TICK)

func _advance_minutes(amount: int) -> void:
    GameState.calendar_minute += amount
    while GameState.calendar_minute >= 60:
        GameState.calendar_minute -= 60
        GameState.calendar_hour += 1
        while GameState.calendar_hour >= 24:
            GameState.calendar_hour -= 24
            GameState.calendar_day += 1
            EventBus.day_advanced.emit(GameState.calendar_day)

func format_calendar() -> String:
    return "DAY %d  %02d:%02d" % [GameState.calendar_day, GameState.calendar_hour, GameState.calendar_minute]

## Clears cached RNG streams (they will lazily re-derive from the current
## GameState.campaign_seed on next use) and the tick accumulator. Call this
## whenever the seed changes, e.g. starting a new campaign.
func reset_rng_streams() -> void:
    _rng_streams.clear()
    _accumulator = 0.0

## Returns the named deterministic RNG stream, lazily seeded from
## (campaign_seed, stream_name) so each stream is independent and
## reproducible for a given seed.
func rng(stream_name: StringName) -> RandomNumberGenerator:
    if not _rng_streams.has(stream_name):
        var generator: RandomNumberGenerator = RandomNumberGenerator.new()
        generator.seed = hash("%d:%s" % [GameState.campaign_seed, stream_name])
        _rng_streams[stream_name] = generator
    return _rng_streams[stream_name]

## Deterministically picks one item from a named stream. The same seed plus
## the same sequence of calls always yields the same sequence of picks.
func pick_from(stream_name: StringName, items: Array) -> Variant:
    if items.is_empty():
        return null
    var index: int = rng(stream_name).randi_range(0, items.size() - 1)
    return items[index]
