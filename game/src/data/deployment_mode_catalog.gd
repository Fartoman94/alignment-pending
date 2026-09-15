class_name DeploymentModeCatalog
extends RefCounted

## Loads and caches data/deployment_modes.json: id, name, base_user_scale,
## exposure_multiplier, rollout_days, inference_compute_per_1k_users. See
## DataValidator for the schema rules.

const PATH: String = "res://data/deployment_modes.json"
## Delay/Internal/Beta/Public per docs/design/UI_UX.md; "delay" isn't a
## deployment mode (it's declining to release), so it's not in the catalog.
const ORDER: Array[String] = ["internal", "beta", "public"]

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("DeploymentModeCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("DeploymentModeCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## The next mode after id in Delay/Internal/Beta/Public order, or "" if
## already at Public (the top).
static func next_mode(id: String) -> String:
    var index: int = ORDER.find(id)
    if index < 0 or index + 1 >= ORDER.size():
        return ""
    return ORDER[index + 1]

static func clear_cache() -> void:
    _cache.clear()
