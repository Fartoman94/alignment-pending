class_name PlatformBackend
extends RefCounted

## The platform-service interface (P46): every method here is what a real
## platform SDK adapter (Steam, a console store, etc.) would implement.
## The base class's defaults ARE the "platform unavailable" behavior —
## unavailable, no achievements, no cloud — so an unimplemented/future
## backend degrades gracefully by construction rather than needing every
## caller to special-case "no backend". PlatformService never talks to a
## real SDK directly; it only ever calls through this interface, so a
## real backend can be swapped in later (see LocalMockPlatformBackend for
## the only backend actually shipped today) without any caller changing.

func is_available() -> bool:
    return false

func unlock_achievement(_id: String) -> Error:
    return ERR_UNAVAILABLE

func is_achievement_unlocked(_id: String) -> bool:
    return false

func unlocked_achievement_ids() -> Array:
    return []

func is_cloud_available() -> bool:
    return false

func save_to_cloud(_slot: String, _payload: Dictionary) -> Error:
    return ERR_UNAVAILABLE

func load_from_cloud(_slot: String) -> Dictionary:
    return {}
