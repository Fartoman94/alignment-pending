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
var calendar_day: int = 1
var calendar_hour: int = 9
var calendar_minute: int = 0
## Each entry: {buildable_id: String, cell_x: int, cell_y: int, rotated: bool}.
## Kept in sync by BuildController on every place/sell.
var buildings: Array = []
## Each entry is a StaffMember dict (see docs/technical/DATA_SCHEMA.md):
## id, generated_name, role, skills, salary, morale, fatigue, values,
## relationships, assigned_task, traits, hire_date. Kept in sync by
## StaffManager on every hire/fire.
var staff: Array = []
var next_staff_id: int = 1

func toggle_pause() -> void:
    paused = not paused
    EventBus.simulation_pause_changed.emit(paused)

## Resets to a fresh campaign: a new random seed, default resources, and
## day-1 calendar. Does not touch player settings (SettingsManager owns
## those separately).
func reset_to_defaults() -> void:
    campaign_seed = randi()
    cash = 184200.0
    compute_capacity = 100.0
    compute_used = 32.0
    power_capacity = 100.0
    power_used = 49.0
    public_trust = 43.0
    safety_debt = 17.0
    paused = false
    simulation_speed = 1.0
    calendar_day = 1
    calendar_hour = 9
    calendar_minute = 0
    buildings = []
    staff = []
    next_staff_id = 1

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
        "calendar_day": calendar_day,
        "calendar_hour": calendar_hour,
        "calendar_minute": calendar_minute,
        "buildings": buildings,
        "staff": staff,
        "next_staff_id": next_staff_id,
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
    calendar_day = int(data.get("calendar_day", calendar_day))
    calendar_hour = int(data.get("calendar_hour", calendar_hour))
    calendar_minute = int(data.get("calendar_minute", calendar_minute))
    var loaded_buildings: Variant = data.get("buildings", [])
    buildings = loaded_buildings if loaded_buildings is Array else []
    var loaded_staff: Variant = data.get("staff", [])
    staff = loaded_staff if loaded_staff is Array else []
    next_staff_id = int(data.get("next_staff_id", next_staff_id))
