extends Node2D

signal heat_changed(new_heat: float)

@export var level: int = 1
@export var base_heat: float = 12.0
@export var heat_per_tps: float = 0.35
@export var heat_radius: float = 240.0
@export var back_local_direction: Vector2 = Vector2.RIGHT
@export var traffic_per_second: float = 0.0:
	set(value):
		traffic_per_second = max(value, 0.0)
		recalculate_heat()

var current_heat: float = 0.0

func _ready() -> void:
	add_to_group("heat_sources")
	recalculate_heat()

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

func recalculate_heat() -> void:
	current_heat = base_heat + (traffic_per_second * heat_per_tps)
	heat_changed.emit(current_heat)
