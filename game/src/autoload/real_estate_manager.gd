extends Node

## Garage -> corporate building progression (finalization pack's "Garage
## inicial y progresión a oficinas" + "Ciudad, distritos y bienes raíces"
## prompts): which building (BuildingCatalog) the company currently
## occupies, renting/buying a different one, in-place office upgrades to
## the current building, and how the occupied district's stats (talent,
## prestige, regulation) feed back into hiring, trust, and regulatory
## pressure. GameState.current_building_id defaults to "garage_start" —
## the garage is the canonical campaign start, same as
## GameState.reset_to_defaults() leaves it.
##
## A *move* replaces the current building outright (not cumulative, unlike
## DatacenterManager's remote tiers which stack) — you occupy exactly one
## building at a time. Office upgrades are physical renovations to that one
## space, so GameState.office_upgrades_purchased is cleared on every move
## (a new building doesn't inherit the old one's coffee corner) — the
## player re-invests as they grow, which keeps upgrades meaningful instead
## of compounding forever.

## A move always costs some overhead beyond the destination's own
## purchase_cost (movers, downtime, new leases/contracts to set up) — a
## small fraction of the destination's purchase_cost, floored so even a
## free-to-rent move (the garage's own purchase_cost is 0) still has some
## friction.
const RELOCATION_COST_FRACTION: float = 0.05
const RELOCATION_COST_MIN: float = 500.0

## Office upgrade "morale" effect values (data/office_upgrades.json) are
## authored as a rough one-time "how good does this feel" score (5-10), not
## a literal daily percentage-point delta — scaled down to a size
## comparable to StaffManager's other daily morale deltas (its own
## MORALE_DECAY_HIGH_FATIGUE/MORALE_RECOVERY_LOW_FATIGUE are 3-4/day).
const MORALE_UPGRADE_DAILY_SCALE: float = 0.05

## District prestige/regulation (0-100, centered on 50 = "no opinion
## either way") nudge public_trust/regulatory_pressure a little every day —
## a secondary, location-based modifier layered on top of each stat's own
## primary driver (LegalManager/RegulatorManager/BoardManager etc.), never
## the main driver of either. Deliberately small: at the extremes (0 or
## 100) this is only ±0.5 trust or ±1.0 regulatory pressure per day.
const DISTRICT_TRUST_DRIFT_RATE: float = 0.01
const DISTRICT_REGULATION_DRIFT_RATE: float = 0.02

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)
    _recompute_daily_cost()

func current_building_def() -> Dictionary:
    return BuildingCatalog.get_def(GameState.current_building_id)

func current_district_def() -> Dictionary:
    return DistrictCatalog.get_def(String(current_building_def().get("district", "")))

func current_company_tier_def() -> Dictionary:
    return CompanyTierCatalog.get_def(String(current_building_def().get("tier", "")))

## Owned outright — either the building's own mode is "owned" (the garage,
## from day one) or the player exercised the buy option on a "rent_or_buy"
## listing. Owned buildings never charge daily rent.
func is_owned(building_id: String) -> bool:
    if GameState.owned_building_ids.has(building_id):
        return true
    return String(BuildingCatalog.get_def(building_id).get("mode", "")) == "owned"

func daily_rent_cost() -> float:
    if GameState.current_building_id.is_empty() or is_owned(GameState.current_building_id):
        return 0.0
    var def: Dictionary = current_building_def()
    if def.is_empty():
        return 0.0
    var rent_multiplier: float = float(current_district_def().get("rent_multiplier", 1.0))
    return float(def.get("rent_cost_per_day", 0.0)) * rent_multiplier

## The company-size tier's base cap plus every purchased office upgrade's
## employee_cap bonus — always derived, never independently mutated, same
## discipline as DatacenterManager._recompute_bonuses().
func effective_employee_cap() -> int:
    var tier: Dictionary = current_company_tier_def()
    var cap: int = int(tier.get("employee_cap", 4))
    for upgrade_id: Variant in GameState.office_upgrades_purchased:
        var udef: Dictionary = OfficeUpgradeCatalog.get_def(String(upgrade_id))
        cap += int((udef.get("effects", {}) as Dictionary).get("employee_cap", 0))
    return cap

func _relocation_cost(def: Dictionary, buy: bool) -> float:
    var purchase_cost: float = float(def.get("purchase_cost", 0.0))
    var buy_cost: float = purchase_cost if buy else 0.0
    var move_overhead: float = maxf(RELOCATION_COST_MIN, purchase_cost * RELOCATION_COST_FRACTION)
    return buy_cost + move_overhead

func relocation_cost(building_id: String, buy: bool) -> float:
    return _relocation_cost(BuildingCatalog.get_def(building_id), buy)

func can_move_to(building_id: String, buy: bool) -> bool:
    if building_id == GameState.current_building_id:
        return false
    var def: Dictionary = BuildingCatalog.get_def(building_id)
    if def.is_empty():
        return false
    var mode: String = String(def.get("mode", ""))
    if buy and mode == "rent":
        return false  # a rent-only listing has no purchase option
    var tier_def: Dictionary = CompanyTierCatalog.get_def(String(def.get("tier", "")))
    var unlock: Dictionary = tier_def.get("unlock_requirements", {})
    if GameState.cash < float(unlock.get("cash", 0.0)):
        return false
    if GameState.public_trust < float(unlock.get("trust", 0.0)):
        return false
    return GameState.cash >= _relocation_cost(def, buy)

## Moves into `building_id`, deducting the relocation cost (and the full
## purchase_cost too, if buying). Clears office_upgrades_purchased — see
## the class doc comment for why a new space doesn't inherit the old one's
## renovations. Never removes staff or breaks the roster: capacity is
## checked by the hiring UI against effective_employee_cap(), same as
## every other cap in this game (never a hard staff-eviction on downsize).
func move_to(building_id: String, buy: bool) -> Error:
    if not can_move_to(building_id, buy):
        return ERR_INVALID_PARAMETER
    var def: Dictionary = BuildingCatalog.get_def(building_id)
    GameState.cash -= _relocation_cost(def, buy)
    if buy and not GameState.owned_building_ids.has(building_id):
        GameState.owned_building_ids.append(building_id)
    GameState.current_building_id = building_id
    GameState.office_upgrades_purchased = []
    GameState.real_estate_move_history.append({
        "building_id": building_id,
        "day": GameState.calendar_day,
        "bought": buy,
    })
    _recompute_daily_cost()
    EventBus.real_estate_moved.emit(building_id, buy)
    return OK

func can_purchase_upgrade(upgrade_id: String) -> bool:
    if GameState.office_upgrades_purchased.has(upgrade_id):
        return false
    var def: Dictionary = OfficeUpgradeCatalog.get_def(upgrade_id)
    if def.is_empty():
        return false
    return GameState.cash >= float(def.get("cost", 0.0))

## Cost is deducted immediately; a 'trust' effect (if any) is a one-time
## bump applied now (a board room signals credibility the moment it
## exists), while 'morale'/'employee_cap' are ongoing and read live by
## passive_morale_bonus_per_day()/effective_employee_cap() — see those.
func purchase_upgrade(upgrade_id: String) -> Error:
    if not can_purchase_upgrade(upgrade_id):
        return ERR_INVALID_PARAMETER
    var def: Dictionary = OfficeUpgradeCatalog.get_def(upgrade_id)
    GameState.cash -= float(def.get("cost", 0.0))
    GameState.office_upgrades_purchased.append(upgrade_id)
    var effects: Dictionary = def.get("effects", {})
    if effects.has("trust"):
        GameState.public_trust = clampf(GameState.public_trust + float(effects["trust"]), 0.0, 100.0)
    EventBus.office_upgrade_purchased.emit(upgrade_id)
    return OK

## Read by StaffManager._update_fatigue_and_morale() and added to every
## staff member's daily morale delta alongside fatigue/relationship drift.
func passive_morale_bonus_per_day() -> float:
    var total: float = 0.0
    for upgrade_id: Variant in GameState.office_upgrades_purchased:
        var def: Dictionary = OfficeUpgradeCatalog.get_def(String(upgrade_id))
        total += float((def.get("effects", {}) as Dictionary).get("morale", 0.0))
    return total * MORALE_UPGRADE_DAILY_SCALE

## Rent itself is deducted centrally by EconomyManager's ledger (reads
## GameState.daily_real_estate_cost via rent_cost()) — same "recompute the
## cached total here, let EconomyManager do the one actual cash deduction"
## split DatacenterManager already uses for datacenter_operating_cost.
## Deducting it again here would double-charge rent every day.
func _on_day_advanced(_day: int) -> void:
    _recompute_daily_cost()
    _apply_district_daily_drift()

func _recompute_daily_cost() -> void:
    GameState.daily_real_estate_cost = daily_rent_cost()

## Pure function of the current district's prestige — same
## "expose the delta as its own testable function" pattern
## WorldStateManager.public_mood_daily_trust_delta() uses, so a test (or
## another system) can account for this driver without duplicating the
## formula.
func district_daily_trust_delta() -> float:
    var district: Dictionary = current_district_def()
    if district.is_empty():
        return 0.0
    return (float(district.get("prestige", 50.0)) - 50.0) * DISTRICT_TRUST_DRIFT_RATE

func district_daily_regulation_delta() -> float:
    var district: Dictionary = current_district_def()
    if district.is_empty():
        return 0.0
    return (float(district.get("regulation", 50.0)) - 50.0) * DISTRICT_REGULATION_DRIFT_RATE

func _apply_district_daily_drift() -> void:
    GameState.public_trust = clampf(GameState.public_trust + district_daily_trust_delta(), 0.0, 100.0)
    GameState.regulatory_pressure = clampf(GameState.regulatory_pressure + district_daily_regulation_delta(), 0.0, 100.0)
