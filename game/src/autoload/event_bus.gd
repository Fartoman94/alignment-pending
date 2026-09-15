extends Node

signal metric_changed(metric: StringName, value: float)
signal incident_raised(incident_id: StringName)
signal selection_changed(kind: StringName, entity_id: String)
signal simulation_pause_changed(paused: bool)
signal day_advanced(day: int)
## tool_id is a BuildableCatalog id to start placing, "sell" for sell mode,
## or "" to cancel/exit build mode.
signal build_tool_changed(tool_id: String)
signal staff_roster_changed()
## Fires every SimClock logical tick with the number of simulated minutes
## that just elapsed. GameState.paused/SimClock.active already gate this.
signal simulation_tick(minutes: int)
signal task_assigned(staff_id: String, building_id: String)
signal task_completed(staff_id: String, task_id: String)
signal task_unassigned(staff_id: String)
