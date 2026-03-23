extends InteractableObject

func _ready() -> void:
	object_name = "Breaker"
	actions = ["Turn Off", "Turn On", "Reboot"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			print("Turning off breaker")
			turn_off()
		"Turn On":
			print("Turning on breaker")
			turn_on()
		"Reboot":
			print("Rebooting breaker")
			reboot()

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func reboot() -> void:
	pass