class_name RivalDoctrineCatalog
extends RefCounted

## Loads and caches data/rival_doctrines.json: id, name,
## research_pace_multiplier, market_pressure_multiplier. See
## docs/design/WORLD_AND_NARRATIVE.md ("Each rival receives randomized
## doctrine") and DataValidator for the schema rules.

const PATH: String = "res://data/rival_doctrines.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("RivalDoctrineCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("RivalDoctrineCatalog: %s root must be a JSON array" % PATH)
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
