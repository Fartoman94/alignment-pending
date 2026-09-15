extends Node

## 3-5 abstract rival companies (docs/design/WORLD_AND_NARRATIVE.md "Rival
## generation"): fictional names + randomized doctrines, no real-world
## mapping. Each launches model generations on its own doctrine-paced
## cycle, with a bounded catch-up mechanic so a rival that falls behind the
## pack speeds up rather than getting permanently lapped. Also derives
## market_shares() — a pure, always-sums-to-1.0 split between the player
## and every rival, read by anything that wants a "who's winning" figure.

# "Examples for development only" in WORLD_AND_NARRATIVE.md, but original
# and ready to ship as the placeholder rival identity pool. One rival per
# name (RIVAL_NAMES.size() rivals), so names are always unique.
const RIVAL_NAMES: Array[String] = [
    "Lattice Nine", "Civitas Compute", "Morrow Metric", "Helioform Systems", "Parallax Works",
]
const BASE_LAUNCH_DAYS: int = 20
const MIN_LAUNCH_DAYS: int = 5

## A rival behind the leading generation launches faster, capped so it's
## never more than 2x base pace — bounded impact, same discipline as P24's
## trait/leadership bonuses.
const CATCH_UP_PER_GEN_BEHIND: float = 0.15
const CATCH_UP_FLOOR: float = 0.5

const BASE_RIVAL_MARKET_SCALE: float = 500.0

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)
    if GameState.rivals.is_empty():
        generate_rival()

## Deterministic per campaign_seed via SimClock's "rival_identity" stream.
## Call this whenever the seed changes (a new campaign), not just at boot.
func generate_rival() -> void:
    GameState.rivals = []
    GameState.rival_launch_history = []
    var doctrine_ids: Array = RivalDoctrineCatalog.load_all().keys()
    if doctrine_ids.is_empty():
        return
    for i in RIVAL_NAMES.size():
        var doctrine_id: String = String(SimClock.pick_from("rival_identity", doctrine_ids))
        var rival_id: String = "rival_%d" % (i + 1)
        GameState.rivals.append({
            "id": rival_id, "name": RIVAL_NAMES[i], "doctrine": doctrine_id, "generation": 0,
            "progress_days": 0, "cycle_duration_days": effective_launch_days(doctrine_id, 0),
        })

func find_rival(rival_id: String) -> Dictionary:
    for r: Variant in GameState.rivals:
        var rival: Dictionary = r
        if String(rival.get("id", "")) == rival_id:
            return rival
    return {}

func _base_launch_days(doctrine_id: String) -> int:
    var doctrine: Dictionary = RivalDoctrineCatalog.get_def(doctrine_id)
    var pace: float = float(doctrine.get("research_pace_multiplier", 1.0))
    return maxi(MIN_LAUNCH_DAYS, int(round(float(BASE_LAUNCH_DAYS) / maxf(0.1, pace))))

## The highest generation any rival has reached. Also the metric
## IncidentManager reads as "rival_generation" (how far the competitive
## field has advanced, not any one company).
func leading_generation() -> int:
    var top: int = 0
    for r: Variant in GameState.rivals:
        top = maxi(top, int((r as Dictionary).get("generation", 0)))
    return top

## 1.0 at the front of the pack; drops (bounded to CATCH_UP_FLOOR) the
## further behind the leader a rival's generation is.
func catch_up_multiplier(generation: int) -> float:
    var gap: int = leading_generation() - generation
    if gap <= 0:
        return 1.0
    return maxf(CATCH_UP_FLOOR, 1.0 - float(gap) * CATCH_UP_PER_GEN_BEHIND)

## Doctrine pace, sped up by the catch-up multiplier for a rival that's
## currently behind. Recomputed once per launch (not continuously), same
## discipline the single-rival version used.
func effective_launch_days(doctrine_id: String, generation: int) -> int:
    var base: int = _base_launch_days(doctrine_id)
    return maxi(MIN_LAUNCH_DAYS, int(round(float(base) * catch_up_multiplier(generation))))

## rival_generation() metric alias kept for IncidentManager's condition
## vocabulary (EVENT_CONDITION_METRICS still names it "rival_generation").
func rival_generation() -> int:
    return leading_generation()

## Sum of every rival's individual pressure — more rivals racing, and
## further along, means more aggregate market pressure. Read by
## IncidentManager as the "rival_pressure" condition metric.
func rival_pressure() -> float:
    var total: float = 0.0
    for r: Variant in GameState.rivals:
        total += _single_rival_pressure(r)
    return total

func _single_rival_pressure(r: Variant) -> float:
    var rival: Dictionary = r
    var doctrine: Dictionary = RivalDoctrineCatalog.get_def(String(rival.get("doctrine", "")))
    var pressure_mult: float = float(doctrine.get("market_pressure_multiplier", 1.0))
    return float(rival.get("generation", 0)) * pressure_mult

func launch_progress_fraction(rival_id: String) -> float:
    var rival: Dictionary = find_rival(rival_id)
    if rival.is_empty():
        return 0.0
    var duration: float = float(rival.get("cycle_duration_days", BASE_LAUNCH_DAYS))
    if duration <= 0.0:
        return 0.0
    return clampf(float(rival.get("progress_days", 0)) / duration, 0.0, 1.0)

func _rival_market_scale(r: Variant) -> float:
    var rival: Dictionary = r
    var doctrine: Dictionary = RivalDoctrineCatalog.get_def(String(rival.get("doctrine", "")))
    var pressure_mult: float = float(doctrine.get("market_pressure_multiplier", 1.0))
    return BASE_RIVAL_MARKET_SCALE * pressure_mult * float(1 + int(rival.get("generation", 0)))

## The player's and every rival's share of an abstract market pie, derived
## from each party's current scale — always sums to exactly 1.0 (or a sane
## 100%-to-the-player default if nobody has any scale yet), so nothing
## downstream needs to independently normalize it. Keys: "player" plus each
## rival's id.
func market_shares() -> Dictionary:
    var player_scale: float = ReleaseManager.total_user_scale()
    var rival_scales: Dictionary = {}
    var total: float = player_scale
    for r: Variant in GameState.rivals:
        var rival: Dictionary = r
        var scale: float = _rival_market_scale(rival)
        rival_scales[String(rival.get("id", ""))] = scale
        total += scale

    var shares: Dictionary = {}
    if total <= 0.0:
        shares["player"] = 1.0
        for rival_id: String in rival_scales:
            shares[rival_id] = 0.0
        return shares
    shares["player"] = player_scale / total
    for rival_id: String in rival_scales:
        shares[rival_id] = float(rival_scales[rival_id]) / total
    return shares

func _on_day_advanced(_day: int) -> void:
    if GameState.rivals.is_empty():
        generate_rival()
    var to_launch: Array = []
    for r: Variant in GameState.rivals:
        var rival: Dictionary = r
        rival["progress_days"] = int(rival.get("progress_days", 0)) + 1
        if int(rival["progress_days"]) >= int(rival.get("cycle_duration_days", BASE_LAUNCH_DAYS)):
            to_launch.append(rival)
    for rival: Dictionary in to_launch:
        _launch(rival)

func _launch(rival: Dictionary) -> void:
    var doctrine_id: String = String(rival.get("doctrine", ""))
    var generation: int = int(rival.get("generation", 0)) + 1
    rival["generation"] = generation
    rival["progress_days"] = 0
    rival["cycle_duration_days"] = effective_launch_days(doctrine_id, generation)
    GameState.rival_launch_history.append({
        "rival_id": String(rival.get("id", "")), "generation": generation, "day": GameState.calendar_day, "doctrine": doctrine_id,
    })
    EventBus.rival_launched.emit(String(rival.get("id", "")), generation)
