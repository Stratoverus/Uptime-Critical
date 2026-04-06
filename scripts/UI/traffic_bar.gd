extends ProgressBar

var color_safe = Color.GREEN
var color_danger = Color.RED
var dropped_overlay_color = Color(0.88, 0.15, 0.12, 0.8)
var dropped_ratio: float = 0.0

func update_display(current_val: float, max_val: float, servers_active: bool, unit_label: String = "Req/s", dropped_ratio_input: float = 0.0):
	max_value = max(max_val, 1.0)
	value = current_val
	dropped_ratio = clamp(dropped_ratio_input, 0.0, 1.0)

	var filling_ratio = value / max_value
	var current_color = color_safe.lerp(color_danger, filling_ratio)

	var sb = get_theme_stylebox("fill").duplicate()
	sb.bg_color = current_color
	add_theme_stylebox_override("fill", sb)

	if servers_active:
		if max_value < 1000.0:
			$TrafficLabel.text = "%d / %d %s" % [int(value), int(max_value), unit_label]
		elif max_value >= 1000.0 and max_value < 1000000.0:
			$TrafficLabel.text = "%.2f / %.2f k%s" % [value / 1000.0, max_value / 1000.0, unit_label]
		else:
			$TrafficLabel.text = "%.2f / %.2f M%s" % [value / 1000000.0, max_value / 1000000.0, unit_label]
		if dropped_ratio > 0.0:
			$TrafficLabel.text += " | Drop %.0f%%" % (dropped_ratio * 100.0)
	else:
		$TrafficLabel.text = "SERVER OFFLINE"

	queue_redraw()

func _draw() -> void:
	if max_value <= 0.0:
		return

	if dropped_ratio <= 0.0:
		return

	var dropped_value: float = value * dropped_ratio
	if dropped_value <= 0.0:
		return

	var handled_value: float = max(value - dropped_value, 0.0)
	var handled_ratio: float = clamp(handled_value / max_value, 0.0, 1.0)
	var dropped_ratio_on_capacity: float = clamp(dropped_value / max_value, 0.0, 1.0 - handled_ratio)

	if dropped_ratio_on_capacity <= 0.0:
		return

	var bar_rect := Rect2(Vector2.ZERO, size)
	var dropped_rect := Rect2(
		Vector2(bar_rect.position.x + bar_rect.size.x * handled_ratio, bar_rect.position.y),
		Vector2(bar_rect.size.x * dropped_ratio_on_capacity, bar_rect.size.y)
	)
	draw_rect(dropped_rect, dropped_overlay_color, true)
