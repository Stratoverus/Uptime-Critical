extends InteractableObject

func _ready() -> void:
	object_name = "Server Rack"
	actions = ["Turn Off", "Turn On", "Reboot"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			print("Turning off server rack")
			turn_off()
		"Turn On":
			print("Turning on server rack")
			turn_on()
		"Reboot":
			print("Rebooting server rack")
			reboot()

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func reboot() -> void:
	pass