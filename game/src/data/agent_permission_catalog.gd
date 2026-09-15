class_name AgentPermissionCatalog
extends RefCounted

## Loads and caches data/agent_permissions.json: id, name, category,
## productivity_description, risk_description, productivity_effects,
## risk_effects. Every permission carries both a productivity gain and an
## explicit risk surface — enforced by DataValidator, not just convention.

const PATH: String = "res://data/agent_permissions.json"

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("AgentPermissionCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("AgentPermissionCatalog: %s root must be a JSON array" % PATH)
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
