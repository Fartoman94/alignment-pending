extends Node

## Job assignment: a task template (WorkTaskCatalog) requires a compatible
## building (BuildGrid/BuildController-placed, referenced by stable id via
## GameState.buildings) and a compatible staff skill. Progress accrues from
## EventBus.simulation_tick, scaled by the assigned staff's relevant skill.

# building_id -> work_order id. Rebuilt from GameState.work_orders on
# _ready()/load, not persisted separately.
var _reserved_buildings: Dictionary = {}

func _ready() -> void:
    EventBus.simulation_tick.connect(_on_tick)
    EventBus.staff_roster_changed.connect(_reconcile_orphaned_orders)
    _rebuild_reservations()
    _sync_compute_used()

func _rebuild_reservations() -> void:
    _reserved_buildings.clear()
    for order: Dictionary in GameState.work_orders:
        _reserved_buildings[String(order.get("building_id", ""))] = String(order.get("id", ""))

## GameState.compute_used always equals compute reserved by active work
## orders — recomputed, never independently mutated.
func _sync_compute_used() -> void:
    var total: float = 0.0
    for order: Variant in GameState.work_orders:
        var task_def: Dictionary = WorkTaskCatalog.get_def(String((order as Dictionary).get("task_id", "")))
        total += float(task_def.get("compute_cost", 0.0))
    GameState.compute_used = total

func is_building_reserved(building_id: String) -> bool:
    return _reserved_buildings.has(building_id)

func _find_building(building_id: String) -> Dictionary:
    for b: Variant in GameState.buildings:
        var entry: Dictionary = b
        if String(entry.get("id", "")) == building_id:
            return entry
    return {}

## Buildings of the type a task needs that aren't already reserved by
## another work order.
func available_buildings_for_task(task_id: String) -> Array:
    var task_def: Dictionary = WorkTaskCatalog.get_def(task_id)
    if task_def.is_empty():
        return []
    var required: String = String(task_def.get("required_buildable", ""))
    var out: Array = []
    for b: Variant in GameState.buildings:
        var entry: Dictionary = b
        if String(entry.get("buildable_id", "")) == required and not is_building_reserved(String(entry.get("id", ""))):
            out.append(entry)
    return out

func can_assign(staff_id: String, task_id: String, building_id: String) -> bool:
    var staff: Dictionary = StaffManager.find(staff_id)
    if staff.is_empty() or not String(staff.get("assigned_task", "")).is_empty():
        return false
    var task_def: Dictionary = WorkTaskCatalog.get_def(task_id)
    if task_def.is_empty():
        return false
    if is_building_reserved(building_id):
        return false
    var building: Dictionary = _find_building(building_id)
    if building.is_empty() or String(building.get("buildable_id", "")) != String(task_def.get("required_buildable", "")):
        return false
    var required_skill: String = String(task_def.get("required_skill", ""))
    var skills: Dictionary = staff.get("skills", {})
    if int(skills.get(required_skill, 0)) <= 0:
        return false
    # Over-capacity blocks the job outright rather than letting
    # compute_used exceed the (heat-throttled) effective capacity.
    var compute_cost: float = float(task_def.get("compute_cost", 0.0))
    if compute_cost > 0.0 and compute_cost > GameState.effective_compute_capacity() - GameState.compute_used:
        return false
    return true

func assign(staff_id: String, task_id: String, building_id: String) -> Error:
    if not can_assign(staff_id, task_id, building_id):
        return ERR_INVALID_PARAMETER
    var order_id: String = "wo_%d" % GameState.next_work_order_id
    GameState.next_work_order_id += 1
    var order: Dictionary = {
        "id": order_id, "task_id": task_id, "staff_id": staff_id,
        "building_id": building_id, "progress_minutes": 0.0,
        "started_day": GameState.calendar_day,
    }
    GameState.work_orders.append(order)
    _reserved_buildings[building_id] = order_id
    _set_staff_field(staff_id, "assigned_task", order_id)
    _sync_compute_used()
    EventBus.task_assigned.emit(staff_id, building_id)
    return OK

## Cancels the in-progress work order for staff_id, if any (no-op otherwise).
func cancel(staff_id: String) -> Error:
    for order: Variant in GameState.work_orders:
        var entry: Dictionary = order
        if String(entry.get("staff_id", "")) == staff_id:
            GameState.work_orders.erase(entry)
            _reserved_buildings.erase(String(entry.get("building_id", "")))
            _set_staff_field(staff_id, "assigned_task", "")
            _sync_compute_used()
            EventBus.task_unassigned.emit(staff_id)
            return OK
    return ERR_DOES_NOT_EXIST

func find_order_for_staff(staff_id: String) -> Dictionary:
    for order: Variant in GameState.work_orders:
        var entry: Dictionary = order
        if String(entry.get("staff_id", "")) == staff_id:
            return entry
    return {}

func progress_fraction(order: Dictionary) -> float:
    var task_def: Dictionary = WorkTaskCatalog.get_def(String(order.get("task_id", "")))
    var duration: float = float(task_def.get("duration_minutes", 0.0))
    if duration <= 0.0:
        return 0.0
    return clampf(float(order.get("progress_minutes", 0.0)) / duration, 0.0, 1.0)

func _on_tick(minutes: int) -> void:
    if GameState.work_orders.is_empty():
        return
    var completed: Array = []
    for order: Variant in GameState.work_orders:
        var entry: Dictionary = order
        var staff_id: String = String(entry.get("staff_id", ""))
        var staff: Dictionary = StaffManager.find(staff_id)
        if staff.is_empty():
            completed.append(entry)
            continue
        var task_def: Dictionary = WorkTaskCatalog.get_def(String(entry.get("task_id", "")))
        var required_skill: String = String(task_def.get("required_skill", ""))
        var skills: Dictionary = staff.get("skills", {})
        var skill_value: int = int(skills.get(required_skill, 0))
        var multiplier: float = 0.5 + float(skill_value) / 100.0
        entry["progress_minutes"] = float(entry.get("progress_minutes", 0.0)) + float(minutes) * multiplier
        var duration: float = float(task_def.get("duration_minutes", 240.0))
        if float(entry["progress_minutes"]) >= duration:
            completed.append(entry)
    for entry: Dictionary in completed:
        _complete_order(entry)

func _complete_order(order: Dictionary) -> void:
    var staff_id: String = String(order.get("staff_id", ""))
    var building_id: String = String(order.get("building_id", ""))
    var task_id: String = String(order.get("task_id", ""))
    GameState.work_orders.erase(order)
    _reserved_buildings.erase(building_id)
    _set_staff_field(staff_id, "assigned_task", "")
    _sync_compute_used()
    EventBus.task_completed.emit(staff_id, task_id)

func _reconcile_orphaned_orders() -> void:
    var valid_ids: Dictionary = {}
    for member: Variant in GameState.staff:
        valid_ids[String((member as Dictionary).get("id", ""))] = true
    var to_remove: Array = []
    for order: Variant in GameState.work_orders:
        var entry: Dictionary = order
        if not valid_ids.has(String(entry.get("staff_id", ""))):
            to_remove.append(entry)
    for entry: Dictionary in to_remove:
        var staff_id: String = String(entry.get("staff_id", ""))
        GameState.work_orders.erase(entry)
        _reserved_buildings.erase(String(entry.get("building_id", "")))
        _sync_compute_used()
        EventBus.task_unassigned.emit(staff_id)

func _set_staff_field(staff_id: String, field: String, value: Variant) -> void:
    for member: Variant in GameState.staff:
        var entry: Dictionary = member
        if String(entry.get("id", "")) == staff_id:
            entry[field] = value
            return
