class_name OfficeUpgradeCatalog
extends RefCounted

## Loads and caches data/office_upgrades.json: id, name, cost, effects
## ({morale, employee_cap, trust} — a subset, any combination). See
## DataValidator for the schema rules. Renovations to the *current*
## building (RealEstateManager) — cleared when the company moves to a
## different building (a fresh space doesn't inherit the old one's
## coffee corner), same reasoning documented in RealEstateManager.move_to().

const PATH: String = "res://data/office_upgrades.json"
const EFFECT_KEYS: Array[String] = ["morale", "employee_cap", "trust"]

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("OfficeUpgradeCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("OfficeUpgradeCatalog: %s root must be a JSON array" % PATH)
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
