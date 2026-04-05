extends InteractableObject

@export var level: int = 1
@export var max_electrical_connections: int = 1
@export var electrical_node_offset: Vector2 = Vector2(0, -20)

var current_facing: String = "front"
var is_connected_to_network: bool = false
var cable_mode_highlight_on: bool = false
var connected_segments: Array = []
var electrical_node: Node2D = null
var network_node_type := "router"
var port_label: Label = null
# set below to 8 
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

var upgrade_costs = {
	1: 250,
	2: 350
}

func update_actions() -> void:
	if level >= 3:
		actions = ["Turn Off", "Turn On"]
	else:
		var cost = upgrade_costs.get(level, 0)
		actions = [
			"Turn Off",
			"Turn On",
			"Upgrade ($" + str(cost) + ")"
		]

func _ready() -> void:
	add_to_group("network_nodes")
	add_to_group("electrical_connectable")
	object_name = "Router L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()
	_ensure_electrical_node()
	_ensure_port_label()
	_update_port_label()

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

	_update_electrical_node_position()

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
		object_name = "Router L" + str(level)
		update_actions()

		set_facing(current_facing)
		_update_port_label()

func set_network_connected_state(connected: bool) -> void:
	is_connected_to_network = connected
	_update_cable_mode_visual()

func set_cable_mode_highlight(enabled: bool) -> void:
	cable_mode_highlight_on = enabled
	_update_cable_mode_visual()

func _update_cable_mode_visual() -> void:
	if not sprite:
		return

	if not cable_mode_highlight_on:
		sprite.modulate = Color(1, 1, 1, 1)
		return

	# Simple highlight only (no connection logic)
	sprite.modulate = Color(1.1, 1.1, 0.8, 1.0)

func add_connection(segment) -> void:
	if not connected_segments.has(segment):
		connected_segments.append(segment)
		_update_port_label()

func remove_connection(segment) -> void:
	connected_segments.erase(segment)
	_update_port_label()

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
		connection_count = 0

	return connection_count < max(0, max_electrical_connections)

func _ensure_electrical_node() -> void:
	electrical_node = get_node_or_null("ElectricalNode") as Node2D
	if electrical_node == null:
		electrical_node = Node2D.new()
		electrical_node.name = "ElectricalNode"
		add_child(electrical_node)

	_update_electrical_node_position()

func _update_electrical_node_position() -> void:
	if electrical_node == null:
		return
	electrical_node.position = electrical_node_offset
