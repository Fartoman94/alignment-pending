class_name NewsTemplateCatalog
extends RefCounted

## Loads and caches data/news_templates.json: id, category, template.
## Offline authored templates only — never a live LLM call, never a real
## publication/service name (see NewsFeedManager.OUTLETS). See
## DataValidator for the schema rules.

const PATH: String = "res://data/news_templates.json"

static var _cache: Dictionary = {}  # category -> Array[String] (templates)
static var _all: Array = []

static func load_all() -> Array:
    if not _all.is_empty():
        return _all
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("NewsTemplateCatalog: could not open %s" % PATH)
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("NewsTemplateCatalog: %s root must be a JSON array" % PATH)
        return []
    _all = parsed
    return _all

## Every template string for one category, in file order.
static func templates_for(category: String) -> Array:
    if _cache.is_empty():
        for entry: Variant in load_all():
            var record: Dictionary = entry
            var cat: String = String(record.get("category", ""))
            if not _cache.has(cat):
                _cache[cat] = []
            (_cache[cat] as Array).append(String(record.get("template", "")))
    return _cache.get(category, [])

static func clear_cache() -> void:
    _cache.clear()
    _all = []
