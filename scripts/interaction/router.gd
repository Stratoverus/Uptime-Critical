extends InteractableObject

func _ready() -> void:
	object_name = "Router"
	actions = ["Inspect", "Reset", "Reroute"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Inspect":
			print("Inspecting router")
		"Reset":
			print("Resetting router")
		"Reroute":
			print("Rerouting traffic")