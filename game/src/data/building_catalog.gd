class_name BuildingCatalog
extends RefCounted

## Loads and caches data/buildings.json: id, name, district, mode
## ("owned"/"rent"/"rent_or_buy"), purchase_cost, rent_cost_per_day,
## capacity, rooms, tier (a CompanyTierCatalog id). See DataValidator for
## the schema rules. Real estate listings, not the desk/server_rack grid
## placement system (BuildableCatalog) — this is which office the company
## occupies, not what's placed inside it.

const PATH: String = "res://data/buildings.json"

static var _cache: Dictionary = {}
static var _order: Array[String] = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("BuildingCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("BuildingCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            var id: String = String(record["id"])
            _cache[id] = record
            _order.append(id)
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## Listing order as authored in buildings.json (roughly garage -> HQ), used
## by the Real Estate UI so listings don't jump around every frame.
static func ids_in_order() -> Array[String]:
    load_all()
    return _order.duplicate()

static func clear_cache() -> void:
    _cache.clear()
    _order.clear()
