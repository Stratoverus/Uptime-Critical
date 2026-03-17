extends InteractableObject

func _ready() -> void:
	object_name = "Server Rack"
	actions = ["Inspect", "Reboot", "Diagnostics"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Inspect":
			print("Inspecting server rack")
		"Reboot":
			print("Rebooting server rack")
		"Diagnostics":
			print("Running diagnostics on server rack")