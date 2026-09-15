extends Node

## Staff roster operations: candidate generation (fictional names, role,
## skills, salary), hire/fire, and daily payroll. Roster data itself lives
## in GameState.staff (persisted); this autoload is the operations layer.

const CANDIDATE_POOL_SIZE: int = 3
const SKILL_KEYS: Array[String] = ["capability", "engineering", "operations", "safety", "communication"]

# Original, invented name fragments — not references to real people.
const FIRST_NAMES: Array[String] = [
    "Ari", "Bela", "Corin", "Dax", "Emi", "Fen", "Gale", "Hux", "Ines", "Jory",
    "Kes", "Lior", "Mira", "Nyx", "Osk", "Pia", "Quinn", "Ren", "Sable", "Toma",
    "Uma", "Vex", "Wren", "Xela", "Yuri", "Zeph",
]
const LAST_NAMES: Array[String] = [
    "Alder", "Brancato", "Corvin", "Delgao", "Eaves", "Farrow", "Grissel", "Hallow",
    "Ivory", "Jarrah", "Kestrel", "Loomis", "Marrow", "Nightingale", "Oyelaran",
    "Pryce", "Quill", "Rathbone", "Sarto", "Tavish", "Ulric", "Vantree", "Wexley",
    "Yarrow", "Zephyrine",
]

## Not persisted: candidates are an ephemeral offer pool, regenerated as
## hired/refreshed. A reload just gets a fresh pool from the current seed.
var candidates: Array = []

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)
    refresh_candidates()

func _on_day_advanced(_day: int) -> void:
    _deduct_payroll()

func total_payroll() -> float:
    var total: float = 0.0
    for member: Dictionary in GameState.staff:
        total += float(member.get("salary", 0.0))
    return total

func _deduct_payroll() -> void:
    var total: float = total_payroll()
    if total > 0.0:
        GameState.cash -= total
        EventBus.metric_changed.emit("cash", GameState.cash)

func refresh_candidates() -> void:
    candidates.clear()
    for i in CANDIDATE_POOL_SIZE:
        candidates.append(_generate_candidate())

func _generate_candidate() -> Dictionary:
    var role_ids: Array = StaffRoleCatalog.load_all().keys()
    if role_ids.is_empty():
        return {}
    var role_id: String = String(SimClock.pick_from("staff_roles", role_ids))
    var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)

    var skills: Dictionary = {}
    for key: String in SKILL_KEYS:
        skills[key] = SimClock.rng("staff_skills").randi_range(20, 70)
    var primary: String = String(role_def.get("primary_skill", "capability"))
    if skills.has(primary):
        skills[primary] = clampi(int(skills[primary]) + SimClock.rng("staff_skills").randi_range(10, 25), 0, 100)

    var salary_min: float = float(role_def.get("base_salary_min", 600))
    var salary_max: float = float(role_def.get("base_salary_max", 1000))
    var salary: float = snappedf(SimClock.rng("staff_salary").randf_range(salary_min, salary_max), 1.0)

    return {
        "id": "",
        "generated_name": _generate_name(),
        "role": role_id,
        "skills": skills,
        "salary": salary,
        "morale": 70,
        "fatigue": 0,
        "values": {},
        "relationships": [],
        "assigned_task": "",
        "traits": [],
        "hire_date": 0,
    }

func _generate_name() -> String:
    var first: String = String(SimClock.pick_from("staff_first_names", FIRST_NAMES))
    var last: String = String(SimClock.pick_from("staff_last_names", LAST_NAMES))
    return "%s %s" % [first, last]

## Hires candidates[candidate_index], assigning it a stable unique id, and
## tops the pool back up to CANDIDATE_POOL_SIZE.
func hire(candidate_index: int) -> Error:
    if candidate_index < 0 or candidate_index >= candidates.size():
        return ERR_INVALID_PARAMETER
    var candidate: Dictionary = (candidates[candidate_index] as Dictionary).duplicate(true)
    candidate["id"] = "staff_%d" % GameState.next_staff_id
    GameState.next_staff_id += 1
    candidate["hire_date"] = GameState.calendar_day
    GameState.staff.append(candidate)
    candidates.remove_at(candidate_index)
    candidates.append(_generate_candidate())
    EventBus.staff_roster_changed.emit()
    return OK

func fire(staff_id: String) -> Error:
    for i in GameState.staff.size():
        var member: Dictionary = GameState.staff[i]
        if String(member.get("id", "")) == staff_id:
            GameState.staff.remove_at(i)
            EventBus.staff_roster_changed.emit()
            return OK
    return ERR_DOES_NOT_EXIST

func find(staff_id: String) -> Dictionary:
    for member: Dictionary in GameState.staff:
        if String(member.get("id", "")) == staff_id:
            return member
    return {}
