extends "res://scripts/systems/thermal_source.gd"

@export var simulate_default_load: bool = true
@export var idle_traffic_per_second: float = 12.0
@export_range(0.0, 2.0, 0.01) var idle_load_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var idle_power_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var idle_efficiency_multiplier: float = 1.0

var _powered_traffic_per_second: float = 0.0

func _ready() -> void:
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
	_powered_traffic_per_second = traffic_per_second
	super._ready()

func get_directional_texture_prefix() -> String:
	var safe_level: int = max(level, 1)
	return "res://assets/object_sprites/servers/server_rack_%d" % safe_level

func set_powered_state(powered: bool) -> void:
	if powered:
		set_source_enabled(true)
		if traffic_per_second <= 0.0 and _powered_traffic_per_second > 0.0:
			traffic_per_second = _powered_traffic_per_second
		else:
			recalculate_heat()
		return

	if traffic_per_second > 0.0:
		_powered_traffic_per_second = traffic_per_second

	set_source_enabled(false)
	traffic_per_second = 0.0

func turn_off() -> void:
	set_powered_state(false)

func turn_on() -> void:
	set_powered_state(true)
