extends Node

const SAVE_VERSION: int = 1

var campaign_seed: int = 8124
var cash: float = 184200.0
var compute_capacity: float = 100.0
var compute_used: float = 32.0
var power_capacity: float = 100.0
var power_used: float = 49.0
var public_trust: float = 43.0
var safety_debt: float = 17.0
var paused: bool = false
var simulation_speed: float = 1.0

func toggle_pause() -> void:
    paused = not paused
    EventBus.simulation_pause_changed.emit(paused)

## Campaign state payload only. The save format version lives one layer up,
## in SaveManager's envelope, so it isn't duplicated here.
func to_dict() -> Dictionary:
    return {
        "campaign_seed": campaign_seed,
        "cash": cash,
        "compute_capacity": compute_capacity,
        "compute_used": compute_used,
        "power_capacity": power_capacity,
        "power_used": power_used,
        "public_trust": public_trust,
        "safety_debt": safety_debt,
        "simulation_speed": simulation_speed,
    }

func from_dict(data: Dictionary) -> void:
    cash = float(data.get("cash", cash))
    campaign_seed = int(data.get("campaign_seed", campaign_seed))
    compute_capacity = float(data.get("compute_capacity", compute_capacity))
    compute_used = float(data.get("compute_used", compute_used))
    power_capacity = float(data.get("power_capacity", power_capacity))
    power_used = float(data.get("power_used", power_used))
    public_trust = float(data.get("public_trust", public_trust))
    safety_debt = float(data.get("safety_debt", safety_debt))
    simulation_speed = float(data.get("simulation_speed", simulation_speed))
