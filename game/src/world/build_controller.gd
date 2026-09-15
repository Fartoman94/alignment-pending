class_name BuildController
extends Node3D

## Build-mode state machine: ghost preview with valid/invalid feedback,
## R to rotate, click to place or sell. Data-driven cost/refund come from
## BuildableCatalog; occupancy/route rules come from BuildGrid.

enum Mode { NONE, PLACE, SELL }

var grid: BuildGrid
var camera: Camera3D

var mode: Mode = Mode.NONE
var current_buildable_id: String = ""
var rotated: bool = false

var _ghost: MeshInstance3D
# building instance id (String, stable across save/load via
# GameState.next_building_id) -> {mesh, cells: Array[Vector2i],
# buildable_id, rotated, cell}
var _placed: Dictionary = {}

func _ready() -> void:
    if not InputMap.has_action("build_rotate"):
        InputMap.add_action("build_rotate")
        var ev: InputEventKey = InputEventKey.new()
        ev.physical_keycode = KEY_R
        InputMap.action_add_event("build_rotate", ev)

func start_place(buildable_id: String) -> void:
    var def: Dictionary = BuildableCatalog.get_def(buildable_id)
    if def.is_empty():
        push_warning("BuildController: unknown buildable id '%s'" % buildable_id)
        return
    mode = Mode.PLACE
    current_buildable_id = buildable_id
    rotated = false
    _clear_ghost()
    _ghost = _make_mesh(def, Color(1.0, 1.0, 1.0, 0.55))
    add_child(_ghost)

func start_sell() -> void:
    mode = Mode.SELL
    current_buildable_id = ""
    _clear_ghost()

func stop() -> void:
    mode = Mode.NONE
    current_buildable_id = ""
    _clear_ghost()

func _clear_ghost() -> void:
    if _ghost != null:
        _ghost.queue_free()
        _ghost = null

func _make_mesh(def: Dictionary, tint: Color) -> MeshInstance3D:
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var w: int = int(footprint.get("w", 1))
    var d: int = int(footprint.get("d", 1))
    var height: float = float(def.get("height", 1.0))
    var mi: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(w * BuildGrid.CELL_SIZE * 0.9, height, d * BuildGrid.CELL_SIZE * 0.9)
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    var base_color: Color = Color(String(def.get("color", "888888")))
    mat.albedo_color = Color(base_color.r * tint.r, base_color.g * tint.g, base_color.b * tint.b, tint.a)
    if tint.a < 1.0:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mesh.material = mat
    mi.mesh = mesh
    mi.position.y = height * 0.5
    return mi

## Adds a dynamic navigation obstacle so staff path around a placed
## building without needing the static navmesh re-baked on every build/sell.
func _add_obstacle(mesh: MeshInstance3D, def: Dictionary) -> void:
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var w: int = int(footprint.get("w", 1))
    var d: int = int(footprint.get("d", 1))
    var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
    obstacle.radius = maxf(w, d) * BuildGrid.CELL_SIZE * 0.5 * 0.95
    obstacle.height = float(def.get("height", 1.0))
    obstacle.avoidance_enabled = true
    mesh.add_child(obstacle)

func _process(_delta: float) -> void:
    if mode != Mode.PLACE:
        return
    if Input.is_action_just_pressed("build_rotate"):
        rotated = not rotated
    if _ghost != null:
        _update_ghost_preview()

func _update_ghost_preview() -> void:
    var world_pos: Vector3 = _mouse_to_floor_world()
    var cell: Vector2i = grid.world_to_cell(world_pos)
    var def: Dictionary = BuildableCatalog.get_def(current_buildable_id)
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var cells: Array[Vector2i] = grid.footprint_cells(cell, int(footprint.get("w", 1)), int(footprint.get("d", 1)), rotated)
    var valid: bool = grid.is_area_free(cells) and GameState.cash >= float(def.get("cost", 0.0))
    var mat: StandardMaterial3D = _ghost.mesh.material
    mat.albedo_color = Color(0.3, 0.9, 0.4, 0.55) if valid else Color(0.95, 0.25, 0.25, 0.55)
    _ghost.position = grid.cell_to_world(cell)
    _ghost.rotation.y = deg_to_rad(90.0) if rotated else 0.0
    _ghost.set_meta("valid", valid)
    _ghost.set_meta("cell", cell)

func _mouse_to_floor_world() -> Vector3:
    if camera == null or not is_inside_tree():
        return Vector3.ZERO
    var mouse_pos: Vector2 = get_viewport().get_mouse_position()
    var from: Vector3 = camera.project_ray_origin(mouse_pos)
    var dir: Vector3 = camera.project_ray_normal(mouse_pos)
    if absf(dir.y) < 0.0001:
        return Vector3.ZERO
    var t: float = -from.y / dir.y
    return from + dir * t

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var mb: InputEventMouseButton = event
    if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
        return
    if mode == Mode.PLACE:
        try_place()
    elif mode == Mode.SELL:
        try_sell(grid.world_to_cell(_mouse_to_floor_world()))

func try_place() -> Error:
    if mode != Mode.PLACE or _ghost == null:
        return ERR_UNCONFIGURED
    if not _ghost.has_meta("cell") or not bool(_ghost.get_meta("valid", false)):
        return ERR_INVALID_PARAMETER
    var cell: Vector2i = _ghost.get_meta("cell")
    var def: Dictionary = BuildableCatalog.get_def(current_buildable_id)
    var cost: float = float(def.get("cost", 0.0))
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var cells: Array[Vector2i] = grid.footprint_cells(cell, int(footprint.get("w", 1)), int(footprint.get("d", 1)), rotated)
    if not grid.is_area_free(cells) or GameState.cash < cost:
        return ERR_INVALID_PARAMETER

    GameState.cash -= cost
    var building_id: String = "bldg_%d" % GameState.next_building_id
    GameState.next_building_id += 1
    grid.occupy(cells, building_id)
    var mesh: MeshInstance3D = _make_mesh(def, Color(1.0, 1.0, 1.0, 1.0))
    mesh.position = grid.cell_to_world(cell)
    mesh.rotation.y = deg_to_rad(90.0) if rotated else 0.0
    add_child(mesh)
    _add_obstacle(mesh, def)
    _placed[building_id] = {
        "mesh": mesh, "cells": cells, "buildable_id": current_buildable_id,
        "rotated": rotated, "cell": cell,
    }
    _sync_game_state()
    return OK

func try_sell(target_cell: Vector2i) -> Error:
    var building_id: String = grid.building_id_at(target_cell)
    if building_id.is_empty() or not _placed.has(building_id):
        return ERR_DOES_NOT_EXIST
    var entry: Dictionary = _placed[building_id]
    var def: Dictionary = BuildableCatalog.get_def(entry["buildable_id"])
    var refund: float = float(def.get("cost", 0.0)) * float(def.get("refund_ratio", 0.0))
    GameState.cash += refund
    grid.free_cells(entry["cells"])
    (entry["mesh"] as MeshInstance3D).queue_free()
    _placed.erase(building_id)
    _sync_game_state()
    return OK

func _sync_game_state() -> void:
    GameState.buildings = save_to_state()

func save_to_state() -> Array:
    var out: Array = []
    for building_id: String in _placed:
        var entry: Dictionary = _placed[building_id]
        var cell: Vector2i = entry["cell"]
        out.append({
            "id": building_id,
            "buildable_id": entry["buildable_id"],
            "cell_x": cell.x,
            "cell_y": cell.y,
            "rotated": entry["rotated"],
        })
    return out

## Rebuilds placed-building meshes/occupancy from saved data, reusing each
## entry's own stable id (assigned once at placement time) rather than
## regenerating one — other systems (e.g. task assignment) persist
## references to a specific building id across save/load. Skips (with a
## warning) any entry whose buildable id is unknown, id is missing/blank,
## or whose cells are no longer free, instead of crashing on stale data.
func load_from_state(data: Array) -> void:
    for raw: Variant in data:
        if not (raw is Dictionary):
            continue
        var entry: Dictionary = raw
        var building_id: String = String(entry.get("id", ""))
        var buildable_id: String = String(entry.get("buildable_id", ""))
        var def: Dictionary = BuildableCatalog.get_def(buildable_id)
        if building_id.is_empty() or def.is_empty():
            push_warning("BuildController: skipping saved building with missing id or unknown buildable id '%s'" % buildable_id)
            continue
        var cell: Vector2i = Vector2i(int(entry.get("cell_x", 0)), int(entry.get("cell_y", 0)))
        var was_rotated: bool = bool(entry.get("rotated", false))
        var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
        var cells: Array[Vector2i] = grid.footprint_cells(cell, int(footprint.get("w", 1)), int(footprint.get("d", 1)), was_rotated)
        if not grid.is_area_free(cells):
            push_warning("BuildController: skipping saved building at %s (cells occupied or out of bounds)" % cell)
            continue

        grid.occupy(cells, building_id)
        var mesh: MeshInstance3D = _make_mesh(def, Color(1.0, 1.0, 1.0, 1.0))
        mesh.position = grid.cell_to_world(cell)
        mesh.rotation.y = deg_to_rad(90.0) if was_rotated else 0.0
        add_child(mesh)
        _add_obstacle(mesh, def)
        _placed[building_id] = {
            "mesh": mesh, "cells": cells, "buildable_id": buildable_id,
            "rotated": was_rotated, "cell": cell,
        }

## World position of a placed building, or Vector3.ZERO if unknown.
func building_position(building_id: String) -> Vector3:
    if not _placed.has(building_id):
        return Vector3.ZERO
    return grid.cell_to_world(_placed[building_id]["cell"])
