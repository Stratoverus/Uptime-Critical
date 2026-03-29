extends InteractableObject

@export var level: int = 1

var current_facing: String = "front"

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
			print("Missing direction:", direction)
	else:
		print("Missing level:", level)

func perform_action(action_name: String) -> void:
	if action_name == "Turn Off":
		print("Turning off router L", level)
		turn_off()
	elif action_name == "Turn On":
		print("Turning on router L", level)
		turn_on()
	elif action_name.begins_with("Upgrade"):
		print("Upgrading router L", level)
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
		object_name = "Router L" + str(level)
		update_actions()

		print("Upgraded to level", level)

		set_facing(current_facing)
	else:
		print("Not enough money to upgrade")