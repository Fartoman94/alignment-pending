extends Node

## Abstract remote datacenter progression (P30): a management screen of
## purchasable tiers, not a grid to place buildings on. Each tier is a
## single one-time purchase that adds a large compute_capacity_bonus (see
## GameState.effective_compute_capacity()) plus a recurring operating cost
## (land lease/power contract/cooling contract) — so late-game compute
## scales by buying tiers, never by rendering thousands of individual
## racks. Purchased strictly in order, same discipline as
## DeploymentModeCatalog/FundingRoundCatalog.

func _ready() -> void:
    _recompute_bonuses()

func next_tier_id() -> String:
    return DatacenterTierCatalog.tier_after(GameState.datacenter_tiers_purchased.size())

func can_purchase(tier_id: String) -> bool:
    var next_id: String = next_tier_id()
    if next_id.is_empty() or tier_id != next_id:
        return false
    var def: Dictionary = DatacenterTierCatalog.get_def(tier_id)
    if def.is_empty():
        return false
    return GameState.cash >= float(def.get("cost", 0.0))

func purchase(tier_id: String) -> Error:
    if not can_purchase(tier_id):
        return ERR_INVALID_PARAMETER
    var def: Dictionary = DatacenterTierCatalog.get_def(tier_id)
    GameState.cash -= float(def.get("cost", 0.0))
    GameState.datacenter_tiers_purchased.append(tier_id)
    _recompute_bonuses()
    EventBus.datacenter_tier_purchased.emit(tier_id)
    return OK

## Always derived from datacenter_tiers_purchased, never independently
## mutated — same discipline as BuildController.recompute_infrastructure().
func _recompute_bonuses() -> void:
    var compute_bonus: float = 0.0
    var operating_cost: float = 0.0
    for tier_id: Variant in GameState.datacenter_tiers_purchased:
        var def: Dictionary = DatacenterTierCatalog.get_def(String(tier_id))
        compute_bonus += float(def.get("compute_capacity_bonus", 0.0))
        operating_cost += float(def.get("operating_cost_per_day", 0.0))
    GameState.datacenter_compute_bonus = compute_bonus
    GameState.datacenter_operating_cost = operating_cost
