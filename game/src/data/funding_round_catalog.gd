class_name FundingRoundCatalog
extends RefCounted

## Loads and caches data/funding_rounds.json: id, name, min_valuation,
## amount, equity_pct, obligation_per_day. See DataValidator for the
## schema rules.

const PATH: String = "res://data/funding_rounds.json"
## Seed -> Series A -> Series B, raised strictly in order (mirrors
## DeploymentModeCatalog's Internal -> Beta -> Public order).
const ORDER: Array[String] = ["seed", "series_a", "series_b"]

static var _cache: Dictionary = {}

static func load_all() -> Dictionary:
    if not _cache.is_empty():
        return _cache
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("FundingRoundCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("FundingRoundCatalog: %s root must be a JSON array" % PATH)
        return {}
    var records: Array = parsed
    for entry: Variant in records:
        if entry is Dictionary and entry.has("id"):
            var record: Dictionary = entry
            _cache[String(record["id"])] = record
    return _cache

static func get_def(id: String) -> Dictionary:
    return load_all().get(id, {})

## The next round id after raised_count rounds have already been raised, or
## "" once every round in ORDER has been raised.
static func round_after(raised_count: int) -> String:
    if raised_count < 0 or raised_count >= ORDER.size():
        return ""
    return ORDER[raised_count]

static func clear_cache() -> void:
    _cache.clear()
