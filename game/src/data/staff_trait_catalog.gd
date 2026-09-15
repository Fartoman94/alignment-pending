class_name StaffTraitCatalog
extends RefCounted

## Loads and caches data/staff_traits.json: id, name, skill_deltas,
## morale_delta, fatigue_resistance. See DataValidator for the bounds each
## field is required to stay within (traits must have bounded impact).

const PATH: String = "res://data/staff_traits.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("StaffTraitCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("StaffTraitCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

static func clear_cache() -> void:
    _cache.clear()
