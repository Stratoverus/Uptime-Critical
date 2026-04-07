# extends "res://scripts/systems/thermal_source.gd"
extends InteractableObject
@export var level: int = 1
@export var base_heat: float = 0.0
@export var heat_radius: float = 260.0
@export var back_local_direction: Vector2 = Vector2.UP
@export var intake_local_direction: Vector2 = Vector2.DOWN
@export var airflow_rate: float = 1.35
@export var cooling_capacity: float = 40.0
@export var overdrive_cooling_multiplier: float = 1.75
@export var overdrive_power_multiplier: float = 2.5
@export var max_electrical_connections: int = 1
@export var electrical_node_offset: Vector2 = Vector2(0, -20)
@export var upgrade_cost_l1_to_l2: int = 200
@export var upgrade_cost_l2_to_l3: int = 300

var current_facing: String = "front"
var is_manually_enabled: bool = true
var is_powered: bool = false
var is_overdrive_enabled: bool = false
var electrical_connected_segments: Array = []
var electrical_node: Node2D = null
var power_status_lights: Array[Node] = []
var visual_state_initialized: bool = false
var last_visual_active_state: bool = false
var sprites_by_level = {
	1: {
		"front": preload("res://assets/object_sprites/coolingRacks/cooling_rack_1_front.png"),
		"right": preload("res://assets/object_sprites/coolingRacks/cooling_rack_1_right.png"),
		"back": preload("res://assets/object_sprites/coolingRacks/cooling_rack_1_back.png"),
		"left": preload("res://assets/object_sprites/coolingRacks/cooling_rack_1_left.png")
	},
	2: {
		"front": preload("res://assets/object_sprites/coolingRacks/cooling_rack_2_front.png"),
		"right": preload("res://assets/object_sprites/coolingRacks/cooling_rack_2_right.png"),
		"back": preload("res://assets/object_sprites/coolingRacks/cooling_rack_2_back.png"),
		"left": preload("res://assets/object_sprites/coolingRacks/cooling_rack_2_left.png")
	},
	3: {
		"front": preload("res://assets/object_sprites/coolingRacks/cooling_rack_3_front.png"),
		"right": preload("res://assets/object_sprites/coolingRacks/cooling_rack_3_right.png"),
		"back": preload("res://assets/object_sprites/coolingRacks/cooling_rack_3_back.png"),
		"left": preload("res://assets/object_sprites/coolingRacks/cooling_rack_3_left.png")
	}
}

func update_actions() -> void:
	actions = []
	if is_manually_enabled:
		actions.append("Turn Off")
	else:
		actions.append("Turn On")

	if level >= 3:
		actions.append("Inspect")
	else:
		var cost := _get_upgrade_cost(level)
		actions.append("Inspect")
		actions.append("Upgrade $" + str(cost))

	if is_overdrive_enabled:
		actions.append("Disable Overdrive")
	else:
		actions.append("Enable Overdrive")

func _ready() -> void:
	add_to_group("electrical_connectable")
	add_to_group("cooling_units")
	object_name = "Cooling Rack L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()
	_ensure_electrical_node()
	_collect_power_status_lights()
	_sync_power_status_lights()
	add_to_group("heat_sources")
	notify_thermal_system_placed()
	_apply_visual_state()

func _exit_tree() -> void:
	notify_thermal_system_removed()

func get_heat_value() -> float:
	if not _is_active():
		return 0.0
	return base_heat

func get_heat_radius() -> float:
	return heat_radius

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
	if not _is_active():
		return 0.0
	return max(airflow_rate, 0.0)

func get_cooling_capacity() -> float:
	if not _is_active():
		return 0.0
	var multiplier: float = overdrive_cooling_multiplier if is_overdrive_enabled else 1.0
	return max(cooling_capacity * multiplier, 0.0)

func get_heat_source_type() -> StringName:
	return &"cooler"

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

func set_facing(direction: String) -> void:
	current_facing = direction
	apply_facing_rotation(direction)

	if sprites_by_level.has(level):
		var sprites = sprites_by_level[level]

		if sprites.has(direction):
			sprite.texture = sprites[direction]
		else:
			push_warning("Missing direction: %s" % direction)
	else:
		push_warning("Missing level: %s" % level)

	_update_electrical_node_position()
	_apply_visual_state()

func perform_action(action_name: String) -> void:
	if action_name == "Turn Off":
		turn_off()
	elif action_name == "Turn On":
		turn_on()
	elif action_name == "Enable Overdrive":
		enable_overdrive()
	elif action_name == "Disable Overdrive":
		disable_overdrive()
	elif action_name == "Inspect":
		inspect()
	elif action_name.begins_with("Upgrade"):
		upgrade()
	else:
		super.perform_action(action_name)

func turn_off() -> void:
	is_manually_enabled = false
	is_overdrive_enabled = false
	update_actions()
	_apply_visual_state()

func turn_on() -> void:
	is_manually_enabled = true
	update_actions()
	_apply_visual_state()

func enable_overdrive() -> void:
	if not _is_active():
		show_top_alert("Cannot enable overdrive while cooler is offline.")
		return
	is_overdrive_enabled = true
	update_actions()
	_apply_visual_state()

func disable_overdrive() -> void:
	is_overdrive_enabled = false
	update_actions()
	_apply_visual_state()

func is_overdrive_active() -> bool:
	return _is_active() and is_overdrive_enabled

func get_overdrive_power_multiplier() -> float:
	if not is_overdrive_active():
		return 1.0
	return max(overdrive_power_multiplier, 1.0)

func inspect() -> void:
	pass

func upgrade() -> void:
	if level >= 3:
		return

	var cost := _get_upgrade_cost(level)
	if GameManager != null and GameManager.can_afford(cost):
		GameManager.spend_money(cost)

		level += 1
		object_name = "Cooling Rack L" + str(level)
		update_actions()
		set_facing(current_facing)

func _get_upgrade_cost(from_level: int) -> int:
	var fallback_cost: int = upgrade_cost_l1_to_l2 if from_level == 1 else upgrade_cost_l2_to_l3 if from_level == 2 else 0
	var economy_config: Node = get_node_or_null("/root/EconomyConfig")
	if economy_config != null and economy_config.has_method("get_upgrade_cost"):
		return int(economy_config.call("get_upgrade_cost", "cooling", from_level, fallback_cost))
	return fallback_cost

func get_electrical_nodes() -> Array[Node2D]:
	_ensure_electrical_node()
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node):
		nodes.append(electrical_node)
	return nodes

func can_accept_electrical_connection(connector_node: Node2D, current_connection_count: int = -1) -> bool:
	_ensure_electrical_node()
	if connector_node == null or connector_node != electrical_node:
		return false

	var connection_count: int = current_connection_count
	if connection_count < 0:
		connection_count = electrical_connected_segments.size()

	return connection_count < max(0, max_electrical_connections)

func add_electrical_connection(connection_target) -> void:
	if not electrical_connected_segments.has(connection_target):
		electrical_connected_segments.append(connection_target)

func remove_electrical_connection(connection_target) -> void:
	electrical_connected_segments.erase(connection_target)

func set_powered_state(powered: bool) -> void:
	if is_powered == powered:
		return
	is_powered = powered
	_sync_power_status_lights()
	_apply_visual_state()

func _update_cable_mode_visual() -> void:
	_apply_visual_state()

func _apply_visual_state() -> void:
	if not sprite:
		return

	var active_state: bool = _is_active()
	var target_modulate: Color = Color(1.0, 1.0, 1.0, 1.0) if active_state else Color(0.45, 0.45, 0.45, 1.0)
	if active_state and is_overdrive_enabled:
		target_modulate = Color(1.0, 0.92, 0.75, 1.0)
	var should_animate_power_change: bool = visual_state_initialized and (last_visual_active_state != active_state)
	set_sprite_modulate(target_modulate, power_fade_duration_sec if should_animate_power_change else 0.0)

	last_visual_active_state = active_state
	visual_state_initialized = true

func _is_active() -> bool:
	return is_manually_enabled and is_powered

func _ensure_electrical_node() -> void:
	electrical_node = get_node_or_null("ElectricalNode") as Node2D
	if electrical_node == null:
		electrical_node = Node2D.new()
		electrical_node.name = "ElectricalNode"
		add_child(electrical_node)

	_update_electrical_node_position()

func _collect_power_status_lights() -> void:
	power_status_lights.clear()
	for child in find_children("*", "Node", true, false):
		if child == null:
			continue
		if child.has_method("set_powered") and child.has_method("set_light_color"):
			power_status_lights.append(child)

func _sync_power_status_lights() -> void:
	if power_status_lights.is_empty():
		return

	for light_node in power_status_lights:
		if light_node == null:
			continue
		if light_node.has_method("set_powered"):
			light_node.call("set_powered", is_powered)

func _update_electrical_node_position() -> void:
	if electrical_node == null:
		return
	electrical_node.position = electrical_node_offset
