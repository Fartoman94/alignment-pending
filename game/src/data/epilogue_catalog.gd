class_name EpilogueCatalog
extends RefCounted

## Loads and caches data/epilogues.json: id, title, body. `body` is a
## String.format() template filled from GameState.ending_summary (P37) —
## tracked consequences, not a moral score. 9 GDD-named endings (8 regular
## + 1 secret) plus the always-separate "bankruptcy" failure ending.

const PATH: String = "res://data/epilogues.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("EpilogueCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("EpilogueCatalog: %s root must be a JSON array" % PATH)
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
