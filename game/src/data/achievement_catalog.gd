class_name AchievementCatalog
extends RefCounted

## Loads and caches data/achievements.json: id, name, description,
## trigger (see AchievementManager for the trigger vocabulary). Original,
## fictional achievement flavor — no real-company references, per
## docs/design/ACHIEVEMENTS_AND_META.md. See DataValidator for schema rules.

const PATH: String = "res://data/achievements.json"

static var _by_id: Dictionary = {}

static func load_all() -> Dictionary:
    if not _by_id.is_empty():
        return _by_id
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("AchievementCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("AchievementCatalog: %s root must be a JSON array" % PATH)
        return {}
    for entry: Variant in (parsed as Array):
        var record: Dictionary = entry
        var id: String = String(record.get("id", ""))
        if not id.is_empty():
            _by_id[id] = record
    return _by_id

static func get_def(achievement_id: String) -> Dictionary:
    return load_all().get(achievement_id, {})

static func ordered_ids() -> Array:
    return load_all().keys()

static func clear_cache() -> void:
    _by_id = {}
