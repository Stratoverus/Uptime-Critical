extends Node2D

signal heat_changed(new_heat: float)

@export var level: int = 1
@export var base_heat: float = 12.0
@export var heat_per_tps: float = 0.35
@export var heat_radius: float = 240.0
@export var back_local_direction: Vector2 = Vector2.RIGHT
@export var intake_local_direction: Vector2 = Vector2.LEFT
@export var airflow_rate: float = 1.0
@export var cooling_capacity: float = 0.0
@export var traffic_per_second: float = 0.0:
	set(value):
		traffic_per_second = max(value, 0.0)
		recalculate_heat()

var current_heat: float = 0.0

func _ready() -> void:
	add_to_group("heat_sources")
	recalculate_heat()
	notify_thermal_system_placed()

func _exit_tree() -> void:
	notify_thermal_system_removed()

func set_traffic_per_second(tps: float) -> void:
	traffic_per_second = tps

func get_heat_value() -> float:
	return current_heat

func get_heat_radius() -> float:
	return heat_radius

func get_back_direction() -> Vector2:
	var direction := back_local_direction.normalized().rotated(global_rotation)
	if direction.length() < 0.001:
		return Vector2.RIGHT
	return direction

func get_intake_direction() -> Vector2:
	var direction := intake_local_direction.normalized().rotated(global_rotation)
	if direction.length() < 0.001:
		return Vector2.LEFT
	return direction

func get_airflow_rate() -> float:
	return max(airflow_rate, 0.0)

func get_cooling_capacity() -> float:
	return max(cooling_capacity, 0.0)

func recalculate_heat() -> void:
	current_heat = base_heat + (traffic_per_second * heat_per_tps)
	heat_changed.emit(current_heat)

func get_thermal_system() -> Node:
	return get_tree().get_first_node_in_group("thermal_system")

func notify_thermal_system_placed() -> void:
	var thermal_system := get_thermal_system()
	if thermal_system != null and thermal_system.has_method("notify_structure_placed"):
		thermal_system.call("notify_structure_placed", self)

func notify_thermal_system_removed() -> void:
	var thermal_system := get_thermal_system()
	if thermal_system != null and thermal_system.has_method("notify_structure_removed"):
		thermal_system.call("notify_structure_removed", self)
