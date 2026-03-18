# TrafficBar.gd (Attached to the ProgressBar)
extends ProgressBar

var color_safe = Color.GREEN
var color_danger = Color.RED

func update_display(current_val: float):
	# This function ONLY handles visuals
	value = current_val
	
	var filling_ratio = value / max_value
	var current_color = color_safe.lerp(color_danger, filling_ratio)
	
	var sb = get_theme_stylebox("fill").duplicate()
	sb.bg_color = current_color
	add_theme_stylebox_override("fill", sb)

	if max_value < 1000:
		$TrafficLabel.text = "%d / %d Mbps" % [int(value), int(max_value)]
	else:
		$TrafficLabel.text = "%.2f / %.2f Gbps" % [value/1000.0, max_value/1000.0]
