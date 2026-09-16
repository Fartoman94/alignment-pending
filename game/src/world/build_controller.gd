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
## P42 colorblind redundancy: the ghost's green/red valid/invalid tint is
## a color-only signal, so when SettingsManager.colorblind_mode is on this
## label spells the same state out in text ("OK"/"X") too.
var _ghost_label: Label3D
## P43: the single source of truth for which cell PLACE/SELL currently
## targets. Mouse motion and keyboard/joypad ui_up/down/left/right both
## just update this — whichever the player used most recently wins,
## instead of fighting each other for control of the ghost every frame.
var _cursor_cell: Vector2i = Vector2i.ZERO
var _sell_marker: MeshInstance3D
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
    EventBus.day_advanced.connect(_on_day_advanced)

func _on_day_advanced(_day: int) -> void:
    if GameState.daily_infrastructure_cost > 0.0:
        GameState.cash -= GameState.daily_infrastructure_cost

func start_place(buildable_id: String) -> void:
    var def: Dictionary = BuildableCatalog.get_def(buildable_id)
    if def.is_empty():
        push_warning("BuildController: unknown buildable id '%s'" % buildable_id)
        return
    mode = Mode.PLACE
    current_buildable_id = buildable_id
    rotated = false
    _cursor_cell = _default_cursor_cell()
    _clear_ghost()
    _ghost = _make_mesh(def, Color(1.0, 1.0, 1.0, 0.55))
    add_child(_ghost)
    _ghost_label = Label3D.new()
    _ghost_label.name = "ColorblindIndicator"
    _ghost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _ghost_label.font_size = 48
    _ghost_label.outline_size = 12
    _ghost_label.position.y = float(def.get("height", 1.0)) + 0.4
    _ghost_label.visible = false
    _ghost.add_child(_ghost_label)
    # P43: a controller/keyboard player needs to move the ghost with
    # ui_up/down/left/right, the same actions Controls use for menu focus
    # traversal — releasing focus keeps those inputs free for the 3D
    # cursor instead of silently reshuffling whichever HUD button was
    # last focused.
    if is_inside_tree():
        get_viewport().gui_release_focus()

func start_sell() -> void:
    mode = Mode.SELL
    current_buildable_id = ""
    _cursor_cell = _default_cursor_cell()
    _clear_ghost()
    _sell_marker = ProceduralMeshFactory.make_box("SellMarker", Vector3(BuildGrid.CELL_SIZE * 0.9, 0.1, BuildGrid.CELL_SIZE * 0.9), Color(0.95, 0.25, 0.25, 0.5))
    add_child(_sell_marker)
    _update_sell_marker()
    if is_inside_tree():
        get_viewport().gui_release_focus()

func stop() -> void:
    mode = Mode.NONE
    current_buildable_id = ""
    _clear_ghost()
    if _sell_marker != null:
        _sell_marker.queue_free()
        _sell_marker = null

## Grid-center on X, but never BuildGrid.ROUTE_ROW on Y — that row is the
## reserved walkway (always invalid to place/sell on), so a controller
## player wouldn't be able to tell why their very first cursor position
## looked wrong without moving it first.
func _default_cursor_cell() -> Vector2i:
    if grid == null:
        return Vector2i.ZERO
    var row: int = BuildGrid.GRID_ROWS / 2
    if grid.is_reserved(Vector2i(0, row)):
        row = 0
    return Vector2i(BuildGrid.GRID_COLS / 2, row)

func _clear_ghost() -> void:
    if _ghost != null:
        _ghost.queue_free()
        _ghost = null
        _ghost_label = null

## The actual placed building's visual (ghost preview always stays the
## simple translucent procedural box below — a plain tinted silhouette is
## clearer valid/invalid placement feedback than a detailed model would
## be, so this is a deliberate scope boundary, not a shortcut). Loads the
## buildable's real authored model (finalization-pack 3D asset pack) if
## its data has one; otherwise falls back to the same procedural box
## every buildable used before (e.g. safety_lab, which the pack has no
## matching asset for).
func _make_real_mesh(def: Dictionary) -> Node3D:
    var model_path: String = String(def.get("model", ""))
    if model_path.is_empty():
        return _make_mesh(def, Color(1.0, 1.0, 1.0, 1.0))
    var packed: PackedScene = load(model_path)
    if packed == null:
        push_error("BuildController: could not load buildable model '%s'" % model_path)
        return _make_mesh(def, Color(1.0, 1.0, 1.0, 1.0))
    var model: Node3D = packed.instantiate()
    # Same Z-up-authored-in-local-space correction as StaffAgent's
    # character models (see that script's docstring) — confirmed the
    # same fix applies here by rendering and looking at the pixels
    # again, not assumed just because it's the same asset pack.
    model.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    model.name = String(def.get("id", "Buildable")).capitalize()
    return model

## Buildable geometry (P39: routed through ProceduralMeshFactory instead of
## building BoxMesh/StandardMaterial3D inline). Still used for the ghost
## preview always, and as the fallback for any buildable with no real
## model in _make_real_mesh().
func _make_mesh(def: Dictionary, tint: Color) -> MeshInstance3D:
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var w: int = int(footprint.get("w", 1))
    var d: int = int(footprint.get("d", 1))
    var height: float = float(def.get("height", 1.0))
    var base_color: Color = Color(String(def.get("color", "888888")))
    var tinted_color: Color = Color(base_color.r * tint.r, base_color.g * tint.g, base_color.b * tint.b, tint.a)
    var mi: MeshInstance3D = ProceduralMeshFactory.make_box(
        String(def.get("id", "Buildable")).capitalize(),
        Vector3(w * BuildGrid.CELL_SIZE * 0.9, height, d * BuildGrid.CELL_SIZE * 0.9),
        tinted_color,
    )
    mi.position.y = height * 0.5
    return mi

## Adds a dynamic navigation obstacle so staff path around a placed
## building without needing the static navmesh re-baked on every build/sell.
func _add_obstacle(mesh: Node3D, def: Dictionary) -> void:
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var w: int = int(footprint.get("w", 1))
    var d: int = int(footprint.get("d", 1))
    var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
    obstacle.radius = maxf(w, d) * BuildGrid.CELL_SIZE * 0.5 * 0.95
    obstacle.height = float(def.get("height", 1.0))
    obstacle.avoidance_enabled = true
    mesh.add_child(obstacle)

func _process(_delta: float) -> void:
    if mode == Mode.NONE:
        return
    _handle_cursor_movement()
    if mode == Mode.PLACE:
        if Input.is_action_just_pressed("build_rotate"):
            rotated = not rotated
        if _ghost != null:
            _update_ghost_preview()
        if Input.is_action_just_pressed("build_confirm"):
            try_place()
    elif mode == Mode.SELL:
        _update_sell_marker()
        if Input.is_action_just_pressed("build_confirm"):
            try_sell(_cursor_cell)

## Keyboard/joypad cell movement (ui_up/down/left/right — the same
## built-in actions Controls use for menu focus, freed up for this
## purpose by start_place()/start_sell() releasing focus). Mouse motion
## (see _unhandled_input) is the other way to move the cursor; both write
## the same _cursor_cell so neither fights the other.
func _handle_cursor_movement() -> void:
    var step: Vector2i = Vector2i.ZERO
    if Input.is_action_just_pressed("ui_left"):
        step.x -= 1
    if Input.is_action_just_pressed("ui_right"):
        step.x += 1
    if Input.is_action_just_pressed("ui_up"):
        step.y -= 1
    if Input.is_action_just_pressed("ui_down"):
        step.y += 1
    if step != Vector2i.ZERO:
        _cursor_cell = Vector2i(
            clampi(_cursor_cell.x + step.x, 0, BuildGrid.GRID_COLS - 1),
            clampi(_cursor_cell.y + step.y, 0, BuildGrid.GRID_ROWS - 1),
        )

func _update_ghost_preview() -> void:
    var def: Dictionary = BuildableCatalog.get_def(current_buildable_id)
    var footprint: Dictionary = def.get("footprint", {"w": 1, "d": 1})
    var cells: Array[Vector2i] = grid.footprint_cells(_cursor_cell, int(footprint.get("w", 1)), int(footprint.get("d", 1)), rotated)
    var fits_power: bool = GameState.power_used + float(def.get("power_draw", 0.0)) <= GameState.power_capacity
    var valid: bool = grid.is_area_free(cells) and GameState.cash >= float(def.get("cost", 0.0)) and fits_power
    var mat: StandardMaterial3D = _ghost.mesh.material
    mat.albedo_color = Color(0.3, 0.9, 0.4, 0.55) if valid else Color(0.95, 0.25, 0.25, 0.55)
    _ghost.position = grid.cell_to_world(_cursor_cell)
    _ghost.rotation.y = deg_to_rad(90.0) if rotated else 0.0
    _ghost.set_meta("valid", valid)
    _ghost.set_meta("cell", _cursor_cell)
    _update_ghost_indicator(valid)

func _update_sell_marker() -> void:
    if _sell_marker != null:
        var world_pos: Vector3 = grid.cell_to_world(_cursor_cell)
        _sell_marker.position = Vector3(world_pos.x, 0.05, world_pos.z)

## P42 colorblind redundancy: the same valid/invalid state as the ghost's
## tint, spelled out in text, so it never depends on color perception alone.
func _update_ghost_indicator(valid: bool) -> void:
    if _ghost_label == null:
        return
    _ghost_label.visible = SettingsManager.colorblind_mode
    _ghost_label.text = "OK" if valid else "X"
    _ghost_label.modulate = Color.WHITE if valid else Color(1.0, 0.6, 0.6)

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
    if event is InputEventMouseMotion and mode != Mode.NONE:
        _cursor_cell = grid.world_to_cell(_mouse_to_floor_world())
        return
    if not (event is InputEventMouseButton):
        return
    var mb: InputEventMouseButton = event
    if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
        return
    if mode == Mode.PLACE:
        try_place()
    elif mode == Mode.SELL:
        _cursor_cell = grid.world_to_cell(_mouse_to_floor_world())
        try_sell(_cursor_cell)

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
    var power_draw: float = float(def.get("power_draw", 0.0))
    if not grid.is_area_free(cells) or GameState.cash < cost or GameState.power_used + power_draw > GameState.power_capacity:
        return ERR_INVALID_PARAMETER

    GameState.cash -= cost
    var building_id: String = "bldg_%d" % GameState.next_building_id
    GameState.next_building_id += 1
    grid.occupy(cells, building_id)
    var mesh: Node3D = _make_real_mesh(def)
    mesh.position = grid.cell_to_world(cell)
    mesh.rotation.y = deg_to_rad(90.0) if rotated else 0.0
    add_child(mesh)
    _add_obstacle(mesh, def)
    _placed[building_id] = {
        "mesh": mesh, "cells": cells, "buildable_id": current_buildable_id,
        "rotated": rotated, "cell": cell,
    }
    _sync_game_state()
    AudioManager.play_sfx("build_place")
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
    (entry["mesh"] as Node3D).queue_free()
    _placed.erase(building_id)
    _sync_game_state()
    return OK

func _sync_game_state() -> void:
    GameState.buildings = save_to_state()
    recompute_infrastructure()

## Recomputes compute/power/heat/operating-cost totals from every currently
## placed building. Always derived, never independently mutated, so it can
## never drift out of sync with the actual building list.
func recompute_infrastructure() -> void:
    var compute_units: float = 0.0
    var power_draw: float = 0.0
    var heat_output: float = 0.0
    var operating_cost: float = 0.0
    for building_id: String in _placed:
        var def: Dictionary = BuildableCatalog.get_def(_placed[building_id]["buildable_id"])
        compute_units += float(def.get("compute_units", 0.0))
        power_draw += float(def.get("power_draw", 0.0))
        heat_output += float(def.get("heat_output", 0.0))
        operating_cost += float(def.get("operating_cost_per_day", 0.0))
    GameState.compute_capacity = GameState.BASE_COMPUTE_CAPACITY + compute_units + GameState.research_compute_bonus
    GameState.power_used = GameState.BASE_POWER_DRAW + power_draw
    GameState.heat_load = heat_output
    GameState.daily_infrastructure_cost = operating_cost

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
        var mesh: Node3D = _make_real_mesh(def)
        mesh.position = grid.cell_to_world(cell)
        mesh.rotation.y = deg_to_rad(90.0) if was_rotated else 0.0
        add_child(mesh)
        _add_obstacle(mesh, def)
        _placed[building_id] = {
            "mesh": mesh, "cells": cells, "buildable_id": buildable_id,
            "rotated": was_rotated, "cell": cell,
        }
    recompute_infrastructure()

## World position of a placed building, or Vector3.ZERO if unknown.
func building_position(building_id: String) -> Vector3:
    if not _placed.has(building_id):
        return Vector3.ZERO
    return grid.cell_to_world(_placed[building_id]["cell"])
