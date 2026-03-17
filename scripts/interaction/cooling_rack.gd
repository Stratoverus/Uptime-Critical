extends InteractableObject

func _ready() -> void:
	object_name = "Cooling Unit"
	actions = ["Inspect", "Increase Cooling", "Decrease Cooling"]
	interaction_range = 150.0
	super._ready()

func perform_action(action_name: String) -> void:
	match action_name:
		"Inspect":
			print("Inspecting cooling unit")
		"Increase Cooling":
			print("Increasing cooling")
		"Decrease Cooling":
			print("Decreasing cooling")