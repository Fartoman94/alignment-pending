class_name WorldVariableCatalog
extends RefCounted

## Loads and caches data/world_variables.json: id, name, description,
## effect_description, midpoint, amplitude, period_days. See
## DataValidator for the schema rules (amplitude is bounded so the value
## can never leave [0, 100]).

const PATH: String = "res://data/world_variables.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("WorldVariableCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("WorldVariableCatalog: %s root must be a JSON array" % PATH)
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
