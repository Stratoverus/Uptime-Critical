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
	elif cable_type_name == "Cat6":
		width = 5
	elif cable_type_name == "Fiber":
		width = 6
	default_color = cable_data.get("color", Color(0.45, 0.45, 0.45, 1.0))

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
		glow_line.default_color = Color(default_color.r * 0.52, default_color.g * 0.52, default_color.b * 0.52, glow_alpha)
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
