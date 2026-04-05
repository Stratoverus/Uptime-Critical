# extends "res://scripts/systems/thermal_source.gd"
extends InteractableObject
@export var level: int = 1
@export var base_heat: float = 0.0
@export var heat_radius: float = 260.0
@export var back_local_direction: Vector2 = Vector2.UP
@export var intake_local_direction: Vector2 = Vector2.DOWN
@export var airflow_rate: float = 1.35
@export var cooling_capacity: float = 40.0

var current_facing: String = "front"
var upgrade_costs = {
	1: 200,
	2: 300
}

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
	if level >= 3:
		actions = ["Turn Off", "Turn On", "Inspect"]
	else:
		var cost = upgrade_costs.get(level, 0)
		actions = [
			"Turn Off",
			"Turn On",
			"Inspect",
			"Upgrade $" + str(cost)
		]

func _ready() -> void:
	object_name = "Cooling Rack L" + str(level)
	update_actions()
	interaction_range = 150.0
	super._ready()
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
	elif action_name == "Inspect":
		inspect()
	elif action_name.begins_with("Upgrade"):
		upgrade()
	else:
		super.perform_action(action_name)

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func inspect() -> void:
	pass

func upgrade() -> void:
	if level >= 3:
		return

	var cost = upgrade_costs.get(level, 0)
	var game = get_tree().get_first_node_in_group("hud")

	if game and game.can_afford(cost):
		game.spend_money(cost)

		level += 1
		object_name = "Cooling Rack L" + str(level)
		update_actions()
		set_facing(current_facing)
