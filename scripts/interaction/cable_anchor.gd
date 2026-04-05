extends Area2D

@export var anchor_group_name: StringName = &"network_nodes"

var is_connected_to_network := false
var cable_mode_highlight_on := false
var object_name := "Cable Anchor"
var connected_segments: Array = []
var network_node_type := "anchor"

@onready var sprite = $Sprite2D

func _ready():
	if anchor_group_name != &"":
		add_to_group(anchor_group_name)
	input_pickable = true

func set_cable_mode_highlight(enabled: bool) -> void:
	cable_mode_highlight_on = enabled
	_update_visual()

func _update_visual() -> void:
	if not sprite:
		return

	if not cable_mode_highlight_on:
		sprite.modulate = Color(1, 1, 1, 1)
	else:
		sprite.modulate = Color(1.0, 1.0, 0.6, 1.0)

func add_connection(segment) -> void:
	if not connected_segments.has(segment):
		connected_segments.append(segment)

func remove_connection(segment) -> void:
	connected_segments.erase(segment)