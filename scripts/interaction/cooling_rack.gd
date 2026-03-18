extends InteractableObject

func _ready() -> void:
	object_name = "Cooling Unit"
	actions = ["Turn Off", "Turn On", "Inspect"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Turn Off":
			print("Turning off cooling unit")
			turn_off()
		"Turn On":
			print("Turning on cooling unit")
			turn_on()
		"Inspect":
			print("Inspecting cooling unit")
			inspect()

func turn_off() -> void:
	pass

func turn_on() -> void:
	pass

func inspect() -> void:
	pass