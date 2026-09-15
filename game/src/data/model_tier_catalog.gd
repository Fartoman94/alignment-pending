class_name ModelTierCatalog
extends RefCounted

## Loads and caches data/model_tiers.json: id, name, cost, duration_minutes,
## capability_base, safety_base, autonomy_base, cost_efficiency_base. See
## DataValidator for the schema rules.

const PATH: String = "res://data/model_tiers.json"

static var _cache: Dictionary = {}
static var _order: Array = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("ModelTierCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("ModelTierCatalog: %s root must be a JSON array" % PATH)
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
