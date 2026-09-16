class_name LocalMockPlatformBackend
extends PlatformBackend

## The only backend actually shipped (P46): a local stand-in for a real
## platform SDK, so the game has real, working achievements/cloud-save
## hooks without an unapproved third-party dependency. "Cloud" here is a
## local file standing in for a real remote endpoint — enough to prove
## the PlatformService interface end-to-end; a real cloud backend swaps
## in later by implementing the same PlatformBackend interface, without
## AchievementManager/SaveManager changing at all.

const ACHIEVEMENTS_PATH: String = "user://platform_mock/achievements.json"
const CLOUD_DIR: String = "user://platform_mock/cloud"

var _unlocked: Dictionary = {}
var _loaded: bool = false

func is_available() -> bool:
    return true

func is_cloud_available() -> bool:
    return true

func unlock_achievement(id: String) -> Error:
    _ensure_loaded()
    _unlocked[id] = true
    return _save_achievements()

func is_achievement_unlocked(id: String) -> bool:
    _ensure_loaded()
    return _unlocked.has(id)

func unlocked_achievement_ids() -> Array:
    _ensure_loaded()
    return _unlocked.keys()

func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    if not FileAccess.file_exists(ACHIEVEMENTS_PATH):
        return
    var file: FileAccess = FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Array:
        for id: Variant in parsed:
            _unlocked[String(id)] = true

func _save_achievements() -> Error:
    DirAccess.make_dir_recursive_absolute(ACHIEVEMENTS_PATH.get_base_dir())
    var file: FileAccess = FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(_unlocked.keys()))
    file.close()
    return OK

func save_to_cloud(slot: String, payload: Dictionary) -> Error:
    DirAccess.make_dir_recursive_absolute(CLOUD_DIR)
    var file: FileAccess = FileAccess.open("%s/%s.json" % [CLOUD_DIR, slot], FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(payload))
    file.close()
    return OK

func load_from_cloud(slot: String) -> Dictionary:
    var path: String = "%s/%s.json" % [CLOUD_DIR, slot]
    if not FileAccess.file_exists(path):
        return {}
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed if parsed is Dictionary else {}

## Test-only: clears in-memory + on-disk mock state so tests don't leak
## unlocked achievements across runs of this same local user:// profile.
func clear_all() -> void:
    _unlocked = {}
    _loaded = true
    _save_achievements()
