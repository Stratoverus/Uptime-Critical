extends CharacterBody2D

@export var move_speed: float = 220.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

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
	velocity = direction * move_speed
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
		key_event.physical_keycode = key_code
		InputMap.action_add_event(action_name, key_event)


func _action_has_key(action_name: String, key_code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == key_code:
			return true

	return false
