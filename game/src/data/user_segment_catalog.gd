class_name UserSegmentCatalog
extends RefCounted

## Loads and caches data/user_segments.json: id, name, share_of_market,
## max_price, elasticity, capability_weight, reliability_weight,
## safety_weight. See DataValidator for the schema rules.

const PATH: String = "res://data/user_segments.json"

static var _cache: Dictionary = {}
static var _order: Array = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("UserSegmentCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("UserSegmentCatalog: %s root must be a JSON array" % PATH)
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

static func ordered_ids() -> Array:
    load_all()
    return _order.duplicate()

static func clear_cache() -> void:
    _cache.clear()
    _order.clear()
