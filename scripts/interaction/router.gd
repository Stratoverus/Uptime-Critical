extends InteractableObject

@export var level: int = 1

var current_facing: String = "front"
var is_connected_to_network: bool = false
var cable_mode_highlight_on: bool = false
var connected_segments: Array = []
var network_node_type := "router"
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
	object_name = "Router L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()

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
		object_name = "Router L" + str(level)
		update_actions()

		set_facing(current_facing)

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

func remove_connection(segment) -> void:
	connected_segments.erase(segment)

func has_free_port() -> bool:
	return connected_segments.size() < get_port_limit()

func get_port_limit() -> int:
	return port_limits.get(level, 8)