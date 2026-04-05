extends Area2D
class_name InteractableObject

signal interaction_requested(interactable)

@export var object_name: String = "Interactable"
@export var interaction_range: float = 150.0
@export var build_time_sec: float = 2.0
@export_range(0.0, 3.0, 0.05) var power_fade_duration_sec: float = 1.0
@export var actions: Array[String] = []

@onready var sprite: Sprite2D = $Sprite2D
var _sprite_modulate_tween: Tween = null
var _sprite_modulate_target: Color = Color(1.0, 1.0, 1.0, 1.0)

func _ready() -> void:
	add_to_group("interactable")
	_ensure_physics_blocker()
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func apply_facing_rotation(direction: String) -> void:
	rotation = _facing_to_rotation(direction)

func _facing_to_rotation(direction: String) -> float:
	match direction:
		"right":
			return PI * 0.5
		"back":
			return PI
		"left":
			return -PI * 0.5
		_:
			return 0.0

func _ensure_physics_blocker() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return

	var blocker := get_node_or_null("PhysicsBlocker") as StaticBody2D
	if blocker == null:
		blocker = StaticBody2D.new()
		blocker.name = "PhysicsBlocker"
		add_child(blocker)

	blocker.collision_layer = 1
	blocker.collision_mask = 1

	var blocker_shape := blocker.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if blocker_shape == null:
		blocker_shape = CollisionShape2D.new()
		blocker_shape.name = "CollisionShape2D"
		blocker.add_child(blocker_shape)

	blocker_shape.position = collision_shape.position
	blocker_shape.rotation = collision_shape.rotation
	if collision_shape.shape != null:
		blocker_shape.shape = collision_shape.shape.duplicate(true)

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

func set_sprite_modulate(target: Color, duration_sec: float = 0.0) -> void:
	if not sprite:
		return

	if duration_sec <= 0.0 and _sprite_modulate_tween != null and is_instance_valid(_sprite_modulate_tween):
		if _colors_approx_equal(target, _sprite_modulate_target):
			# Preserve in-flight tween toward the same target for smoother transitions.
			return

	if _sprite_modulate_tween != null and is_instance_valid(_sprite_modulate_tween):
		_sprite_modulate_tween.kill()
		_sprite_modulate_tween = null

	if duration_sec <= 0.0:
		_sprite_modulate_target = target
		sprite.modulate = target
		return

	_sprite_modulate_target = target
	_sprite_modulate_tween = create_tween()
	_sprite_modulate_tween.set_trans(Tween.TRANS_SINE)
	_sprite_modulate_tween.set_ease(Tween.EASE_OUT)
	_sprite_modulate_tween.tween_property(sprite, "modulate", target, duration_sec)
	_sprite_modulate_tween.finished.connect(func() -> void:
		_sprite_modulate_tween = null
	)

func _colors_approx_equal(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b) and is_equal_approx(a.a, b.a)

func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func get_distance_to_player() -> float:
	var player := get_player()
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)

func is_player_in_range() -> bool:
	return get_distance_to_player() <= interaction_range

func show_top_alert(message: String, duration_ms: int = 1400) -> void:
	if message.is_empty():
		return

	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("_show_top_alert"):
		scene_root.call("_show_top_alert", message, duration_ms)
