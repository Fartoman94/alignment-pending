class_name CompanyTierCatalog
extends RefCounted

## Loads and caches data/company_tiers.json: id, display_name, employee_cap,
## unlock_requirements ({cash, trust}), real_estate_class. See DataValidator
## for the schema rules. A tier is derived from BuildingCatalog's "tier"
## field on the currently-occupied building (RealEstateManager), never set
## independently — same "always derived" discipline as
## BuildController.recompute_infrastructure().

const PATH: String = "res://data/company_tiers.json"
## Progression rungs as authored (garage -> hq_building), used to compare
## "is this a step up" when evaluating a move.
const ORDER: Array[String] = ["garage", "garage_plus", "small_office", "medium_office", "premium_office", "hq_building"]

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("CompanyTierCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("CompanyTierCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

static func rank_of(id: String) -> int:
    return ORDER.find(id)

static func clear_cache() -> void:
    _cache.clear()
