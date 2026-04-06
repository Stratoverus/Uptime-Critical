extends Line2D

var start_point = null
var end_point = null
var start_visual_position: Vector2 = Vector2.ZERO
var end_visual_position: Vector2 = Vector2.ZERO
var cable_type_name := ""
var cost_per_foot := 0.0
var length := 0.0
var total_cost = (length / 300.0) * cost_per_foot
var glow_line: Line2D = null
var base_default_color: Color = Color(0.45, 0.45, 0.45, 1.0)
var base_glow_color: Color = Color(0.24, 0.24, 0.24, 0.24)
var utilization_ratio: float = 0.0
var current_traffic_load_rps: float = 0.0
var max_traffic_capacity_rps: float = 0.0
@export_range(0.0, 1.0, 0.01) var warning_start_ratio: float = 0.50
@export var hot_color: Color = Color(1.0, 0.06, 0.06, 1.0)
@export var hot_glow_color: Color = Color(1.0, 0.08, 0.08, 0.92)

func _ready() -> void:
	add_to_group("cable_segments")
	if glow_line == null:
		glow_line = Line2D.new()
		glow_line.name = "GlowLine"
		glow_line.z_index = -1
		add_child(glow_line)

func setup(a, b, cable_data: Dictionary, start_world_position: Vector2 = Vector2.ZERO, end_world_position: Vector2 = Vector2.ZERO) -> void:
	start_point = a
	end_point = b
	cable_type_name = cable_data.get("name", "Cable")
	cost_per_foot = cable_data.get("cost", 0)
	z_as_relative = false

	if cable_type_name == "Cat5":
		width = 4
		max_traffic_capacity_rps = 300.0
	elif cable_type_name == "Cat6":
		width = 5
		max_traffic_capacity_rps = 600.0
	elif cable_type_name == "Fiber":
		width = 6
		max_traffic_capacity_rps = 1500.0
	elif cable_type_name == "Internet Pipe (Uplink)":
		max_traffic_capacity_rps = 5000.0
	elif cable_type_name == "Power Cable":
		max_traffic_capacity_rps = 1200.0
	else:
		max_traffic_capacity_rps = 500.0
	base_default_color = cable_data.get("color", Color(0.45, 0.45, 0.45, 1.0))
	default_color = base_default_color

	if cable_type_name == "Internet Pipe (Uplink)":
		# Keep uplink clearly visible above world tiles/walls.
		z_index = 120
	else:
		z_index = 0

	if glow_line != null:
		var glow_alpha := 0.24
		if cable_type_name == "Cat6":
			glow_alpha = 0.28
		elif cable_type_name == "Fiber":
			glow_alpha = 0.34
		elif cable_type_name == "Internet Pipe (Uplink)":
			glow_alpha = 0.40

		glow_line.z_as_relative = false
		glow_line.z_index = z_index - 1
		glow_line.width = width + 6.0
		base_glow_color = Color(base_default_color.r * 0.52, base_default_color.g * 0.52, base_default_color.b * 0.52, glow_alpha)
		glow_line.default_color = base_glow_color
		glow_line.closed = false

	var start_pos = start_world_position if start_world_position != Vector2.ZERO else a.global_position
	var end_pos = end_world_position if end_world_position != Vector2.ZERO else b.global_position
	start_visual_position = start_pos
	end_visual_position = end_pos
	var orthogonal_points := build_orthogonal_path(start_pos, end_pos)

	clear_points()
	for p in orthogonal_points:
		add_point(p)

	if glow_line != null:
		glow_line.clear_points()
		for p in orthogonal_points:
			glow_line.add_point(p)

	# calculate length
	length = calculate_polyline_length(orthogonal_points)

	# calculate cost
	total_cost = length * cost_per_foot
	set_traffic_load_rps(0.0)

func build_orthogonal_path(start_pos: Vector2, end_pos: Vector2) -> PackedVector2Array:
	var path_points := PackedVector2Array()
	path_points.append(start_pos)

	var dx = abs(end_pos.x - start_pos.x)
	var dy = abs(end_pos.y - start_pos.y)
	if dx >= dy:
		append_unique_point(path_points, Vector2(end_pos.x, start_pos.y))
	else:
		append_unique_point(path_points, Vector2(start_pos.x, end_pos.y))

	append_unique_point(path_points, end_pos)
	return path_points

func append_unique_point(path_points: PackedVector2Array, point: Vector2) -> void:
	if path_points.is_empty():
		path_points.append(point)
		return
	if path_points[path_points.size() - 1].distance_to(point) <= 0.01:
		return
	path_points.append(point)

func calculate_polyline_length(path_points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path_points.size() - 1):
		total += path_points[i].distance_to(path_points[i + 1])
	return total

func get_other_point(point):
	if point == start_point:
		return end_point
	if point == end_point:
		return start_point
	return null

func uses_endpoint(node, world_position: Vector2, tolerance: float = 2.0) -> bool:
	if node == start_point and start_visual_position.distance_to(world_position) <= tolerance:
		return true
	if node == end_point and end_visual_position.distance_to(world_position) <= tolerance:
		return true
	return false

func set_utilization_ratio(ratio: float) -> void:
	utilization_ratio = clamp(ratio, 0.0, 1.0)

	var warning_start: float = clamp(warning_start_ratio, 0.0, 1.0)
	var normalized := 0.0
	if utilization_ratio > warning_start:
		normalized = (utilization_ratio - warning_start) / max(1.0 - warning_start, 0.001)

	default_color = base_default_color.lerp(hot_color, normalized)

	if glow_line != null:
		var glow_hot := Color(hot_glow_color.r, hot_glow_color.g, hot_glow_color.b, base_glow_color.a)
		glow_line.default_color = base_glow_color.lerp(glow_hot, normalized)
		var max_glow_width: float = width + 13.0
		glow_line.width = lerp(width + 6.0, max_glow_width, normalized)

func get_utilization_ratio() -> float:
	return utilization_ratio

func get_max_traffic_capacity_rps() -> float:
	return max(max_traffic_capacity_rps, 1.0)

func get_current_traffic_load_rps() -> float:
	return max(current_traffic_load_rps, 0.0)

func set_traffic_load_rps(load_rps: float) -> void:
	current_traffic_load_rps = max(load_rps, 0.0)
	var ratio: float = current_traffic_load_rps / get_max_traffic_capacity_rps()
	set_utilization_ratio(clamp(ratio, 0.0, 1.0))

func get_wire_stats_text() -> String:
	var usage_percent: float = utilization_ratio * 100.0
	var cable_kind: String = "Traffic"
	if cable_type_name == "Power Cable":
		cable_kind = "Power"
	elif cable_type_name == "Internet Pipe (Uplink)":
		cable_kind = "Uplink"

	var start_name: String = _get_node_label(start_point)
	var end_name: String = _get_node_label(end_point)
	return "Type: %s\nFrom: %s\nTo: %s\nCost: $%.2f\nLoad: %.1f / %.1f Req/s\nUtilization: %.1f%%\nLoad Class: %s" % [
		cable_type_name,
		start_name,
		end_name,
		total_cost,
		get_current_traffic_load_rps(),
		get_max_traffic_capacity_rps(),
		usage_percent,
		cable_kind
	]

func _get_node_label(node) -> String:
	if node == null:
		return "Unknown"

	var object_name_value: Variant = node.get("object_name")
	if object_name_value != null and str(object_name_value) != "":
		return str(object_name_value)

	return str(node.name)
