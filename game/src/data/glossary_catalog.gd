class_name GlossaryCatalog
extends RefCounted

## Loads and caches data/glossary_terms.json: id, term, definition. See
## DataValidator for the schema rules.

const PATH: String = "res://data/glossary_terms.json"

static var _cache: Dictionary = {}
static var _order: Array = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("GlossaryCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("GlossaryCatalog: %s root must be a JSON array" % PATH)
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

## Term ids sorted alphabetically by term text, for a readable glossary list.
static func ordered_ids() -> Array:
    load_all()
    var ids: Array = _order.duplicate()
    ids.sort_custom(func(a, b): return String(_cache[a].get("term", a)) < String(_cache[b].get("term", b)))
    return ids

static func clear_cache() -> void:
    _cache.clear()
    _order.clear()
