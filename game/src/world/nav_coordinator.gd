class_name NavCoordinator
extends RefCounted

## Prevents two staff from claiming the exact same destination point at
## once — the simplest source of an "obvious deadlock" (two agents both
## trying to stand in the same spot forever). Path-level collision between
## agents is handled separately by NavigationAgent3D avoidance.

const CELL_SIZE: float = 1.0

var _reserved: Dictionary = {}

func _quantize(pos: Vector3) -> Vector2i:
    return Vector2i(int(round(pos.x / CELL_SIZE)), int(round(pos.z / CELL_SIZE)))

func try_reserve(pos: Vector3) -> bool:
    var key: Vector2i = _quantize(pos)
    if _reserved.has(key):
        return false
    _reserved[key] = true
    return true

func release(pos: Vector3) -> void:
    _reserved.erase(_quantize(pos))

func reserved_count() -> int:
    return _reserved.size()
