extends Area2D
class_name InteractableObject

signal interaction_requested(interactable)

@export var object_name: String = "Interactable"
@export var interaction_range: float = 150.0
@export var actions: Array[String] = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("interactable")
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ignore_until := int(get_meta("ignore_interaction_until", 0))
		if Time.get_ticks_msec() < ignore_until:
			return

		interaction_requested.emit(self)

func get_actions() -> Array[String]:
	return actions

func perform_action(_action_name: String) -> void:
	pass

func _on_mouse_entered() -> void:
	if not sprite:
		return

	if has_method("_update_cable_mode_visual"):
		call("_update_cable_mode_visual")

	sprite.modulate = sprite.modulate * Color(1.15, 1.15, 1.15, 1.0)

func _on_mouse_exited() -> void:
	if not sprite:
		return

	if has_method("_update_cable_mode_visual"):
		call("_update_cable_mode_visual")
	else:
		sprite.modulate = Color(1, 1, 1, 1)

func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func get_distance_to_player() -> float:
	var player := get_player()
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)

func is_player_in_range() -> bool:
	return get_distance_to_player() <= interaction_range