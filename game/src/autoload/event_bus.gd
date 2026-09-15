extends Node

signal metric_changed(metric: StringName, value: float)
signal incident_raised(incident_id: StringName)
signal selection_changed(kind: StringName, entity_id: String)
signal simulation_pause_changed(paused: bool)
signal day_advanced(day: int)
