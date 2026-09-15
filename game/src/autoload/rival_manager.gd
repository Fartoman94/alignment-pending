extends Node

## An abstract rival company (docs/design/WORLD_AND_NARRATIVE.md "Rival
## generation"): a fictional name + randomized doctrine, no real-world
## mapping. It launches model generations on a doctrine-paced cycle and
## exerts deterministic market pressure that other systems (IncidentManager
## prerequisites) can read.

# "Examples for development only" in WORLD_AND_NARRATIVE.md, but original
# and ready to ship as the placeholder rival identity pool.
const RIVAL_NAMES: Array[String] = [
    "Lattice Nine", "Civitas Compute", "Morrow Metric", "Helioform Systems", "Parallax Works",
]
const BASE_LAUNCH_DAYS: int = 20
const MIN_LAUNCH_DAYS: int = 5

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)
    if GameState.rival.is_empty():
        generate_rival()

## Deterministic per campaign_seed via SimClock's "rival_identity" stream.
## Call this whenever the seed changes (a new campaign), not just at boot.
func generate_rival() -> void:
    var name: String = String(SimClock.pick_from("rival_identity", RIVAL_NAMES))
    var doctrine_ids: Array = RivalDoctrineCatalog.load_all().keys()
    var doctrine_id: String = String(SimClock.pick_from("rival_identity", doctrine_ids))
    GameState.rival = {
        "name": name, "doctrine": doctrine_id, "generation": 0,
        "progress_days": 0, "cycle_duration_days": _launch_duration(doctrine_id),
    }
    GameState.rival_launch_history = []

func _launch_duration(doctrine_id: String) -> int:
    var doctrine: Dictionary = RivalDoctrineCatalog.get_def(doctrine_id)
    var pace: float = float(doctrine.get("research_pace_multiplier", 1.0))
    return maxi(MIN_LAUNCH_DAYS, int(round(float(BASE_LAUNCH_DAYS) / maxf(0.1, pace))))

func rival_generation() -> int:
    return int(GameState.rival.get("generation", 0))

## A simple deterministic market-pressure figure: more generations and a
## more aggressive doctrine mean more pressure. Read by IncidentManager as
## the "rival_pressure" condition metric.
func rival_pressure() -> float:
    if GameState.rival.is_empty():
        return 0.0
    var doctrine: Dictionary = RivalDoctrineCatalog.get_def(String(GameState.rival.get("doctrine", "")))
    var pressure_mult: float = float(doctrine.get("market_pressure_multiplier", 1.0))
    return float(rival_generation()) * pressure_mult

func launch_progress_fraction() -> float:
    if GameState.rival.is_empty():
        return 0.0
    var duration: float = float(GameState.rival.get("cycle_duration_days", BASE_LAUNCH_DAYS))
    if duration <= 0.0:
        return 0.0
    return clampf(float(GameState.rival.get("progress_days", 0)) / duration, 0.0, 1.0)

func _on_day_advanced(_day: int) -> void:
    if GameState.rival.is_empty():
        generate_rival()
    GameState.rival["progress_days"] = int(GameState.rival.get("progress_days", 0)) + 1
    if int(GameState.rival["progress_days"]) >= int(GameState.rival.get("cycle_duration_days", BASE_LAUNCH_DAYS)):
        _launch()

func _launch() -> void:
    var doctrine_id: String = String(GameState.rival.get("doctrine", ""))
    var generation: int = int(GameState.rival.get("generation", 0)) + 1
    GameState.rival["generation"] = generation
    GameState.rival["progress_days"] = 0
    GameState.rival["cycle_duration_days"] = _launch_duration(doctrine_id)
    GameState.rival_launch_history.append({
        "generation": generation, "day": GameState.calendar_day, "doctrine": doctrine_id,
    })
    EventBus.rival_launched.emit(generation)
