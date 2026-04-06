extends RefCounted

# Shared geometry and placement helpers for all wiring overlays.
static func build_orthogonal_path(start_point: Vector2, end_point: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(start_point)

	var dx: float = abs(end_point.x - start_point.x)
	var dy: float = abs(end_point.y - start_point.y)
	if dx >= dy:
		_append_unique_point(points, Vector2(end_point.x, start_point.y))
	else:
		_append_unique_point(points, Vector2(start_point.x, end_point.y))

	_append_unique_point(points, end_point)
	return points

static func calculate_polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

static func distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var best_distance := INF
	for i in range(points.size() - 1):
		best_distance = min(best_distance, distance_to_segment(point, points[i], points[i + 1]))
	return best_distance

static func distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment_vector := segment_end - segment_start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.001:
		return point.distance_to(segment_start)

	var t: float = clamp((point - segment_start).dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	var projection: Vector2 = segment_start + segment_vector * t
	return point.distance_to(projection)

static func closest_point_on_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> Vector2:
	var segment_vector := segment_end - segment_start
	var point_vector := point - segment_start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.001:
		return segment_start

	var t: float = clamp(point_vector.dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	return segment_start + segment_vector * t

static func is_point_too_close_to_positions(point: Vector2, positions: Array, min_distance: float) -> bool:
	for position_value in positions:
		if not (position_value is Vector2):
			continue
		if (position_value as Vector2).distance_to(point) < min_distance:
			return true
	return false

static func _append_unique_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty():
		points.append(point)
		return
	if points[points.size() - 1].distance_to(point) <= 0.01:
		return
	points.append(point)
