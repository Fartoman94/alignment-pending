class_name SubscriptionPlanCatalog
extends RefCounted

## Loads and caches data/subscription_plans.json: id, name, description,
## price, quota_users, enterprise_contract_revenue_per_day,
## min_reliability_for_contract. See DataValidator for the schema rules.

const PATH: String = "res://data/subscription_plans.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("SubscriptionPlanCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("SubscriptionPlanCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

static func ordered_ids() -> Array:
    return load_all().keys()

static func clear_cache() -> void:
    _cache.clear()
