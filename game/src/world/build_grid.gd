class_name BuildGrid
extends Node3D

## Office floor grid: cell<->world conversion, footprint occupancy, and the
## reserved walkway row that placements may never block (path-obstruction
## validation; full staff pathfinding is P09's job).

const CELL_SIZE: float = 2.0
const GRID_COLS: int = 8
const GRID_ROWS: int = 6
const ORIGIN_X: float = -8.0
const ORIGIN_Z: float = -6.0
# East-west aisle every staff member must be able to walk through.
const ROUTE_ROW: int = 3

# Vector2i cell -> building instance id (String).
var _occupied: Dictionary = {}

func is_in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS

func is_reserved(cell: Vector2i) -> bool:
    return cell.y == ROUTE_ROW

func cell_to_world(cell: Vector2i) -> Vector3:
    return Vector3(ORIGIN_X + CELL_SIZE * (cell.x + 0.5), 0.0, ORIGIN_Z + CELL_SIZE * (cell.y + 0.5))

func world_to_cell(world_pos: Vector3) -> Vector2i:
    var col: int = int(floor((world_pos.x - ORIGIN_X) / CELL_SIZE))
    var row: int = int(floor((world_pos.z - ORIGIN_Z) / CELL_SIZE))
    return Vector2i(col, row)

## Cells covered by a footprint_w x footprint_d object rooted at origin_cell.
## A 90-degree rotation swaps width and depth.
func footprint_cells(origin_cell: Vector2i, footprint_w: int, footprint_d: int, rotated: bool) -> Array[Vector2i]:
    var w: int = footprint_d if rotated else footprint_w
    var d: int = footprint_w if rotated else footprint_d
    var cells: Array[Vector2i] = []
    for dx in w:
        for dz in d:
            cells.append(Vector2i(origin_cell.x + dx, origin_cell.y + dz))
    return cells

func is_area_free(cells: Array[Vector2i]) -> bool:
    if cells.is_empty():
        return false
    for cell: Vector2i in cells:
        if not is_in_bounds(cell):
            return false
        if is_reserved(cell):
            return false
        if _occupied.has(cell):
            return false
    return true

func occupy(cells: Array[Vector2i], building_id: String) -> void:
    for cell: Vector2i in cells:
        _occupied[cell] = building_id

func free_cells(cells: Array[Vector2i]) -> void:
    for cell: Vector2i in cells:
        _occupied.erase(cell)

func building_id_at(cell: Vector2i) -> String:
    return String(_occupied.get(cell, ""))
