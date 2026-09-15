extends Node

## Cohort-based demand across hobbyist/developer/business segments, price
## elasticity, and inference cost — pure aggregate math on segment shares
## and a model's true stats (no per-user Node simulation, per this
## prompt's acceptance criteria). Revenue and cost are both individually
## queryable via compute_breakdown() for traceability, not just a single
## opaque cash delta.

const DEFAULT_PRICE: float = 5.0
const MIN_PRICE: float = 0.0
const BASE_COST_PER_USER: float = 0.5

func _ready() -> void:
    EventBus.day_advanced.connect(_on_day_advanced)

func set_price(deployment_id: String, price: float) -> void:
    for d: Variant in GameState.deployments:
        var entry: Dictionary = d
        if String(entry.get("id", "")) == deployment_id:
            entry["price"] = maxf(MIN_PRICE, price)
            return

func _find_model(model_id: String) -> Dictionary:
    for m: Variant in GameState.models:
        var entry: Dictionary = m
        if String(entry.get("id", "")) == model_id:
            return entry
    return {}

## Segment quality score in [0, 1]: a weighted read of the model's true
## capability/reliability/safety_confidence against what this segment
## cares about (business cares more about reliability+safety, hobbyist
## cares about neither much).
func _segment_quality(model: Dictionary, segment: Dictionary) -> float:
    var cap_w: float = float(segment.get("capability_weight", 0.0))
    var rel_w: float = float(segment.get("reliability_weight", 0.0))
    var safety_w: float = float(segment.get("safety_weight", 0.0))
    var total_w: float = cap_w + rel_w + safety_w
    if total_w <= 0.0:
        return 0.0
    var weighted: float = (
        cap_w * float(model.get("capability", 0.0))
        + rel_w * float(model.get("reliability", 0.0))
        + safety_w * float(model.get("safety_confidence", 0.0))
    ) / total_w
    return clampf(weighted / 100.0, 0.0, 1.0)

## Elasticity curve: demand falls off as price approaches the segment's
## willingness-to-pay ceiling, steeper for more price-sensitive segments.
func _segment_price_factor(price: float, segment: Dictionary) -> float:
    var max_price: float = float(segment.get("max_price", 1.0))
    if max_price <= 0.0:
        return 0.0
    var headroom: float = clampf(1.0 - price / max_price, 0.0, 1.0)
    return pow(headroom, float(segment.get("elasticity", 1.0)))

func _cost_per_user(model: Dictionary) -> float:
    var cost_efficiency: float = float(model.get("cost_efficiency", 50.0))
    return BASE_COST_PER_USER * clampf(1.2 - cost_efficiency / 100.0, 0.4, 1.2)

## Full traceable breakdown for one deployment: per-segment users/revenue,
## plus total revenue, total cost, and net. Returns {} for an unknown or
## modelless deployment.
func compute_breakdown(deployment: Dictionary) -> Dictionary:
    var model: Dictionary = _find_model(String(deployment.get("model_id", "")))
    if model.is_empty():
        return {}
    var deployment_scale: float = ReleaseManager.current_user_scale(deployment)
    var price: float = float(deployment.get("price", DEFAULT_PRICE))
    var cost_per_user: float = _cost_per_user(model)

    var segments: Dictionary = {}
    var total_users: float = 0.0
    var total_revenue: float = 0.0
    for segment_id: String in UserSegmentCatalog.ordered_ids():
        var segment: Dictionary = UserSegmentCatalog.get_def(segment_id)
        var quality: float = _segment_quality(model, segment)
        var price_factor: float = _segment_price_factor(price, segment)
        var users: float = deployment_scale * float(segment.get("share_of_market", 0.0)) * quality * price_factor
        var revenue: float = users * price
        segments[segment_id] = {"users": users, "revenue": revenue}
        total_users += users
        total_revenue += revenue

    var total_cost: float = total_users * cost_per_user
    return {
        "segments": segments,
        "total_users": total_users,
        "total_revenue": total_revenue,
        "total_cost": total_cost,
        "net": total_revenue - total_cost,
    }

func total_daily_net() -> float:
    return total_daily_revenue() - total_daily_cost()

## Split out from total_daily_net() for full ledger traceability (see
## EconomyManager.daily_ledger()).
func total_daily_revenue() -> float:
    var total: float = 0.0
    for d: Variant in GameState.deployments:
        total += float(compute_breakdown(d).get("total_revenue", 0.0))
    return total

func total_daily_cost() -> float:
    var total: float = 0.0
    for d: Variant in GameState.deployments:
        total += float(compute_breakdown(d).get("total_cost", 0.0))
    return total

func _on_day_advanced(_day: int) -> void:
    var total_net: float = 0.0
    for d: Variant in GameState.deployments:
        var breakdown: Dictionary = compute_breakdown(d)
        total_net += float(breakdown.get("net", 0.0))
    if not is_zero_approx(total_net):
        GameState.cash += total_net
        EventBus.metric_changed.emit("cash", GameState.cash)
