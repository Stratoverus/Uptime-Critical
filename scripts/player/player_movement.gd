extends CharacterBody2D

@export var move_speed: float = 220.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var move_target: Vector2 = Vector2.ZERO
var moving_to_target: bool = false
var target_interactable = null
var auto_move_target: Vector2 = Vector2.ZERO
var auto_moving: bool = false

const MOVE_ACTIONS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_up": KEY_W,
	"move_down": KEY_S,
}

func _ready() -> void:
	add_to_group("player")
	_ensure_wasd_actions()
	animated_sprite.play("idle")

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if direction != Vector2.ZERO:
		auto_moving = false
		velocity = direction * move_speed
	else:
		if auto_moving:
			var auto_direction := auto_move_target - global_position

			if auto_direction.length() < 8.0:
				auto_moving = false
				velocity = Vector2.ZERO
			else:
				direction = auto_direction.normalized()
				velocity = direction * move_speed
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(direction)

func _update_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		animated_sprite.play("idle")
		return

	if abs(direction.x) > abs(direction.y):
		if direction.x > 0.0:
			animated_sprite.play("walkRight")
		else:
			animated_sprite.play("walkLeft")
	else:
		if direction.y > 0.0:
			animated_sprite.play("walkDown")
		else:
			animated_sprite.play("walkUp")

func _ensure_wasd_actions() -> void:
	for action_name: String in MOVE_ACTIONS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		var key_code: Key = MOVE_ACTIONS[action_name]
		if _action_has_key(action_name, key_code):
			continue

		var key_event := InputEventKey.new()
		key_event.physical_keycode = key_code as Key
		InputMap.action_add_event(action_name, key_event)


func _action_has_key(action_name: String, key_code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == key_code:
			return true

	return false

func move_to_interactable(interactable) -> void:
	var direction: Vector2 = (global_position - interactable.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN

	auto_move_target = interactable.global_position + direction * (interactable.interaction_range - 10.0)
	auto_moving = true
