extends InteractableObject

@export var level: int = 1

var current_facing: String = "front"

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

var upgrade_costs = {
	1: 200,
	2: 300
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
		print("Cooling rack L", level, "off")
		turn_off()
	elif action_name == "Turn On":
		print("Cooling rack L", level, "on")
		turn_on()
	elif action_name == "Inspect":
		print("Inspecting cooling rack L", level)
		inspect()
	elif action_name.begins_with("Upgrade"):
		print("Upgrading cooling rack L", level)
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
		print("Already max level")
		return

	var cost = upgrade_costs.get(level, 0)
	var game = get_tree().get_first_node_in_group("hud")

	if game and game.can_afford(cost):
		game.spend_money(cost)

		level += 1
		object_name = "Cooling Rack L" + str(level)
		update_actions()
		set_facing(current_facing)

		print("Upgraded to level", level)
	else:
		print("Not enough money to upgrade")