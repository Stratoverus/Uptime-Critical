extends Node2D
class_name ThermalSource

signal heat_changed(new_heat: float)

@export var level: int = 1
@export var source_type: StringName = &"generic"
@export var base_heat: float = 0.0
@export var heat_per_tps: float = 0.0
@export var heat_radius: float = 240.0
@export var back_local_direction: Vector2 = Vector2.UP
@export var intake_local_direction: Vector2 = Vector2.DOWN
@export var airflow_rate: float = 1.0
@export var cooling_capacity: float = 0.0
@export var traffic_per_second: float = 0.0:
	set(value):
		traffic_per_second = max(value, 0.0)
		recalculate_heat()
@export var load_multiplier: float = 1.0
@export var power_multiplier: float = 1.0
@export var efficiency_multiplier: float = 1.0
@export var source_enabled: bool = true
@export_range(0, 3, 1) var visual_cardinal_offset: int = 0

var current_heat: float = 0.0
var _visual_sprite: Sprite2D = null
var _last_visual_direction: StringName = &""
var _texture_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("heat_sources")
	set_notify_transform(true)
	_visual_sprite = _find_visual_sprite()
	recalculate_heat()
	update_directional_visual(true)
	notify_thermal_system_placed()

func _exit_tree() -> void:
	notify_thermal_system_removed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_directional_visual(false)

func set_traffic_per_second(tps: float) -> void:
	traffic_per_second = max(tps, 0.0)
	recalculate_heat()

func set_operational_multipliers(load_value: float, power_value: float, efficiency_value: float) -> void:
	load_multiplier = max(load_value, 0.0)
	power_multiplier = max(power_value, 0.0)
	efficiency_multiplier = max(efficiency_value, 0.0)
	recalculate_heat()

func set_source_enabled(enabled: bool) -> void:
	source_enabled = enabled
	recalculate_heat()

func get_heat_value() -> float:
	return current_heat

func get_heat_radius() -> float:
	return max(heat_radius, 1.0)

func get_back_direction() -> Vector2:
	var direction := back_local_direction.normalized().rotated(global_rotation)
	if direction.length() < 0.001:
		return Vector2.UP
	return direction

func get_intake_direction() -> Vector2:
	var direction := intake_local_direction.normalized().rotated(global_rotation)
	if direction.length() < 0.001:
		return Vector2.DOWN
	return direction

func get_airflow_rate() -> float:
	return max(airflow_rate, 0.0)

func get_cooling_capacity() -> float:
	return max(cooling_capacity, 0.0)

func get_heat_source_type() -> StringName:
	return source_type

func recalculate_heat() -> void:
	if not source_enabled:
		current_heat = 0.0
		heat_changed.emit(current_heat)
		return

	var multiplier: float = max(load_multiplier * power_multiplier * efficiency_multiplier, 0.0)
	current_heat = (base_heat + (traffic_per_second * heat_per_tps)) * multiplier
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

func get_directional_texture_prefix() -> String:
	return ""

func update_directional_visual(force: bool) -> void:
	if _visual_sprite == null:
		return

	var texture_prefix: String = get_directional_texture_prefix()
	if texture_prefix.is_empty():
		return

	var direction_name: StringName = _rotation_to_cardinal_name(global_rotation)
	if not force and direction_name == _last_visual_direction:
		return

	var texture_path: String = "%s_%s.png" % [texture_prefix, String(direction_name)]
	var texture: Texture2D = _load_cached_texture(texture_path)
	if texture != null:
		_visual_sprite.texture = texture
		_last_visual_direction = direction_name

func _load_cached_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D

	if not ResourceLoader.exists(path):
		return null

	var loaded := load(path)
	if loaded is Texture2D:
		_texture_cache[path] = loaded
		return loaded

	return null

func _find_visual_sprite() -> Sprite2D:
	for child in get_children():
		if child is Sprite2D:
			return child as Sprite2D
	return null

func _rotation_to_cardinal_name(angle_radians: float) -> StringName:
	var normalized: float = fposmod(angle_radians, TAU)
	var quarter_turns: int = int(round(normalized / (PI * 0.5))) % 4
	quarter_turns = (quarter_turns + visual_cardinal_offset) % 4
	match quarter_turns:
		0:
			return &"front"
		1:
			return &"right"
		2:
			return &"back"
		_:
			return &"left"
