extends Node2D

@onready var radial_menu = $UI/RadialMenu
var current_interactable = null

func _ready() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)

func _on_interaction_requested(interactable) -> void:
	current_interactable = interactable

	var items = []
	for action in interactable.get_actions():
		items.append({
			"title": action,
			"id": action,
			"texture": get_action_icon(action)
		})

	radial_menu.set_items(items)
	radial_menu.open_menu(get_viewport().get_mouse_position())

func _on_menu_item_selected(id, position) -> void:
	if current_interactable:
		current_interactable.perform_action(id)
		current_interactable = null

func get_action_icon(action_name: String) -> Texture2D:
	match action_name:
		"Turn Off":
			return load("res://assets/UI/icons/turn_off.svg")
		"Turn On":
			return load("res://assets/UI/icons/turn_on.svg")
		"Reboot":
			return load("res://assets/UI/icons/reboot.svg")
		"Inspect":
			return load("res://assets/UI/icons/inspect.svg")
		_:
			return null