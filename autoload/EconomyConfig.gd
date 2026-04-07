extends Node

@export_group("Network Cable Costs ($/ft)")
@export var cat5_cost_per_foot: float = 0.25
@export var cat6_cost_per_foot: float = 0.40
@export var fiber_cost_per_foot: float = 0.90
@export var uplink_cost_per_foot: float = 2.50

@export_group("Electrical Cable Costs ($/ft)")
@export var power_cable_cost_per_foot: float = 0.005

@export_group("Unit Purchase Costs")
@export var server_rack_l1_cost: int = 100
@export var server_rack_l2_cost: int = 200
@export var server_rack_l3_cost: int = 300
@export var cooling_unit_l1_cost: int = 120
@export var cooling_unit_l2_cost: int = 240
@export var cooling_unit_l3_cost: int = 360
@export var router_l1_cost: int = 200
@export var router_l2_cost: int = 400
@export var router_l3_cost: int = 600

@export_group("Upgrade Costs")
@export var server_upgrade_l1_to_l2: int = 420
@export var server_upgrade_l2_to_l3: int = 760
@export var cooling_upgrade_l1_to_l2: int = 360
@export var cooling_upgrade_l2_to_l3: int = 620
@export var router_upgrade_l1_to_l2: int = 460
@export var router_upgrade_l2_to_l3: int = 820

@export_group("Economy Start")
@export var starting_money: float = 900.0

@export_group("Cable Capacity (Req/s)")
@export var cat5_capacity_rps: float = 900.0
@export var cat6_capacity_rps: float = 1800.0
@export var fiber_capacity_rps: float = 3600.0
@export var uplink_capacity_rps: float = 9000.0
@export var power_capacity_rps: float = 1800.0
@export var default_capacity_rps: float = 500.0

@export_group("Traffic Ramp Tuning")
@export var traffic_ramp_minutes_to_max: float = 40.0
@export var traffic_ramp_multiplier_max: float = 2.25
@export var traffic_ramp_curve_exponent: float = 1.1
@export var traffic_overload_ceiling_ratio: float = 2.5

const INTERNET_PIPE_NAME: String = "Internet Pipe (Uplink)"

func get_network_cable_items() -> Array:
	return [
		{ "name": "Cat5", "color": Color(0.53, 0.53, 0.53, 1.0), "cost": cat5_cost_per_foot },
		{ "name": "Cat6", "color": Color(0.36, 0.56, 0.72, 1.0), "cost": cat6_cost_per_foot },
		{ "name": "Fiber", "color": Color(0.16, 0.74, 0.66, 1.0), "cost": fiber_cost_per_foot },
		{ "name": INTERNET_PIPE_NAME, "color": Color(0.94, 0.76, 0.18, 1.0), "cost": uplink_cost_per_foot }
	]

func get_electrical_cable_items() -> Array:
	return [
		{ "name": "Power Cable", "color": Color(0.12, 0.86, 1.0, 0.95), "cost": power_cable_cost_per_foot }
	]

func get_cable_item_by_name(cable_name: String) -> Dictionary:
	for cable_data in get_network_cable_items():
		if str(cable_data.get("name", "")) == cable_name:
			return cable_data.duplicate(true)
	for cable_data in get_electrical_cable_items():
		if str(cable_data.get("name", "")) == cable_name:
			return cable_data.duplicate(true)
	return {}

func get_unit_cost(unit_id: String, fallback_cost: int = 0) -> int:
	match unit_id:
		"server_rack_l1":
			return server_rack_l1_cost
		"server_rack_l2":
			return server_rack_l2_cost
		"server_rack_l3":
			return server_rack_l3_cost
		"cooling_unit_l1":
			return cooling_unit_l1_cost
		"cooling_unit_l2":
			return cooling_unit_l2_cost
		"cooling_unit_l3":
			return cooling_unit_l3_cost
		"router_l1":
			return router_l1_cost
		"router_l2":
			return router_l2_cost
		"router_l3":
			return router_l3_cost
		_:
			return fallback_cost

func get_upgrade_cost(category: String, from_level: int, fallback_cost: int = 0) -> int:
	if from_level == 1:
		match category:
			"server":
				return server_upgrade_l1_to_l2
			"cooling":
				return cooling_upgrade_l1_to_l2
			"router":
				return router_upgrade_l1_to_l2
			_:
				return fallback_cost
	if from_level == 2:
		match category:
			"server":
				return server_upgrade_l2_to_l3
			"cooling":
				return cooling_upgrade_l2_to_l3
			"router":
				return router_upgrade_l2_to_l3
			_:
				return fallback_cost
	return fallback_cost

func get_cable_capacity_rps(cable_name: String, fallback_capacity: float = 500.0) -> float:
	match cable_name:
		"Cat5":
			return cat5_capacity_rps
		"Cat6":
			return cat6_capacity_rps
		"Fiber":
			return fiber_capacity_rps
		INTERNET_PIPE_NAME:
			return uplink_capacity_rps
		"Power Cable":
			return power_capacity_rps
		_:
			return fallback_capacity if fallback_capacity > 0.0 else default_capacity_rps

func get_traffic_ramp_setting(setting_name: String, fallback_value: float = 0.0) -> float:
	match setting_name:
		"traffic_ramp_minutes_to_max":
			return traffic_ramp_minutes_to_max
		"traffic_ramp_multiplier_max":
			return traffic_ramp_multiplier_max
		"traffic_ramp_curve_exponent":
			return traffic_ramp_curve_exponent
		"traffic_overload_ceiling_ratio":
			return traffic_overload_ceiling_ratio
		_:
			return fallback_value

func get_starting_money(fallback_value: float = 0.0) -> float:
	return starting_money if starting_money > 0.0 else fallback_value