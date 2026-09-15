class_name BuildableCatalog
extends RefCounted

## Loads and caches data/buildables.json: id, name, category,
## footprint {w,d}, cost, refund_ratio, color, height. See
## docs/technical/DATA_SCHEMA.md and DataValidator for the schema rules.

const PATH: String = "res://data/buildables.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("BuildableCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("BuildableCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## Cache is static/process-lifetime; only needed by tests that mutate the
## backing file mid-run.
static func clear_cache() -> void:
    _cache.clear()
