extends Node2D
class_name PowerStatusLight

@export var light_color: Color = Color(0.30, 1.0, 0.56, 1.0):
	set(value):
		light_color = value
		_apply_visual_state()

@export_range(0.0, 1.0, 0.01) var min_alpha: float = 0.62
@export_range(0.0, 1.0, 0.01) var max_alpha: float = 1.0
@export_range(0.1, 8.0, 0.05) var blink_speed_hz: float = 1.35
@export var show_dim_when_unpowered: bool = false
@export_range(0.0, 1.0, 0.01) var unpowered_alpha: float = 0.08
@export var randomize_phase_on_ready: bool = true
@export_range(0.0, 6.28318, 0.0001) var phase_offset: float = 0.0
@export_range(2, 64, 1) var default_sprite_size_px: int = 14

@onready var light_sprite: Sprite2D = get_node_or_null("LightSprite") as Sprite2D

var is_powered: bool = false
var blink_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if randomize_phase_on_ready:
		phase_offset = randf() * TAU
	_ensure_light_sprite()
	_apply_visual_state()


func set_powered(powered: bool) -> void:
	if is_powered == powered:
		return
	is_powered = powered
	_apply_visual_state()


func set_light_color(color_value: Color) -> void:
	light_color = color_value
	_apply_visual_state()


func _process(delta: float) -> void:
	if not is_powered:
		return
	blink_time += delta
	_apply_visual_state()


func _apply_visual_state() -> void:
	if light_sprite == null:
		return

	var color_out: Color = light_color
	if is_powered:
		var wave := 0.5 + (0.5 * sin((blink_time * blink_speed_hz * TAU) + phase_offset))
		color_out.a = lerp(min_alpha, max_alpha, wave)
		light_sprite.visible = true
	else:
		color_out.a = unpowered_alpha
		light_sprite.visible = show_dim_when_unpowered

	light_sprite.modulate = color_out


func _ensure_light_sprite() -> void:
	if light_sprite == null:
		light_sprite = Sprite2D.new()
		light_sprite.name = "LightSprite"
		add_child(light_sprite)

	light_sprite.centered = true
	light_sprite.z_index = 8

	# Scene instances may already include LightSprite but leave texture unset.
	if light_sprite.texture == null:
		light_sprite.texture = _build_default_light_texture(default_sprite_size_px)


func _build_default_light_texture(size_px: int) -> Texture2D:
	var safe_size: int = max(size_px, 2)
	var image := Image.create(safe_size, safe_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(safe_size - 1) * 0.5, float(safe_size - 1) * 0.5)
	var radius: float = float(safe_size) * 0.5

	for y in range(safe_size):
		for x in range(safe_size):
			var point := Vector2(float(x), float(y))
			var dist := center.distance_to(point)
			var t: float = clamp(1.0 - (dist / radius), 0.0, 1.0)
			var alpha: float = t * t
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)
