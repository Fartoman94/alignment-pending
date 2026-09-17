class_name TrafficVehicle
extends Node3D

## World+NPC overhaul pass ("el alrededor del garage no puede ser negro
## vacío... autos pasando"): a deliberately simple ping-pong mover, not a
## traffic simulation — the brief itself rules that out ("no hace falta
## tránsito complejo de simulación"). One vehicle drives a straight line
## between two fixed world-space points and reverses at each end; no
## pathfinding, no collision with other vehicles (cheap on purpose, this
## is background dressing, not gameplay).

var start_pos: Vector3
var end_pos: Vector3
var speed: float = 3.0
var _forward: bool = true

func _ready() -> void:
    position = start_pos

func _physics_process(delta: float) -> void:
    var target: Vector3 = end_pos if _forward else start_pos
    var to_target: Vector3 = target - position
    var dist: float = to_target.length()
    if dist < 0.15:
        _forward = not _forward
        return
    var dir: Vector3 = to_target / dist
    position += dir * speed * delta
    # Model's authored length axis is local X (confirmed by rendering) —
    # face travel direction by yawing so local +X tracks dir, same
    # atan2-on-the-flattened-direction approach StaffAgent's own facing
    # fix uses, just swapped for the car's local-X-forward convention
    # instead of a character's local-Z-forward.
    rotation.y = atan2(-dir.z, dir.x)
