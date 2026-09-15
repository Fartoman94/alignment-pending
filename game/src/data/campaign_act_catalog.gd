class_name CampaignActCatalog
extends RefCounted

## Loads and caches data/campaign_acts.json: number, name, tagline,
## milestone_description — the five acts from
## docs/design/WORLD_AND_NARRATIVE.md's "Narrative acts" section. See
## DataValidator for the schema rules.

const PATH: String = "res://data/campaign_acts.json"

static var _cache: Dictionary = {}  # act number (int) -> record

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("CampaignActCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("CampaignActCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and (entry as Dictionary).has("number"):
            var record: Dictionary = entry
            _cache[int(record["number"])] = record
    return _cache

static func get_def(number: int) -> Dictionary:
    return load_all().get(number, {})

static func clear_cache() -> void:
    _cache.clear()
