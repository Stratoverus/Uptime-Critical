extends InteractableObject

@export var base_heat: float = 15.0  # Represents ~30°C idle temperature
@export var heat_radius: float = 260.0
@export var back_local_direction: Vector2 = Vector2.UP
@export var intake_local_direction: Vector2 = Vector2.DOWN
@export var airflow_rate: float = 1.0
@export var cooling_capacity: float = 0.0
@export var level: int = 1

var current_facing: String = "front"
var is_connected_to_network: bool = false
var cable_mode_highlight_on: bool = false
var connected_segments: Array = []
var electrical_connected_segments: Array = []
var network_node_type := "server"
var is_network_online := false
var is_powered := false
var electrical_node_left: Node2D = null
var electrical_node_right: Node2D = null
var power_status_lights: Array[Node] = []

var sprites_by_level = {
	1: {
		"front": preload("res://assets/object_sprites/servers/server_rack_1_front.png"),
		"right": preload("res://assets/object_sprites/servers/server_rack_1_right.png"),
		"back": preload("res://assets/object_sprites/servers/server_rack_1_back.png"),
		"left": preload("res://assets/object_sprites/servers/server_rack_1_left.png")
	},
	2: {
		"front": preload("res://assets/object_sprites/servers/server_rack_2_front.png"),
		"right": preload("res://assets/object_sprites/servers/server_rack_2_right.png"),
		"back": preload("res://assets/object_sprites/servers/server_rack_2_back.png"),
		"left": preload("res://assets/object_sprites/servers/server_rack_2_left.png")
	},
	3: {
		"front": preload("res://assets/object_sprites/servers/server_rack_3_front.png"),
		"right": preload("res://assets/object_sprites/servers/server_rack_3_right.png"),
		"back": preload("res://assets/object_sprites/servers/server_rack_3_back.png"),
		"left": preload("res://assets/object_sprites/servers/server_rack_3_left.png")
	}
}

var upgrade_costs = {
	1: 200,
	2: 300
}

func update_actions() -> void:
	if level >= 3:
		actions = ["Turn Off", "Turn On"]
	else:
		var cost = upgrade_costs.get(level, 0)
		actions = [
			"Turn Off",
			"Turn On",
			"Upgrade $" + str(cost)
		]

func _ready() -> void:
	add_to_group("network_nodes")
	add_to_group("electrical_connectable")
	object_name = "Server Rack L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()
	_ensure_electrical_nodes()
	_collect_power_status_lights()
	_sync_power_status_lights()
	add_to_group("heat_sources")
	notify_thermal_system_placed()

func _exit_tree() -> void:
	notify_thermal_system_removed()

func get_heat_value() -> float:
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
	return max(airflow_rate, 0.0)

func get_cooling_capacity() -> float:
	return max(cooling_capacity, 0.0)

func set_facing(direction: String) -> void:
	current_facing = direction

	if sprites_by_level.has(level):
		var sprites = sprites_by_level[level]

		if sprites.has(direction):
			sprite.texture = sprites[direction]
		else:
			push_warning("Missing direction: %s" % direction)
	else:
		push_warning("Missing level: %s" % level)

func perform_action(action_name: String) -> void:
	if action_name == "Turn Off":
		turn_off()
	elif action_name == "Turn On":
		turn_on()
	elif action_name.begins_with("Upgrade"):
		upgrade()
	else:
		super.perform_action(action_name)

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func upgrade() -> void:
	if level >= 3:
		return

	var cost = upgrade_costs.get(level, 0)
	var game = get_tree().get_first_node_in_group("hud")

	if game and game.can_afford(cost):
		game.spend_money(cost)

		level += 1
		object_name = "Server Rack L" + str(level)
		update_actions()
		set_facing(current_facing)

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

func set_network_connected_state(connected: bool) -> void:
	is_connected_to_network = connected
	_apply_visual_state()

func set_cable_mode_highlight(enabled: bool) -> void:
	cable_mode_highlight_on = enabled
	_apply_visual_state()

func _update_cable_mode_visual() -> void:
	_apply_visual_state()

func add_connection(segment) -> void:
	if not connected_segments.has(segment):
		connected_segments.append(segment)

func remove_connection(segment) -> void:
	connected_segments.erase(segment)

func add_electrical_connection(connection_target) -> void:
	if not electrical_connected_segments.has(connection_target):
		electrical_connected_segments.append(connection_target)

func remove_electrical_connection(connection_target) -> void:
	electrical_connected_segments.erase(connection_target)

func get_electrical_nodes() -> Array[Node2D]:
	_ensure_electrical_nodes()
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node_left):
		nodes.append(electrical_node_left)
	if is_instance_valid(electrical_node_right):
		nodes.append(electrical_node_right)
	return nodes

func can_accept_electrical_connection(connector_node: Node2D, current_connection_count: int = -1) -> bool:
	_ensure_electrical_nodes()
	if connector_node == null:
		return false
	if connector_node != electrical_node_left and connector_node != electrical_node_right:
		return false

	var connection_count: int = current_connection_count
	if connection_count < 0:
		connection_count = 0

	# Each server electrical connector is single-port.
	return connection_count < 1

func _ensure_electrical_nodes() -> void:
	electrical_node_left = _ensure_single_electrical_node("ElectricalNodeLeft", Vector2(-36, -16))
	electrical_node_right = _ensure_single_electrical_node("ElectricalNodeRight", Vector2(36, -16))

func _ensure_single_electrical_node(node_name: String, node_position: Vector2) -> Node2D:
	var existing_node := get_node_or_null(node_name) as Node2D
	if existing_node != null:
		return existing_node

	var connector_node := Node2D.new()
	connector_node.name = node_name
	connector_node.position = node_position
	add_child(connector_node)
	return connector_node

func update_network_status(connected: bool) -> void:
	is_network_online = connected
	_apply_visual_state()

func set_powered_state(powered: bool) -> void:
	if is_powered == powered:
		return
	is_powered = powered
	_sync_power_status_lights()
	_apply_visual_state()

func _update_network_visual() -> void:
	_apply_visual_state()

func _apply_visual_state() -> void:
	if not sprite:
		return

	if not is_powered:
		sprite.modulate = Color(0.45, 0.45, 0.45, 1.0)
		return

	if not cable_mode_highlight_on:
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return

	# Only in network overlay mode: connected racks stay bright, disconnected racks dim.
	if is_network_online:
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		sprite.modulate = Color(0.45, 0.45, 0.45, 1.0)


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