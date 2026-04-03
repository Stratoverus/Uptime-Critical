extends "res://scripts/systems/thermal_source.gd"

@export var simulate_default_load: bool = true
@export var idle_traffic_per_second: float = 12.0
@export_range(0.0, 2.0, 0.01) var idle_load_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var idle_power_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var idle_efficiency_multiplier: float = 1.0

@onready var electrical_node_left: Node2D = $ElectricalNodeLeft
@onready var electrical_node_right: Node2D = $ElectricalNodeRight

func _ready() -> void:
	add_to_group("electrical_connectable")
	if source_type == &"generic":
		source_type = &"server"
	if simulate_default_load:
		# Until gameplay traffic is wired into thermal_source, keep servers at a realistic idle load.
		if traffic_per_second <= 0.0:
			var safe_level: int = max(level, 1)
			var level_scale: float = 1.0 + (float(safe_level - 1) * 0.18)
			traffic_per_second = idle_traffic_per_second * level_scale
		if load_multiplier <= 0.0:
			load_multiplier = idle_load_multiplier
		if power_multiplier <= 0.0:
			power_multiplier = idle_power_multiplier
		if efficiency_multiplier <= 0.0:
			efficiency_multiplier = idle_efficiency_multiplier
	super._ready()


func get_electrical_nodes() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	if is_instance_valid(electrical_node_left):
		nodes.append(electrical_node_left)
	if is_instance_valid(electrical_node_right):
		nodes.append(electrical_node_right)
	return nodes

func get_directional_texture_prefix() -> String:
	var safe_level: int = max(level, 1)
	return "res://assets/object_sprites/servers/server_rack_%d" % safe_level
