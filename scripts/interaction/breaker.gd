extends InteractableObject

func _ready() -> void:
	object_name = "Breaker"
	actions = ["Inspect", "Toggle Power", "Reset Breaker"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Inspect":
			print("Inspecting breaker")
		"Toggle Power":
			print("Toggling power")
		"Reset Breaker":
			print("Resetting breaker")