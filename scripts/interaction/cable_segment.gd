extends Line2D

var start_point = null
var end_point = null
var cable_type_name := ""
var cost_per_foot := 0.0
var length := 0.0
var total_cost = (length / 300.0) * cost_per_foot

func _ready() -> void:
	add_to_group("cable_segments")

func setup(a, b, cable_data: Dictionary) -> void:
	start_point = a
	end_point = b
	cable_type_name = cable_data.get("name", "Cable")
	cost_per_foot = cable_data.get("cost", 0)

	if cable_type_name == "Cat5":
		width = 3
	elif cable_type_name == "Cat6":
		width = 4
	elif cable_type_name == "Fiber":
		width = 5
	default_color = cable_data.get("color", Color.WHITE)

	clear_points()
	add_point(a.global_position)
	add_point(b.global_position)

	# calculate length
	length = a.global_position.distance_to(b.global_position)

	# calculate cost
	total_cost = length * cost_per_foot

func get_other_point(point):
	if point == start_point:
		return end_point
	if point == end_point:
		return start_point
	return null
