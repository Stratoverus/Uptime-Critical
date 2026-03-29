extends "res://scripts/systems/thermal_source.gd"

func _ready() -> void:
	if source_type == &"generic":
		source_type = &"cooler"
	if cooling_capacity <= 0.0:
		cooling_capacity = 24.0  # Default fallback if scene does not set capacity
	if airflow_rate <= 0.0:
		airflow_rate = 1.4
	if base_heat > 0.0:
		base_heat = 0.0
	if heat_per_tps != 0.0:
		heat_per_tps = 0.0
	super._ready()

func get_directional_texture_prefix() -> String:
	var safe_level: int = max(level, 1)
	return "res://assets/object_sprites/coolingRacks/cooling_rack_%d" % safe_level