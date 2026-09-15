class_name SfxCueCatalog
extends RefCounted

## Loads and caches data/sfx_cues.json: id, bus, waveform, envelope timing,
## gain. Every cue is synthesized at runtime by AudioSynth — see
## DataValidator for the schema rules (including the envelope-fits-
## duration click-free check).

const PATH: String = "res://data/sfx_cues.json"

static var _by_id: Dictionary = {}

static func load_all() -> Dictionary:
    if not _by_id.is_empty():
        return _by_id
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("SfxCueCatalog: could not open %s" % PATH)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not (parsed is Array):
        push_error("SfxCueCatalog: %s root must be a JSON array" % PATH)
        return {}
    for entry: Variant in (parsed as Array):
        var record: Dictionary = entry
        var id: String = String(record.get("id", ""))
        if not id.is_empty():
            _by_id[id] = record
    return _by_id

static func get_def(cue_id: String) -> Dictionary:
    return load_all().get(cue_id, {})

static func clear_cache() -> void:
    _by_id = {}
