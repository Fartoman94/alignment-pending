extends Node

## Staff roster operations: candidate generation (fictional names, role,
## skills, salary), hire/fire, and daily payroll. Roster data itself lives
## in GameState.staff (persisted); this autoload is the operations layer.

const CANDIDATE_POOL_SIZE: int = 3
## hr_partner (finalization pack's "NPCs con función real": "HR ayuda a
## hiring") widens the candidate pool — a dedicated recruiter surfaces more
## offers. Capped so a large HR department can't make the pool unbounded.
const HR_PARTNER_POOL_BONUS_PER_HEAD: int = 1
const HR_PARTNER_POOL_BONUS_MAX: int = 4
const SKILL_KEYS: Array[String] = ["capability", "engineering", "operations", "safety", "communication"]

# P24: staff depth (traits, relationships, promotion, burnout, resignation,
# leadership/department bonuses). Every daily effect below is clamped, so no
# single trait/relationship/leadership bonus can push a stat out of bounds
# or make a system unrecoverable.
const MAX_TRAITS_PER_CANDIDATE: int = 2

## Applied to every member of a department (role) while it has a promoted
## lead, on top of their own skills/traits.
const LEADERSHIP_SKILL_BONUS: int = 8
const PROMOTION_SKILL_THRESHOLD: int = 70
const PROMOTION_COST: float = 2000.0

const FATIGUE_GAIN_PER_DAY_ASSIGNED: float = 8.0
const FATIGUE_RECOVERY_PER_DAY_IDLE: float = 12.0
const HIGH_FATIGUE_THRESHOLD: float = 70.0
const LOW_FATIGUE_THRESHOLD: float = 30.0
const MORALE_DECAY_HIGH_FATIGUE: float = 4.0
const MORALE_RECOVERY_LOW_FATIGUE: float = 3.0

## Coworkers in the same department drift toward liking/disliking each
## other a little every day; the affinity swing itself is small and capped,
## and its contribution to morale is capped separately below.
const RELATIONSHIP_AFFINITY_MIN: float = -20.0
const RELATIONSHIP_AFFINITY_MAX: float = 20.0
const RELATIONSHIP_STEP: float = 2.0
const RELATIONSHIP_MORALE_WEIGHT: float = 5.0

const RESIGNATION_MORALE_THRESHOLD: float = 20.0
const RESIGNATION_CHANCE_PER_DAY: float = 0.15

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
    _apply_daily_staff_dynamics()

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

func effective_candidate_pool_size() -> int:
    var hr_partners: int = 0
    for member: Dictionary in GameState.staff:
        if String(member.get("role", "")) == "hr_partner":
            hr_partners += 1
    return CANDIDATE_POOL_SIZE + mini(hr_partners * HR_PARTNER_POOL_BONUS_PER_HEAD, HR_PARTNER_POOL_BONUS_MAX)

func refresh_candidates() -> void:
    candidates.clear()
    for i in effective_candidate_pool_size():
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

    # The occupied district's talent score (finalization pack's real-estate
    # pass: "la localización debe influir en talento") nudges every rolled
    # skill uniformly — a deterministic function of already-tracked state,
    # not a new RNG draw, so it doesn't disturb SimClock's seeded streams.
    var district_talent: float = float(RealEstateManager.current_district_def().get("talent", 50.0))
    var talent_bonus: int = int((district_talent - 50.0) / 10.0)
    if talent_bonus != 0:
        for key: String in SKILL_KEYS:
            skills[key] = clampi(int(skills[key]) + talent_bonus, 0, 100)

    # The world's talent_market cycle (P31) scales the whole range: a hot
    # market makes every fresh candidate pricier, a cold one cheaper.
    var talent_multiplier: float = WorldStateManager.talent_salary_multiplier()
    var salary_min: float = float(role_def.get("base_salary_min", 600)) * talent_multiplier
    var salary_max: float = float(role_def.get("base_salary_max", 1000)) * talent_multiplier
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
        "traits": _generate_traits(),
        "is_lead": false,
        "hire_date": 0,
    }

## 0..MAX_TRAITS_PER_CANDIDATE unique traits, deterministic per seed.
func _generate_traits() -> Array:
    var trait_ids: Array = StaffTraitCatalog.load_all().keys()
    if trait_ids.is_empty():
        return []
    var count: int = SimClock.rng("staff_trait_count").randi_range(0, MAX_TRAITS_PER_CANDIDATE)
    var pool: Array = trait_ids.duplicate()
    var picked: Array = []
    for i in count:
        if pool.is_empty():
            break
        var pick: Variant = SimClock.pick_from("staff_traits", pool)
        picked.append(pick)
        pool.erase(pick)
    return picked

func _generate_name() -> String:
    var first: String = String(SimClock.pick_from("staff_first_names", FIRST_NAMES))
    var last: String = String(SimClock.pick_from("staff_last_names", LAST_NAMES))
    return "%s %s" % [first, last]

## Hires candidates[candidate_index], assigning it a stable unique id, and
## tops the pool back up to effective_candidate_pool_size(). Gated by
## RealEstateManager.effective_employee_cap() — the current building's size
## (finalization pack's real-estate pass: a move "debe impactar... hiring"
## — a bigger office is a precondition for a bigger headcount, not just
## flavor).
func hire(candidate_index: int) -> Error:
    if candidate_index < 0 or candidate_index >= candidates.size():
        return ERR_INVALID_PARAMETER
    if GameState.staff.size() >= RealEstateManager.effective_employee_cap():
        return ERR_UNAVAILABLE
    var candidate: Dictionary = (candidates[candidate_index] as Dictionary).duplicate(true)
    candidate["id"] = "staff_%d" % GameState.next_staff_id
    GameState.next_staff_id += 1
    candidate["hire_date"] = GameState.calendar_day
    GameState.staff.append(candidate)
    candidates.remove_at(candidate_index)
    # Tops up to effective_candidate_pool_size() rather than a flat +1, so
    # hiring an hr_partner grows the pool on the very next hire instead of
    # only at the next full refresh_candidates() (game start).
    while candidates.size() < effective_candidate_pool_size():
        candidates.append(_generate_candidate())
    EventBus.staff_roster_changed.emit()
    AudioManager.play_sfx("staff_hired")
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

## Base skill + this member's trait deltas + a department leadership bonus
## (if their role currently has a promoted lead), clamped to [0, 100] so no
## combination of traits/leadership can push a skill out of range.
func effective_skill(staff_id: String, skill_key: String) -> int:
    var member: Dictionary = find(staff_id)
    if member.is_empty():
        return 0
    var skills: Dictionary = member.get("skills", {})
    var value: float = float(skills.get(skill_key, 0))
    for trait_id: Variant in member.get("traits", []):
        var trait_def: Dictionary = StaffTraitCatalog.get_def(String(trait_id))
        var deltas: Dictionary = trait_def.get("skill_deltas", {})
        value += float(deltas.get(skill_key, 0))
    var role_id: String = String(member.get("role", ""))
    var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)
    if skill_key == String(role_def.get("primary_skill", "")) and _has_lead(role_id):
        value += float(LEADERSHIP_SKILL_BONUS)
    return clampi(int(round(value)), 0, 100)

func _has_lead(role_id: String) -> bool:
    for member: Dictionary in GameState.staff:
        if String(member.get("role", "")) == role_id and bool(member.get("is_lead", false)):
            return true
    return false

## Promotes a staff member to department lead: one lead per role, gated by
## their base primary-skill and a one-time cash cost. The bonus it grants
## (LEADERSHIP_SKILL_BONUS) is small and fixed, so losing the lead (fired or
## resigned) just removes the bonus rather than breaking anything.
func promote(staff_id: String) -> Error:
    var member: Dictionary = find(staff_id)
    if member.is_empty():
        return ERR_DOES_NOT_EXIST
    if bool(member.get("is_lead", false)):
        return ERR_ALREADY_IN_USE
    var role_id: String = String(member.get("role", ""))
    if _has_lead(role_id):
        return ERR_ALREADY_IN_USE
    var role_def: Dictionary = StaffRoleCatalog.get_def(role_id)
    var primary_skill: String = String(role_def.get("primary_skill", ""))
    var skills: Dictionary = member.get("skills", {})
    if int(skills.get(primary_skill, 0)) < PROMOTION_SKILL_THRESHOLD:
        return ERR_INVALID_PARAMETER
    if GameState.cash < PROMOTION_COST:
        return ERR_INVALID_PARAMETER
    GameState.cash -= PROMOTION_COST
    member["is_lead"] = true
    EventBus.staff_roster_changed.emit()
    return OK

## Daily fatigue/morale/relationship drift and resignation rolls. Every
## delta here is a small, clamped step (see the consts above) — no single
## day's dynamics can swing morale/fatigue/affinity outside their range, and
## resignation never blocks re-hiring since the candidate pool is
## independent of the roster (see refresh_candidates()/hire()).
func _apply_daily_staff_dynamics() -> void:
    if GameState.staff.is_empty():
        return
    _update_fatigue_and_morale()
    _drift_relationships()
    _roll_resignations()

func _update_fatigue_and_morale() -> void:
    # Purchased office upgrades (RealEstateManager, e.g. "Coffee Corner")
    # apply the same small passive morale nudge to everyone, every day —
    # computed once outside the loop since it doesn't vary per member.
    var office_morale_bonus: float = RealEstateManager.passive_morale_bonus_per_day()
    for member: Dictionary in GameState.staff:
        var trait_ids: Array = member.get("traits", [])
        var fatigue_resistance: float = 1.0
        var morale_delta: float = 0.0
        for trait_id: Variant in trait_ids:
            var trait_def: Dictionary = StaffTraitCatalog.get_def(String(trait_id))
            fatigue_resistance *= float(trait_def.get("fatigue_resistance", 1.0))
            morale_delta += float(trait_def.get("morale_delta", 0.0))

        var fatigue: float = float(member.get("fatigue", 0.0))
        var assigned: bool = not String(member.get("assigned_task", "")).is_empty()
        if assigned:
            fatigue += FATIGUE_GAIN_PER_DAY_ASSIGNED * fatigue_resistance
        else:
            fatigue -= FATIGUE_RECOVERY_PER_DAY_IDLE
        fatigue = clampf(fatigue, 0.0, 100.0)
        member["fatigue"] = fatigue

        var morale: float = float(member.get("morale", 0.0))
        if fatigue >= HIGH_FATIGUE_THRESHOLD:
            morale -= MORALE_DECAY_HIGH_FATIGUE
        elif fatigue <= LOW_FATIGUE_THRESHOLD:
            morale += MORALE_RECOVERY_LOW_FATIGUE
        var relationships: Array = member.get("relationships", [])
        var affinity_sum: float = 0.0
        for rel: Variant in relationships:
            affinity_sum += float((rel as Dictionary).get("affinity", 0.0))
        var avg_affinity: float = affinity_sum / float(relationships.size()) if not relationships.is_empty() else 0.0
        morale += clampf(avg_affinity / RELATIONSHIP_AFFINITY_MAX, -1.0, 1.0) * RELATIONSHIP_MORALE_WEIGHT
        morale += office_morale_bonus
        member["morale"] = clampf(morale, 0.0, 100.0)

## Coworkers sharing a department slowly drift toward liking each other a
## little more (small positive step, symmetric, clamped).
func _drift_relationships() -> void:
    var by_role: Dictionary = {}
    for member: Dictionary in GameState.staff:
        var role_id: String = String(member.get("role", ""))
        if not by_role.has(role_id):
            by_role[role_id] = []
        (by_role[role_id] as Array).append(member)

    for role_id: Variant in by_role:
        var members: Array = by_role[role_id]
        if members.size() < 2:
            continue
        for i in members.size():
            for j in range(i + 1, members.size()):
                _nudge_relationship(members[i], members[j])
                _nudge_relationship(members[j], members[i])

func _nudge_relationship(member: Dictionary, coworker: Dictionary) -> void:
    var coworker_id: String = String(coworker.get("id", ""))
    var relationships: Array = member.get("relationships", [])
    for rel: Variant in relationships:
        var entry: Dictionary = rel
        if String(entry.get("with", "")) == coworker_id:
            entry["affinity"] = clampf(float(entry.get("affinity", 0.0)) + RELATIONSHIP_STEP, RELATIONSHIP_AFFINITY_MIN, RELATIONSHIP_AFFINITY_MAX)
            return
    relationships.append({"with": coworker_id, "affinity": RELATIONSHIP_STEP})
    member["relationships"] = relationships

## Staff with morale below RESIGNATION_MORALE_THRESHOLD have a per-day
## chance to resign. Resigning is identical to being fired (roster removal +
## staff_roster_changed, which TaskManager already uses to free any
## in-progress work order/building reservation) so it can never leave a
## dangling assignment — and the candidate pool always has offers ready, so
## there's always a way to hire again.
func _roll_resignations() -> void:
    var resigning_ids: Array = []
    for member: Dictionary in GameState.staff:
        if float(member.get("morale", 0.0)) < RESIGNATION_MORALE_THRESHOLD:
            if SimClock.rng("staff_resignation").randf() < RESIGNATION_CHANCE_PER_DAY:
                resigning_ids.append(String(member.get("id", "")))
    for staff_id: String in resigning_ids:
        var member: Dictionary = find(staff_id)
        var staff_name: String = String(member.get("generated_name", "A team member"))
        fire(staff_id)
        EventBus.staff_resigned.emit(staff_id, staff_name)
