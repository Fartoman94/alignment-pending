extends Node

## Save system v1: rotating autosaves, manual save slots, atomic
## temp-write-then-rename, checksum validation, and a migration registry.
## See docs/technical/SAVE_AND_MIGRATIONS.md.

const SAVE_DIR: String = "user://saves"
const AUTOSAVE_SLOT_COUNT: int = 3
const AUTOSAVE_PREFIX: String = "autosave_slot_"
const MANUAL_SLOT_COUNT: int = 3
const MANUAL_PREFIX: String = "manual_slot_"

## vN -> vN+1 migration functions (Callable(Dictionary) -> Dictionary),
## keyed by the version they migrate FROM. Populated in _ready() (a Callable
## bound to self can't live in a const initializer). Never delete an old
## entry before the minimum supported save version is intentionally raised.
var MIGRATIONS: Dictionary = {}

func _ready() -> void:
    MIGRATIONS[1] = Callable(self, "_migrate_v1_to_v2")

## v1 -> v2 (P26): GameState.rival (a single Dictionary) became
## GameState.rivals (an Array of several procedural rivals). An old save's
## one rival becomes rivals[0] with a stable id, and its launch history
## entries are stamped with that same rival_id.
func _migrate_v1_to_v2(payload: Dictionary) -> Dictionary:
    var data: Dictionary = payload.duplicate(true)
    var legacy_rival: Variant = data.get("rival", {})
    if legacy_rival is Dictionary and not (legacy_rival as Dictionary).is_empty():
        var rival: Dictionary = (legacy_rival as Dictionary).duplicate(true)
        rival["id"] = "rival_1"
        data["rivals"] = [rival]
        var history: Variant = data.get("rival_launch_history", [])
        var migrated_history: Array = []
        if history is Array:
            for h: Variant in (history as Array):
                var entry: Dictionary = (h as Dictionary).duplicate(true)
                if not entry.has("rival_id"):
                    entry["rival_id"] = "rival_1"
                migrated_history.append(entry)
        data["rival_launch_history"] = migrated_history
    else:
        data["rivals"] = []
    data.erase("rival")
    return data

func _ensure_save_dir() -> void:
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _autosave_path(slot: int) -> String:
    return "%s/%s%d.json" % [SAVE_DIR, AUTOSAVE_PREFIX, slot]

func _manual_path(slot: int) -> String:
    return "%s/%s%d.json" % [SAVE_DIR, MANUAL_PREFIX, slot]

## Rotates the 3 autosave slots (0 = newest) and writes the current
## GameState as the new slot 0.
func autosave() -> Error:
    _ensure_save_dir()
    for i in range(AUTOSAVE_SLOT_COUNT - 1, 0, -1):
        var src: String = _autosave_path(i - 1)
        var dst: String = _autosave_path(i)
        if not FileAccess.file_exists(src):
            continue
        if FileAccess.file_exists(dst):
            DirAccess.remove_absolute(dst)
        DirAccess.rename_absolute(src, dst)
    return _write_atomic(_autosave_path(0), GameState.to_dict())

## Loads the newest valid autosave, falling back through older rotating
## slots if the newest is missing, unparsable, or fails its checksum.
func load_newest_autosave() -> Error:
    var last_err: Error = ERR_FILE_NOT_FOUND
    for i in range(AUTOSAVE_SLOT_COUNT):
        var path: String = _autosave_path(i)
        if not FileAccess.file_exists(path):
            continue
        var err: Error = _load_from_path(path)
        if err == OK:
            if i > 0:
                push_warning("SaveManager: newest autosave(s) were corrupt; recovered from fallback slot %d" % i)
            return OK
        push_warning("SaveManager: autosave slot %d failed to load (error %s); trying an older slot" % [i, err])
        last_err = err
    return last_err

func has_any_autosave() -> bool:
    for i in range(AUTOSAVE_SLOT_COUNT):
        if FileAccess.file_exists(_autosave_path(i)):
            return true
    return false

func save_manual(slot: int) -> Error:
    if slot < 0 or slot >= MANUAL_SLOT_COUNT:
        return ERR_INVALID_PARAMETER
    _ensure_save_dir()
    return _write_atomic(_manual_path(slot), GameState.to_dict())

func load_manual(slot: int) -> Error:
    if slot < 0 or slot >= MANUAL_SLOT_COUNT:
        return ERR_INVALID_PARAMETER
    return _load_from_path(_manual_path(slot))

func manual_slot_exists(slot: int) -> bool:
    return slot >= 0 and slot < MANUAL_SLOT_COUNT and FileAccess.file_exists(_manual_path(slot))

func has_any_save() -> bool:
    if has_any_autosave():
        return true
    for i in range(MANUAL_SLOT_COUNT):
        if manual_slot_exists(i):
            return true
    return false

## Writes payload to path via temp-file-then-atomic-rename: `path` is only
## ever replaced once the written file has been read back and validated.
func _write_atomic(path: String, payload: Dictionary) -> Error:
    var envelope: Dictionary = _wrap_envelope(payload)
    var tmp_path: String = path + ".tmp"
    var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(envelope))
    file.close()

    var verify_payload: Dictionary = {}
    var verify_err: Error = _read_envelope(tmp_path, verify_payload)
    if verify_err != OK:
        DirAccess.remove_absolute(tmp_path)
        push_error("SaveManager: wrote an unreadable save to %s (error %s); discarded" % [tmp_path, verify_err])
        return verify_err

    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    return DirAccess.rename_absolute(tmp_path, path)

func _wrap_envelope(payload: Dictionary) -> Dictionary:
    # JSON has no int/float distinction: parsing a save back always yields
    # floats. Hash a round-tripped copy so the checksum matches what a
    # fresh read will recompute, instead of hashing pre-round-trip types
    # (e.g. an int campaign_seed) that would never match on load.
    var normalized: Dictionary = JSON.parse_string(JSON.stringify(payload))
    return {
        "save_version": GameState.SAVE_VERSION,
        "checksum": JSON.stringify(normalized).sha256_text(),
        "payload": payload,
    }

## Parses, checksum-validates and migrates the envelope at path, filling
## out_payload with the resulting current-version campaign data.
func _read_envelope(path: String, out_payload: Dictionary) -> Error:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return FileAccess.get_open_error()
    var text: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        return ERR_PARSE_ERROR
    var envelope: Dictionary = parsed
    if not (envelope.has("save_version") and envelope.has("checksum") and envelope.has("payload")):
        return ERR_INVALID_DATA
    if not (envelope["payload"] is Dictionary):
        return ERR_INVALID_DATA

    var payload: Dictionary = envelope["payload"]
    var expected_checksum: String = JSON.stringify(payload).sha256_text()
    if String(envelope["checksum"]) != expected_checksum:
        return ERR_FILE_CORRUPT

    var version: int = int(envelope["save_version"])
    if version > GameState.SAVE_VERSION:
        push_error("SaveManager: save at %s is a newer version (%d) than this build supports (%d)" % [path, version, GameState.SAVE_VERSION])
        return ERR_INVALID_DATA

    var migrated: Dictionary = _migrate(payload, version)
    out_payload.clear()
    for key: String in migrated:
        out_payload[key] = migrated[key]
    return OK

func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
    var data: Dictionary = payload
    var version: int = from_version
    while version < GameState.SAVE_VERSION:
        if not MIGRATIONS.has(version):
            push_error("SaveManager: no migration registered for v%d -> v%d; save may be incomplete" % [version, version + 1])
            break
        var migrate_fn: Callable = MIGRATIONS[version]
        data = migrate_fn.call(data)
        version += 1
    return data

func _load_from_path(path: String) -> Error:
    var payload: Dictionary = {}
    var err: Error = _read_envelope(path, payload)
    if err != OK:
        return err
    GameState.from_dict(payload)
    return OK
