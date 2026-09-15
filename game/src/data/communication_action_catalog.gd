class_name CommunicationActionCatalog
extends RefCounted

## Loads and caches data/communication_actions.json: id, name, cost,
## trust_delta, hype_debt_delta, cooldown_days. See DataValidator for the
## schema rules. Deliberately small per-action trust_delta values (see
## docs/design/CORE_LOOP_AND_BALANCE.md "Hype debt") — PR nudges trust, it
## does not erase what already happened.

const PATH: String = "res://data/communication_actions.json"

static var _cache: Dictionary = {}
static var _order: Array = []

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("CommunicationActionCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("CommunicationActionCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            var id: String = String(record["id"])
            _cache[id] = record
            _order.append(id)
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

static func ordered_ids() -> Array:
    load_all()
    return _order.duplicate()

static func clear_cache() -> void:
    _cache.clear()
    _order.clear()
