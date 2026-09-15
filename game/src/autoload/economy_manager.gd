extends Node

## Expands the expense ledger beyond payroll (StaffManager) and
## infrastructure upkeep (BuildController) with rent, legal, and support —
## plus a single traceable daily_ledger() that a runway forecast can be
## checked against, and a bankruptcy recovery window instead of an
## instant game-over.

const BASE_RENT: float = 300.0
const LEGAL_COST_PER_MODEL: float = 50.0
const LEGAL_COST_PER_DEPLOYMENT: float = 100.0
const SUPPORT_COST_PER_1K_USERS: float = 20.0
# Anti-snowball (docs/design/CORE_LOOP_AND_BALANCE.md): overhead grows with
# headcount, so scaling up isn't free just because cash allows it.
const LEGAL_COST_PER_STAFF: float = 5.0

const BANKRUPTCY_RECOVERY_DAYS: int = 10

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func rent_cost() -> float:
    return BASE_RENT

func legal_cost() -> float:
    return (
        float(GameState.models.size()) * LEGAL_COST_PER_MODEL
        + float(GameState.deployments.size()) * LEGAL_COST_PER_DEPLOYMENT
        + float(GameState.staff.size()) * LEGAL_COST_PER_STAFF
    )

func support_cost() -> float:
    return (ReleaseManager.total_user_scale() / 1000.0) * SUPPORT_COST_PER_1K_USERS

## Recurring investor return expectations from accepted funding rounds
## (BoardManager.accept_funding()). Read directly off GameState rather than
## through BoardManager, since it's just an accumulated total, not a
## per-day computation.
func investor_obligation_cost() -> float:
    return GameState.investor_obligation_per_day

## Land/power/cooling contract costs for every purchased remote datacenter
## tier (DatacenterManager). Read directly off GameState, same reasoning
## as investor_obligation_cost().
func datacenter_cost() -> float:
    return GameState.datacenter_operating_cost

## The world's energy_price cycle (P31), directly visible in the ledger.
func energy_cost() -> float:
    return WorldStateManager.energy_cost()

## Full traceable daily cash-flow breakdown. Uses the exact same formulas
## the other managers apply on their own day_advanced handlers (StaffManager
## payroll, BuildController infrastructure upkeep already cached in
## GameState.daily_infrastructure_cost, RevenueManager revenue/inference
## cost) plus this manager's own rent/legal/support/investor
## obligations/datacenter costs, so a forecast built from this never
## drifts from what day_advanced will actually deduct.
func daily_ledger() -> Dictionary:
    var payroll: float = StaffManager.total_payroll()
    var infrastructure: float = GameState.daily_infrastructure_cost
    var rent: float = rent_cost()
    var legal: float = legal_cost()
    var support: float = support_cost()
    var investor_obligations: float = investor_obligation_cost()
    var datacenters: float = datacenter_cost()
    var energy: float = energy_cost()
    var revenue: float = RevenueManager.total_daily_revenue()
    var inference_cost: float = RevenueManager.total_daily_cost()
    var total_expenses: float = payroll + infrastructure + rent + legal + support + investor_obligations + datacenters + energy + inference_cost
    return {
        "payroll": payroll,
        "infrastructure": infrastructure,
        "rent": rent,
        "legal": legal,
        "support": support,
        "investor_obligations": investor_obligations,
        "datacenters": datacenters,
        "energy": energy,
        "revenue": revenue,
        "inference_cost": inference_cost,
        "total_expenses": total_expenses,
        "net": revenue - total_expenses,
    }

func daily_net() -> float:
    return float(daily_ledger().get("net", 0.0))

## Linear run-rate projection: cash if today's net cash flow held steady
## for `days_ahead` more days. Matches the real ledger within rounding as
## long as nothing else (staff, buildings, deployments) changes in between
## — the same assumption any "current burn rate" runway forecast makes.
func forecast_cash_at(days_ahead: int) -> float:
    return GameState.cash + daily_net() * float(days_ahead)

## INF when cash flow is non-negative (no runway limit).
func runway_days() -> float:
    var net: float = daily_net()
    if net >= 0.0:
        return INF
    return GameState.cash / -net

func _on_day_advanced(_day: int) -> void:
    GameState.cash -= rent_cost() + legal_cost() + support_cost() + investor_obligation_cost() + datacenter_cost() + energy_cost()
    _check_bankruptcy()

## Going negative doesn't end the campaign immediately — there's a
## recovery window. Only running out of time while still in the red
## triggers the bankruptcy ending.
func _check_bankruptcy() -> void:
    if GameState.cash >= 0.0:
        GameState.bankruptcy_day = -1
        return
    if GameState.bankruptcy_day < 0:
        GameState.bankruptcy_day = GameState.calendar_day
        return
    if GameState.calendar_day - GameState.bankruptcy_day >= BANKRUPTCY_RECOVERY_DAYS:
        EndingManager.trigger_ending("bankruptcy")

func bankruptcy_days_remaining() -> int:
    if GameState.bankruptcy_day < 0:
        return -1
    return maxi(0, BANKRUPTCY_RECOVERY_DAYS - (GameState.calendar_day - GameState.bankruptcy_day))
