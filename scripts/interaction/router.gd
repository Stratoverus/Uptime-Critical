extends InteractableObject

@export var level: int = 1

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

func _ready() -> void:
	object_name = "Router L" + str(level)
	actions = ["Turn Off", "Turn On", "Reboot"]
	interaction_range = 150.0
	super._ready()

func set_facing(direction: String) -> void:
	if sprites_by_level.has(level):
		var sprites = sprites_by_level[level]

		if sprites.has(direction):
			sprite.texture = sprites[direction]
		else:
			print("Missing direction:", direction)
	else:
		print("Missing level:", level)

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			print("Turning off router L", level)
			turn_off()
		"Turn On":
			print("Turning on router L", level)
			turn_on()
		"Reboot":
			print("Rebooting router L", level)
			reboot()
		_:
			super.perform_action(action_name)

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func reboot() -> void:
	pass