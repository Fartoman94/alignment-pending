class_name WorkforcePolicyCatalog
extends RefCounted

## Loads and caches data/workforce_policies.json: id, name, description,
## cash_per_pressure, morale_per_pressure, trust_per_pressure,
## safety_debt_per_pressure. Deliberately several genuinely different
## policies (no single one dominates every axis) so automation's staffing
## impact depends on the player's policy choice, not a forced conclusion —
## see DataValidator for the no-dominant-policy check.

const PATH: String = "res://data/workforce_policies.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("WorkforcePolicyCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("WorkforcePolicyCatalog: %s root must be a JSON array" % PATH)
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
