extends InteractableObject

@export var base_heat: float = 15.0  # Represents ~30°C idle temperature
@export var heat_radius: float = 260.0
@export var back_local_direction: Vector2 = Vector2.RIGHT
@export var intake_local_direction: Vector2 = Vector2.LEFT
@export var airflow_rate: float = 1.0
@export var cooling_capacity: float = 0.0
@export var level: int = 1

@onready var electrical_node_left: Node2D = $ElectricalNodeLeft
@onready var electrical_node_right: Node2D = $ElectricalNodeRight

var current_facing: String = "front"

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
	object_name = "Server Rack L" + str(level)
	update_actions()
	interaction_range = 150.0
	add_to_group("electrical_connectable")
	super._ready()
	add_to_group("heat_sources")
	notify_thermal_system_placed()

func _exit_tree() -> void:
	notify_thermal_system_removed()

func get_electrical_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node_left):
		nodes.append(electrical_node_left)
	if is_instance_valid(electrical_node_right):
		nodes.append(electrical_node_right)
	return nodes

func get_heat_value() -> float:
	return base_heat

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

func set_facing(direction: String) -> void:
	current_facing = direction

	if sprites_by_level.has(level):
		var sprites = sprites_by_level[level]

		if sprites.has(direction):
			sprite.texture = sprites[direction]
		else:
			print("Missing direction:", direction)
	else:
		print("Missing level:", level)

func perform_action(action_name: String) -> void:
	if action_name == "Turn Off":
		print("Turning off server rack L", level)
		turn_off()
	elif action_name == "Turn On":
		print("Turning on server rack L", level)
		turn_on()
	elif action_name.begins_with("Upgrade"):
		print("Upgrading server rack L", level)
		upgrade()
	else:
		super.perform_action(action_name)

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func upgrade() -> void:
	if level >= 3:
		print("Already max level")
		return

	var cost = upgrade_costs.get(level, 0)
	var game = get_tree().get_first_node_in_group("hud")

	if game and game.can_afford(cost):
		game.spend_money(cost)

		level += 1
		object_name = "Server Rack L" + str(level)
		update_actions()
		set_facing(current_facing)

		print("Upgraded to level", level)
	else:
		print("Not enough money to upgrade")

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
