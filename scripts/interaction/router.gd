extends InteractableObject

@export var level: int = 1
@export var max_electrical_connections: int = 1
@export var electrical_node_offset: Vector2 = Vector2(0, 22)
@export var internet_node_offset: Vector2 = Vector2(26, 22)
@export_range(1, 64, 1) var max_network_ports: int = 8
@export var upgrade_cost_l1_to_l2: int = 250
@export var upgrade_cost_l2_to_l3: int = 350

var current_facing: String = "front"
var is_connected_to_network: bool = false
var cable_mode_highlight_on: bool = false
var is_manually_enabled: bool = true
var is_powered: bool = false
var connected_segments: Array = []
var internet_connected_segments: Array = []
var electrical_connected_segments: Array = []
var electrical_node: Node2D = null
var internet_node: Node2D = null
var network_node_type := "router"
var port_label: Label = null
var power_status_lights: Array[Node] = []
var traffic_status_lights: Array[Node] = []
var traffic_load_units: float = 0.0
var visual_state_initialized: bool = false
var last_visual_active_state: bool = false
var port_limits = {
	1: 8,
	2: 12,
	3: 16
}

var sprites_by_level = {
	1: {
		"front": preload("res://assets/object_sprites/routers/router_1_front.png"),
		"right": preload("res://assets/object_sprites/routers/router_1_right.png"),
		"back": preload("res://assets/object_sprites/routers/router_1_back.png"),
		"left": preload("res://assets/object_sprites/routers/router_1_left.png")
	},
	2: {
		"front": preload("res://assets/object_sprites/routers/router_2_front.png"),
		"right": preload("res://assets/object_sprites/routers/router_2_right.png"),
		"back": preload("res://assets/object_sprites/routers/router_2_back.png"),
		"left": preload("res://assets/object_sprites/routers/router_2_left.png")
	},
	3: {
		"front": preload("res://assets/object_sprites/routers/router_3_front.png"),
		"right": preload("res://assets/object_sprites/routers/router_3_right.png"),
		"back": preload("res://assets/object_sprites/routers/router_3_back.png"),
		"left": preload("res://assets/object_sprites/routers/router_3_left.png")
	}
}

func update_actions() -> void:
	actions = []
	if is_manually_enabled:
		actions.append("Turn Off")
	else:
		actions.append("Turn On")

	if level >= 3:
		return
	else:
		var cost := _get_upgrade_cost(level)
		actions.append("Upgrade ($" + str(cost) + ")")

func _ready() -> void:
	add_to_group("network_nodes")
	add_to_group("electrical_connectable")
	object_name = "Router L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()
	_ensure_network_nodes()
	_collect_power_status_lights()
	_sync_power_status_lights()
	_collect_traffic_status_lights()
	_sync_traffic_status_lights()
	_ensure_port_label()
	_update_port_label()
	_apply_visual_state()

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
	_update_internet_node_position()

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
	is_manually_enabled = false
	update_actions()
	_apply_visual_state()

func turn_on() -> void:
	is_manually_enabled = true
	update_actions()
	_apply_visual_state()

func upgrade() -> void:
	if level >= 3:
		return

	var cost := _get_upgrade_cost(level)

	if GameManager != null and GameManager.can_afford(cost):
		GameManager.spend_money(cost)

		level += 1
		object_name = "Router L" + str(level)
		update_actions()

		set_facing(current_facing)
		_update_port_label()
		_sync_traffic_status_lights()

func _get_upgrade_cost(from_level: int) -> int:
	var fallback_cost: int = upgrade_cost_l1_to_l2 if from_level == 1 else upgrade_cost_l2_to_l3 if from_level == 2 else 0
	var economy_config: Node = get_node_or_null("/root/EconomyConfig")
	if economy_config != null and economy_config.has_method("get_upgrade_cost"):
		return int(economy_config.call("get_upgrade_cost", "router", from_level, fallback_cost))
	return fallback_cost

func is_available_for_routing() -> bool:
	return _is_active() and is_connected_to_network

func get_capacity_units() -> int:
	return 1

func set_network_connected_state(connected: bool) -> void:
	is_connected_to_network = connected
	_update_cable_mode_visual()

func set_cable_mode_highlight(enabled: bool) -> void:
	cable_mode_highlight_on = enabled
	_update_cable_mode_visual()

func _update_cable_mode_visual() -> void:
	if not sprite:
		return

	var active_state: bool = _is_active()
	var target_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)
	if not active_state:
		target_modulate = Color(0.45, 0.45, 0.45, 1.0)
	elif cable_mode_highlight_on:
		# Simple highlight only (no connection logic)
		target_modulate = Color(1.1, 1.1, 0.8, 1.0)

	var should_animate_power_change: bool = visual_state_initialized and (last_visual_active_state != active_state)
	set_sprite_modulate(target_modulate, power_fade_duration_sec if should_animate_power_change else 0.0)

	last_visual_active_state = active_state
	visual_state_initialized = true

func add_connection(segment) -> void:
	add_connection_for_node(segment, electrical_node)

func remove_connection(segment) -> void:
	remove_connection_for_node(segment, electrical_node)

func add_connection_for_node(segment, connector_node: Node2D) -> void:
	_ensure_network_nodes()
	if connector_node == internet_node:
		if not internet_connected_segments.has(segment):
			internet_connected_segments.append(segment)
		return

	if connector_node == electrical_node:
		if not connected_segments.has(segment):
			connected_segments.append(segment)
			_recalculate_traffic_load_from_connections()
			_update_port_label()
			_sync_traffic_status_lights()

func remove_connection_for_node(segment, connector_node: Node2D) -> void:
	_ensure_network_nodes()
	if connector_node == internet_node:
		internet_connected_segments.erase(segment)
		return

	if connector_node == electrical_node:
		connected_segments.erase(segment)
		_recalculate_traffic_load_from_connections()
		_update_port_label()
		_sync_traffic_status_lights()

func has_free_port() -> bool:
	return connected_segments.size() < get_port_limit()

func get_port_limit() -> int:
	return port_limits.get(level, 8)

func _ensure_port_label() -> void:
	if port_label != null and is_instance_valid(port_label):
		return

	port_label = get_node_or_null("PortLabel") as Label
	if port_label == null:
		port_label = Label.new()
		port_label.name = "PortLabel"
		port_label.position = Vector2(-18, -46)
		port_label.size = Vector2(54, 20)
		port_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		port_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		port_label.z_index = 20
		port_label.visible = false
		add_child(port_label)

func _update_port_label() -> void:
	_ensure_port_label()
	if port_label == null:
		return

	port_label.text = "%d/%d" % [connected_segments.size(), get_port_limit()]

func set_port_label_visible(show_label: bool) -> void:
	_ensure_port_label()
	if port_label != null:
		port_label.visible = show_label

func get_electrical_nodes() -> Array[Node2D]:
	_ensure_network_nodes()
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node):
		nodes.append(electrical_node)
	return nodes

func get_network_nodes() -> Array[Node2D]:
	_ensure_network_nodes()
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node):
		nodes.append(electrical_node)
	if is_instance_valid(internet_node):
		nodes.append(internet_node)
	return nodes

func can_accept_network_connection(connector_node: Node2D, remote_owner: Node = null, remote_connector: Node2D = null, current_connection_count: int = -1) -> bool:
	_ensure_network_nodes()
	if connector_node == null:
		return false

	var connection_count := current_connection_count
	if connector_node == internet_node:
		if connection_count < 0:
			connection_count = internet_connected_segments.size()
		# Allow selecting this node as a wire start endpoint before the remote is chosen.
		if remote_owner == null:
			return connection_count < 1
		if remote_owner == null or not remote_owner.has_method("get_network_port_type"):
			return false
		var remote_type: String = str(remote_owner.call("get_network_port_type", remote_connector))
		if remote_type != "internet_source":
			return false
		return connection_count < 1

	if connector_node == electrical_node:
		if connection_count < 0:
			connection_count = connected_segments.size()
		if remote_owner == null:
			return connection_count < get_port_limit()
		if remote_owner != null and remote_owner.has_method("get_network_port_type"):
			var remote_type: String = str(remote_owner.call("get_network_port_type", remote_connector))
			if remote_type == "internet_source" or remote_type == "internet":
				return false
		return connection_count < get_port_limit()

	return false

func get_network_port_type(connector_node: Node2D) -> String:
	_ensure_network_nodes()
	if connector_node == internet_node:
		return "internet"
	if connector_node == electrical_node:
		return "server"
	return ""

func get_network_port_icon(connector_node: Node2D) -> String:
	match get_network_port_type(connector_node):
		"internet":
			return "🌐"
		"server":
			return ""
		_:
			return ""

func get_electrical_port_icon(connector_node: Node2D) -> String:
	_ensure_network_nodes()
	if connector_node == electrical_node:
		return "⚡"
	return ""

func can_accept_electrical_connection(connector_node: Node2D, current_connection_count: int = -1) -> bool:
	_ensure_network_nodes()
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
	_sync_traffic_status_lights()
	_apply_visual_state()

func set_network_traffic_load(load_units: float) -> void:
	traffic_load_units = max(load_units, 0.0)
	_sync_traffic_status_lights()

func set_network_traffic_ratio(ratio: float) -> void:
	set_network_traffic_load(clamp(ratio, 0.0, 1.0))

func get_network_load_ratio() -> float:
	return clamp(traffic_load_units, 0.0, 1.0)

func _apply_visual_state() -> void:
	_update_cable_mode_visual()

func _is_active() -> bool:
	return is_manually_enabled and is_powered

func _ensure_network_nodes() -> void:
	electrical_node = get_node_or_null("ElectricalNode") as Node2D
	if electrical_node == null:
		electrical_node = Node2D.new()
		electrical_node.name = "ElectricalNode"
		add_child(electrical_node)

	internet_node = get_node_or_null("InternetNode") as Node2D
	if internet_node == null:
		internet_node = Node2D.new()
		internet_node.name = "InternetNode"
		add_child(internet_node)

	_update_electrical_node_position()
	_update_internet_node_position()

func _collect_power_status_lights() -> void:
	power_status_lights.clear()
	for child in find_children("PowerStatusLight", "Node", true, false):
		if child == null:
			continue
		if child.has_method("set_powered") and child.has_method("set_light_color"):
			power_status_lights.append(child)

func _collect_traffic_status_lights() -> void:
	traffic_status_lights.clear()
	for child in find_children("TrafficStatusLight", "Node", true, false):
		if child == null:
			continue
		if child.has_method("set_powered") and child.has_method("set_load_ratio"):
			traffic_status_lights.append(child)

func _recalculate_traffic_load_from_connections() -> void:
	traffic_load_units = float(connected_segments.size())

func _sync_power_status_lights() -> void:
	if power_status_lights.is_empty():
		return

	for light_node in power_status_lights:
		if light_node == null:
			continue
		if light_node.has_method("set_powered"):
			light_node.call("set_powered", is_powered)

func _sync_traffic_status_lights() -> void:
	if traffic_status_lights.is_empty():
		return

	var load_ratio: float = get_network_load_ratio()
	for light_node in traffic_status_lights:
		if light_node == null:
			continue
		if light_node.has_method("set_powered"):
			light_node.call("set_powered", is_powered)
		if light_node.has_method("set_load_ratio"):
			light_node.call("set_load_ratio", load_ratio)

func _update_electrical_node_position() -> void:
	if electrical_node == null:
		return
	electrical_node.position = electrical_node_offset

func _update_internet_node_position() -> void:
	if internet_node == null:
		return
	internet_node.position = internet_node_offset
