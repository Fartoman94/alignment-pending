class_name DatacenterTierCatalog
extends RefCounted

## Loads and caches data/datacenter_tiers.json: id, name, description,
## cost, compute_capacity_bonus, operating_cost_per_day. See DataValidator
## for the schema rules.

const PATH: String = "res://data/datacenter_tiers.json"
## Purchased strictly in order (mirrors DeploymentModeCatalog/
## FundingRoundCatalog's staged-progression pattern).
const ORDER: Array[String] = ["regional_pod", "continental_cluster", "flagship_campus", "orbital_relay"]

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("DatacenterTierCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("DatacenterTierCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## The next tier after purchased_count tiers have already been purchased,
## or "" once every tier in ORDER has been purchased.
static func tier_after(purchased_count: int) -> String:
    if purchased_count < 0 or purchased_count >= ORDER.size():
        return ""
    return ORDER[purchased_count]

static func clear_cache() -> void:
    _cache.clear()
