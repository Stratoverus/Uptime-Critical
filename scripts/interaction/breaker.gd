extends InteractableObject

var sprites = {
	"front": preload("res://assets/object_sprites/breaker_front.png"),
	"right": preload("res://assets/object_sprites/breaker_right.png"),
	"back": preload("res://assets/object_sprites/breaker_back.png"),
	"left": preload("res://assets/object_sprites/breaker_left.png")
}

func _ready() -> void:
	object_name = "Breaker"
	actions = ["Turn Off", "Turn On"]
	interaction_range = 150.0
	super._ready()

func set_facing(direction: String) -> void:
	if sprites.has(direction):
		sprite.texture = sprites[direction]

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			turn_off()
			print("Breaker turned off")
		"Turn On":
			turn_on()
			print("Breaker turned on")
		"Reboot":
			print("Rebooting breaker")
			reboot()

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func reboot() -> void:
	pass