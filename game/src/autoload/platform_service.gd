extends Node

## Platform-service adapter (P46): every other system talks to THIS
## autoload, never to a platform SDK directly — see PlatformBackend for
## the interface and LocalMockPlatformBackend for the only backend
## actually shipped today. A real Steam/console backend plugs in later
## via set_backend() without AchievementManager/SaveManager changing.

var _backend: PlatformBackend

func _ready() -> void:
    _backend = LocalMockPlatformBackend.new()

## Swaps the active backend — the hook a real platform adapter (or a
## test wanting an unavailable/null backend) uses.
func set_backend(backend: PlatformBackend) -> void:
    _backend = backend

func is_available() -> bool:
    return _backend != null and _backend.is_available()

func unlock_achievement(id: String) -> Error:
    if not is_available():
        return ERR_UNAVAILABLE
    return _backend.unlock_achievement(id)

func is_achievement_unlocked(id: String) -> bool:
    if not is_available():
        return false
    return _backend.is_achievement_unlocked(id)

func unlocked_achievement_ids() -> Array:
    if not is_available():
        return []
    return _backend.unlocked_achievement_ids()

func is_cloud_available() -> bool:
    return is_available() and _backend.is_cloud_available()

func save_to_cloud(slot: String, payload: Dictionary) -> Error:
    if not is_cloud_available():
        return ERR_UNAVAILABLE
    return _backend.save_to_cloud(slot, payload)

func load_from_cloud(slot: String) -> Dictionary:
    if not is_cloud_available():
        return {}
    return _backend.load_from_cloud(slot)
