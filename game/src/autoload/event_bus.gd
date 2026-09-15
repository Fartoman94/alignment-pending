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
## target_id is an optional task-specific reference (e.g. a research node
## id for a research_sprint work order); "" when not applicable.
signal task_assigned(staff_id: String, building_id: String, target_id: String)
signal task_completed(staff_id: String, task_id: String, target_id: String)
signal task_unassigned(staff_id: String)
signal research_unlocked(node_id: String)
signal model_created(model_id: String)
signal deployment_changed(deployment_id: String)
signal rival_launched(generation: int)
