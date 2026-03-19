extends Area2D
class_name InteractableObject

signal interaction_requested(interactable)

@export var object_name: String = "Interactable"
@export var interaction_range: float = 150.0
@export var actions: Array[String] = []
@export var auto_step_range: float = 300.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("interactable")
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _input_event(viewport, event, shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var distance := get_distance_to_player()
		print(object_name, " distance to player = ", distance)

		if is_player_in_range():
			print("In range:", object_name)
			interaction_requested.emit(self)
		elif is_player_in_auto_step_range():
			print("Auto-step toward:", object_name)
			_auto_step_player_and_interact()
		else:
			print("Too far away from:", object_name)

func get_actions() -> Array[String]:
	return actions

func perform_action(action_name: String) -> void:
	print(object_name, " performed action: ", action_name)

func _on_mouse_entered() -> void:
	if sprite:
		sprite.modulate = Color(1.3, 1.3, 1.3, 1.0)

func _on_mouse_exited() -> void:
	if sprite:
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

func is_player_in_auto_step_range() -> bool:
	var distance := get_distance_to_player()
	return distance > interaction_range and distance <= auto_step_range

func _auto_step_player_and_interact() -> void:
	var player := get_player()
	if player == null:
		print("No player found")
		return

	var direction := (global_position - player.global_position).normalized()
	var target_position := global_position - direction * (interaction_range - 10.0)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(player, "global_position", target_position, 0.25)
	await tween.finished

	print("Player moved to:", player.global_position)
	interaction_requested.emit(self)
