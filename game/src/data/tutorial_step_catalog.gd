class_name TutorialStepCatalog
extends RefCounted

## Loads and caches data/tutorial_steps.json: id, title, body,
## completion_metric. Order in the file is the tutorial's sequence. See
## DataValidator for the schema rules.

const PATH: String = "res://data/tutorial_steps.json"

static var _cache: Dictionary = {}
static var _order: Array = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("TutorialStepCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("TutorialStepCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
            _order.append(String(record["id"]))
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## Step ids in authored (file) order — the tutorial's sequence.
static func ordered_ids() -> Array:
    load_all()
    return _order

static func clear_cache() -> void:
    _cache.clear()
    _order.clear()
