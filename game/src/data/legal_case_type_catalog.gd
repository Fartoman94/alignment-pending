class_name LegalCaseTypeCatalog
extends RefCounted

## Loads and caches data/legal_case_types.json: id, name,
## trigger_min_exposure, case_deadline_days, cooldown_days,
## injunction_probability_per_day, settle, fight, injunction. Abstract case
## archetypes only — no real plaintiffs. See DataValidator for schema rules.

const PATH: String = "res://data/legal_case_types.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("LegalCaseTypeCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("LegalCaseTypeCatalog: %s root must be a JSON array" % PATH)
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
