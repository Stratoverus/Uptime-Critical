extends Node

@export var starting_traffic_capacity_mbps: float = 1000.0
@export var starting_load_ratio: float = 0.45
@export var min_rps_ratio: float = 0.08
@export var max_rps_ratio: float = 0.12
@export var traffic_growth_rate: float = 0.006
var starting_money: float = 2500.0
@export var default_prep_countdown_seconds: float = 30.0
@export var server_power_cost: float = 0.00030
@export var offline_idle_drain_per_capacity: float = 0.0025
@export var offline_idle_drain_multiplier: float = 1.5

@export_group("Traffic Tuning")
@export var baseline_demand_capacity_ratio: float = 0.70
@export var demand_capacity_follow_speed: float = 0.35
@export var traffic_floor_ratio: float = 0.35
@export var traffic_peak_ratio: float = 1.05
@export var traffic_volatility_ratio: float = 0.28
@export var traffic_volatility_change_speed: float = 0.85
@export var traffic_response_speed: float = 3.2
@export var capacity_discovery_duration_seconds: float = 55.0
@export var daily_demand_growth_multiplier: float = 0.08
var traffic_ramp_minutes_to_max: float = 40.0
var traffic_ramp_multiplier_max: float = 2.25
var traffic_ramp_curve_exponent: float = 1.1
var traffic_overload_ceiling_ratio: float = 2.5

signal money_changed(new_amount)
signal reputation_changed(new_amount)
signal game_over_state_changed(reason)
signal prep_state_changed(remaining_seconds, is_active)
signal gameplay_started
signal show_event_popup(event_data: Dictionary)

# Event Definitions
var EVENTS: Dictionary = {}

# Tracking variables for the CURRENT active event
var active_event_id: String = ""
var event_expiry_time: float = -1.0
var applied_demand_bonus: float = 0.0
var applied_ddos_bonus: float = 0.0
var last_roll_hour = -1
var current_map_scene_path: String = "res://scenes/maps/serverMap/server_room.tscn"
var gameplay_started_flag: bool = false
var prep_countdown_active: bool = false
var prep_countdown_remaining_seconds: float = 0.0
var prep_countdown_last_logged_second: int = -1

# Game State Variables
var time = 360.0
var time_scale = 12.0 # Min/Sec
var current_day = int(time / 1440) + 1
var servers_active = true
var total_minutes_today = time

# Server-only financial constants
var sla_multiplier = 1.0
var revenue = 0.0
var income_rate = 0.0

# TRAFFIC CONSTANTS
var market_demand = 60.0 # The "Target" traffic the player has attracted/contracted
var organic_growth_rate = 0.01
var max_load = 0.0
var current_load = 0.0
var ddos_load = 0.0
var target_ratio: float = 0.08
var current_display_ratio = 0.1
var total_active_traffic = 0
var legit_rps: float = 0.0
var ddos_rps: float = 0.0
var jitter = 0
var traffic_volatility_state: float = 0.0
var traffic_ramp_elapsed_minutes: float = 0.0
var traffic_ramp_started: bool = false
var discovered_capacity_rps: float = 0.0
var discovery_start_capacity_rps: float = 0.0
var discovery_target_capacity_rps: float = 0.0
var discovery_progress: float = 1.0
var save_dirty_mark_accumulator: float = 0.0
var online_server_capacity_units: int = 0
var online_router_capacity_units: int = 0
var active_cluster_count: int = 0
var capacity_bottleneck: String = "Balanced"

# Request simulation state (RPS domain)
var datacenter_capacity_rps: float = 0.0
var incoming_valid_rps: float = 0.0
var incoming_invalid_rps: float = 0.0
var incoming_total_rps: float = 0.0
var handled_valid_rps: float = 0.0
var handled_invalid_rps: float = 0.0
var handled_total_rps: float = 0.0
var dropped_rps: float = 0.0
var dropped_ratio: float = 0.0
var dropped_pre_wire_rps: float = 0.0
var dropped_wire_bottleneck_rps: float = 0.0
var drop_cause_summary: String = "None"
var total_incoming_requests: float = 0.0
var total_processed_requests: float = 0.0
var total_dropped_requests: float = 0.0

# Reputation / failure state
@export var starting_reputation: float = 50.0
@export var reputation_decay_per_second: float = 0.9
@export var reputation_threshold_drop_start: float = 0.15
@export var reputation_threshold_penalty_per_second: float = 2.0
@export var reputation_any_drop_penalty_per_second: float = 0.35
@export var reputation_recovery_per_second: float = 0.45
@export var reputation_recovery_drop_ratio_max: float = 0.02
@export var irreparable_threshold: float = -1.0
@export var irreparable_duration_seconds: float = 240.0
@export var reputation_soft_drop_exponent: float = 1.35
@export var reputation_incident_buildup_rate: float = 1.2
@export var reputation_incident_decay_per_second: float = 0.35
@export var reputation_incident_multiplier_max: float = 2.25

var datacenter_reputation: float = 100.0
var reputation_incident_stress: float = 0.0
var irreparable_timer_seconds: float = 0.0
var is_game_over: bool = false
var game_over_reason: String = ""

@export var revenue_per_valid_handled_request: float = 0.0012
@export var cooler_overdrive_power_cost: float = 1.25
@export var invalid_request_power_cost_multiplier: float = 0.75

var active_overdrive_coolers: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_event_definitions()
	reset_runtime_state()
	if SaveManager != null and SaveManager.has_method("load_game_state"):
		var loaded_game_state: Variant = SaveManager.load_game_state()
		if loaded_game_state is Dictionary and not (loaded_game_state as Dictionary).is_empty():
			import_runtime_state(loaded_game_state)
	money_changed.emit(revenue)

func _rebuild_event_definitions() -> void:
	EVENTS = {
		# ==========================================
		# CALENDAR EVENTS (Ordered sequentially by Day)
		# ==========================================
		"grand_opening": {
			"display_name": "Grand Opening",
			"trigger_type": "calendar",
			"target_day": 1, 
			"duration_minutes": 1440,
			"demand_mult": 1.2,
			"ddos_add": 0.0,
			"message": "Day 1: Your data center is officially live!",
			"seen_before": false,
			"event_is_good": true
		},
		"black_friday": {
			"display_name": "Black Friday",
			"trigger_type": "calendar",
			"target_day": 7,
			"duration_minutes": 1440,
			"demand_mult": 2.0,
			"ddos_add": 0.0,
			"message": "It's Day 7: Black Friday is here!",
			"seen_before": false,
			"event_is_good": true
		},
		"cyber_monday": {
			"display_name": "Cyber Monday",
			"trigger_type": "calendar",
			"target_day": 10, 
			"duration_minutes": 1440,
			"demand_mult": 3.0,
			"ddos_add": 300.0,
			"message": "It's Cyber Monday! The network is melting!",
			"seen_before": false,
			"event_is_good": true
		},
		"quarterly_earnings": {
			"display_name": "Quarterly Earnings Calls",
			"trigger_type": "calendar",
			"target_day": 14, 
			"duration_minutes": 480, # 8 hours of business time
			"demand_mult": 1.5,
			"ddos_add": 0.0,
			"message": "Corporate clients are streaming their earnings calls. Stable traffic ahead.",
			"seen_before": false,
			"event_is_good": true
		},
		"major_os_update": {
			"display_name": "Major OS Update Release",
			"trigger_type": "calendar",
			"target_day": 20, 
			"duration_minutes": 1440,
			"demand_mult": 1.8,
			"ddos_add": 0.0,
			"message": "WindOs 12 just released. Get ready for heavy download traffic!",
			"seen_before": false,
			"event_is_good": true
		},
		"end_of_month_backups": {
			"display_name": "End of Month Backups",
			"trigger_type": "calendar",
			"target_day": 30, 
			"duration_minutes": 1440, 
			"demand_mult": 2.2,
			"ddos_add": 0.0,
			"message": "All enterprise clients are running massive end-of-month data backups!",
			"seen_before": false,
			"event_is_good": true
		},

		# ==========================================
		# RANDOM EVENTS
		# ==========================================
		"botnet_attack": {
			"display_name": "Botnet Attack",
			"trigger_type": "random",
			"weight": 0.1,
			"duration_minutes": 120,
			"demand_mult": 1,
			"ddos_add": 800,
			"message": "Emergency: Massive Botnet detected!",
			"seen_before": false,
			"event_is_good": false
		},
		"viral_video": {
			"display_name": "Viral Video",
			"trigger_type": "random",
			"weight": 0.2,
			"duration_minutes": 600,
			"demand_mult": 1.5,
			"ddos_add": 0.0,
			"message": "A tech influencer reviewed your service!",
			"seen_before": false,
			"event_is_good": true
		},
		"competitor_outage": {
			"display_name": "Competitor Outage",
			"trigger_type": "random",
			"weight": 0.2, 
			"duration_minutes": 360, 
			"demand_mult": 2.0, 
			"ddos_add": 0.0,
			"message": "A rival cloud provider went down! Sudden traffic influx!",
			"seen_before": false,
			"event_is_good": true
		},
		"crypto_boom": {
			"display_name": "Crypto Mining Boom",
			"trigger_type": "random",
			"weight": 0.1,
			"duration_minutes": 2880, 
			"demand_mult": 3.0,
			"ddos_add": 0.0,
			"message": "Market surge! Crypto-bros are renting all available compute!",
			"seen_before": false,
			"event_is_good": true
		},
		"pr_disaster": {
			"display_name": "Data Leak Rumor",
			"trigger_type": "random",
			"weight": 0.3,
			"duration_minutes": 720, 
			"demand_mult": 0.5, 
			"ddos_add": 0.0,
			"message": "A false rumor about data loss caused clients to pause traffic.",
			"seen_before": false,
			"event_is_good": false
		},
		"zero_day_exploit": {
			"display_name": "Zero-Day Exploit",
			"trigger_type": "random",
			"weight": 0.2,
			"duration_minutes": 120, 
			"demand_mult": 1.0,
			"ddos_add": 2500.0, 
			"message": "CRITICAL: Global Zero-Day attack targeting your network!",
			"seen_before": false,
			"event_is_good": false
		},
		"fiber_cut": {
			"display_name": "Accidental Fiber Cut",
			"trigger_type": "random",
			"weight": 0.2,
			"duration_minutes": 240, # 4 hours to repair
			"demand_mult": 0.2, # Traffic plummets because no one can reach you
			"ddos_add": 0.0,
			"message": "A construction crew severed a major uplink! Capacity severely reduced.",
			"seen_before": false,
			"event_is_good": false
		},
		"indie_game_launch": {
			"display_name": "Indie Game Launch",
			"trigger_type": "random",
			"weight": 0.4,
			"duration_minutes": 1440, 
			"demand_mult": 2.5, 
			"ddos_add": 0.0,
			"message": "A game hosted on your servers just went viral on social media!",
			"seen_before": false,
			"event_is_good": true
		},
		"scraper_swarm": {
			"display_name": "AI Scraper Swarm",
			"trigger_type": "random",
			"weight": 0.3,
			"duration_minutes": 300, # 5 hours
			"demand_mult": 1.0, 
			"ddos_add": 800.0, # Medium DDoS equivalent
			"message": "Aggressive AI bots are scraping client data. Junk traffic incoming!",
			"seen_before": false,
			"event_is_good": false
		}
	}

func reset_runtime_state(map_scene_path: String = "") -> void:
	time = 360.0
	time_scale = 12.0
	current_day = int(time / 1440) + 1
	servers_active = true
	total_minutes_today = time

	market_demand = 60.0
	organic_growth_rate = 0.01
	max_load = starting_traffic_capacity_mbps
	market_demand = max_load * clamp(starting_load_ratio, 0.1, 1.2)
	organic_growth_rate = traffic_growth_rate
	current_load = max_load * clamp(starting_load_ratio, 0.1, 1.2)
	ddos_load = 0.0
	target_ratio = min_rps_ratio
	current_display_ratio = 1.0
	total_active_traffic = 0
	legit_rps = 0.0
	ddos_rps = 0.0
	jitter = 0
	traffic_volatility_state = 0.0
	traffic_ramp_elapsed_minutes = 0.0
	traffic_ramp_started = false
	discovered_capacity_rps = max_load * clamp(starting_load_ratio, 0.05, 1.0)
	discovery_start_capacity_rps = discovered_capacity_rps
	discovery_target_capacity_rps = max(max_load, discovered_capacity_rps)
	discovery_progress = 0.0

	revenue = _get_economy_starting_money(starting_money)
	income_rate = 0.0
	datacenter_reputation = clamp(starting_reputation, 0.0, 100.0)
	reputation_incident_stress = 0.0
	irreparable_timer_seconds = 0.0
	is_game_over = false
	game_over_reason = ""

	datacenter_capacity_rps = max_load
	incoming_valid_rps = 0.0
	incoming_invalid_rps = 0.0
	incoming_total_rps = 0.0
	handled_valid_rps = 0.0
	handled_invalid_rps = 0.0
	handled_total_rps = 0.0
	dropped_rps = 0.0
	dropped_ratio = 0.0
	dropped_pre_wire_rps = 0.0
	dropped_wire_bottleneck_rps = 0.0
	drop_cause_summary = "None"
	total_incoming_requests = 0.0
	total_processed_requests = 0.0
	total_dropped_requests = 0.0
	active_overdrive_coolers = 0
	online_server_capacity_units = 0
	online_router_capacity_units = 0
	active_cluster_count = 0
	capacity_bottleneck = "Balanced"

	active_event_id = ""
	event_expiry_time = -1.0
	applied_demand_bonus = 0.0
	applied_ddos_bonus = 0.0
	last_roll_hour = -1
	gameplay_started_flag = false
	prep_countdown_active = false
	prep_countdown_remaining_seconds = default_prep_countdown_seconds
	prep_countdown_last_logged_second = -1
	if not map_scene_path.is_empty():
		current_map_scene_path = map_scene_path

	save_dirty_mark_accumulator = 0.0
	money_changed.emit(revenue)
	reputation_changed.emit(datacenter_reputation)
	prep_state_changed.emit(prep_countdown_remaining_seconds, prep_countdown_active)



func _process(delta: float) -> void:
	var tree := get_tree()
	if tree != null and tree.paused:
		return

	if not gameplay_started_flag:
		if prep_countdown_active:
			prep_countdown_remaining_seconds = max(prep_countdown_remaining_seconds - delta, 0.0)
			prep_state_changed.emit(prep_countdown_remaining_seconds, prep_countdown_active)
			var remaining_second := int(ceil(prep_countdown_remaining_seconds))
			if remaining_second != prep_countdown_last_logged_second:
				prep_countdown_last_logged_second = remaining_second
			if prep_countdown_remaining_seconds <= 0.0:
				start_gameplay()
		return

	# ============================================
	# 1. TIME AND EVENT LOGIC
	# ============================================
	time += delta * time_scale
	current_day = (int((time - 360) / 1440) + 1)


	total_minutes_today = fmod(time, 1440.0)
	var hours_24 = int(total_minutes_today / 60)

	# --- 1. HOURLY TICK ---
	# We check this every time the hour changes
	if hours_24 != last_roll_hour:
		last_roll_hour = hours_24
		check_for_events(current_day, hours_24)

	# --- 2. EXPIRY CHECK ---
	if active_event_id != "" and time >= event_expiry_time:
		end_active_event()

	# ============================================
	# 2. TRAFFIC LOGIC (Asymmetric 16/8 Cycle)
	# ============================================
	var online_servers := _get_online_servers()
	var online_routers := _get_online_routers()
	_refresh_datacenter_capacity(online_servers, online_routers)
	var has_online_network: bool = not online_servers.is_empty()
	if has_online_network and not traffic_ramp_started:
		traffic_ramp_started = true
		traffic_ramp_elapsed_minutes = 0.0
	if traffic_ramp_started:
		traffic_ramp_elapsed_minutes += max(delta, 0.0) / 60.0
	var ramp_minutes_setting: float = _get_economy_traffic_ramp_setting("traffic_ramp_minutes_to_max", traffic_ramp_minutes_to_max)
	var ramp_multiplier_max_setting: float = _get_economy_traffic_ramp_setting("traffic_ramp_multiplier_max", traffic_ramp_multiplier_max)
	var ramp_curve_exponent_setting: float = _get_economy_traffic_ramp_setting("traffic_ramp_curve_exponent", traffic_ramp_curve_exponent)
	var overload_ceiling_ratio_setting: float = _get_economy_traffic_ramp_setting("traffic_overload_ceiling_ratio", traffic_overload_ceiling_ratio)

	var effective_capacity: float = max(max_load, 0.0)
	if effective_capacity > discovery_target_capacity_rps * 1.01:
		discovery_start_capacity_rps = max(discovered_capacity_rps, 0.0)
		discovery_target_capacity_rps = effective_capacity
		discovery_progress = 0.0

	if discovery_progress < 1.0:
		var discovery_alpha: float = clamp(delta / max(capacity_discovery_duration_seconds, 0.001), 0.0, 1.0)
		discovery_progress = clamp(discovery_progress + discovery_alpha, 0.0, 1.0)
		var smooth_progress: float = discovery_progress * discovery_progress * (3.0 - (2.0 * discovery_progress))
		discovered_capacity_rps = lerp(discovery_start_capacity_rps, discovery_target_capacity_rps, smooth_progress)
	else:
		discovered_capacity_rps = max(discovered_capacity_rps, discovery_target_capacity_rps)

	var demand_capacity_basis: float = max(discovered_capacity_rps, effective_capacity)
	var ramp_minutes: float = max(ramp_minutes_setting, 0.001)
	var ramp_progress: float = clamp(traffic_ramp_elapsed_minutes / ramp_minutes, 0.0, 1.0)
	var ramp_curve: float = pow(ramp_progress, max(ramp_curve_exponent_setting, 0.05))
	var ramp_multiplier: float = lerp(1.0, max(ramp_multiplier_max_setting, 1.0), ramp_curve)
	var day_growth_multiplier: float = pow(1.0 + max(daily_demand_growth_multiplier, 0.0), max(float(current_day - 1), 0.0))
	var demand_baseline: float = demand_capacity_basis * max(baseline_demand_capacity_ratio, 0.0) * ramp_multiplier * day_growth_multiplier
	var demand_follow_alpha_up: float = clamp(delta * max(demand_capacity_follow_speed, 0.0), 0.0, 1.0)
	var demand_follow_alpha_down: float = clamp(delta * max(demand_capacity_follow_speed, 0.0) * 0.08, 0.0, 1.0)
	if market_demand < demand_baseline:
		market_demand = lerp(market_demand, demand_baseline, demand_follow_alpha_up)
	else:
		market_demand = lerp(market_demand, demand_baseline, demand_follow_alpha_down)
	market_demand += (demand_capacity_basis * max(organic_growth_rate, 0.0) * delta) * (time_scale / 12.0) * day_growth_multiplier

	var current_h = total_minutes_today / 60.0
	var peak_h = 19.5 # 7:30 PM (Prime Time)
	var low_h = 3.5   # 3:30 AM (Dead of night)
	
	var t = 0.0 # Our progress variable (0.0 to 1.0)
	
	if current_h >= low_h and current_h < peak_h:
		# WAKING PHASE: From 3:30 AM to 7:30 PM (16 Hours)
		# This is where traffic climbs and stays high for the workday.
		t = (current_h - low_h) / (peak_h - low_h)
	else:
		# SLEEPING PHASE: From 7:30 PM back to 3:30 AM (8 Hours)
		# Traffic drops quickly as people go to bed.
		var time_since_peak = fmod(current_h - peak_h + 24.0, 24.0)
		var sleep_duration = 24.0 - (peak_h - low_h)
		t = 1.0 - (time_since_peak / sleep_duration)

	# Smooth the linear 't' using a Cosine curve to prevent "sharp" corners
	# This creates the "S-Curve" look where it picks up slowly at 7 AM
	var smooth_t = (1.0 - cos(t * PI)) / 2.0
	
	# Blend daily cycle between configurable floor and peak multipliers.
	var floor_mult: float = max(traffic_floor_ratio, 0.0)
	var peak_mult: float = max(traffic_peak_ratio, floor_mult)
	var time_of_day_mult = floor_mult + (peak_mult - floor_mult) * smooth_t

	var volatility_target: float = randf_range(-traffic_volatility_ratio, traffic_volatility_ratio)
	var volatility_alpha: float = clamp(delta * max(traffic_volatility_change_speed, 0.0), 0.0, 1.0)
	traffic_volatility_state = lerp(traffic_volatility_state, volatility_target, volatility_alpha)

	var target_load = market_demand * time_of_day_mult * (1.0 + traffic_volatility_state)
	var max_valid_incoming_rps: float = max(max(demand_capacity_basis, effective_capacity) * max(overload_ceiling_ratio_setting, 1.0), 1.0)
	var load_response_alpha: float = clamp(delta * max(traffic_response_speed, 0.0), 0.0, 1.0)
	current_load = lerp(clamp(current_load, 0.0, max_valid_incoming_rps), clamp(target_load, 0.0, max_valid_incoming_rps), load_response_alpha)
		


	if servers_active:
		total_active_traffic = int(round(max(current_load + ddos_load, 0.0)))
	else:
		total_active_traffic = 0

	datacenter_capacity_rps = max(max_load, 0.0)
	incoming_valid_rps = max(current_load, 0.0)
	incoming_invalid_rps = max(ddos_load, 0.0)
	incoming_total_rps = incoming_valid_rps + incoming_invalid_rps
	var cluster_allocations: Array = _build_cluster_allocations(online_servers, online_routers, incoming_total_rps)
	active_cluster_count = cluster_allocations.size()

	if servers_active:
		active_overdrive_coolers = _count_active_overdrive_coolers()
		handled_total_rps = _sum_cluster_handled_rps(cluster_allocations)
	else:
		active_overdrive_coolers = 0
		handled_total_rps = 0.0
		cluster_allocations = []

	var handled_pre_wire_rps: float = handled_total_rps

	_reset_network_cable_utilization()
	var server_flow_map: Dictionary = _apply_server_request_load(cluster_allocations)
	server_flow_map = _apply_network_cable_capacity_limits(server_flow_map)
	_apply_server_flow_map(server_flow_map)
	if servers_active:
		handled_total_rps = _sum_server_flow_rps(server_flow_map)
	else:
		handled_total_rps = 0.0
	_apply_router_request_load(cluster_allocations)
	_apply_network_cable_flow_utilization(server_flow_map)
	_apply_power_cable_utilization()
	dropped_pre_wire_rps = max(incoming_total_rps - handled_pre_wire_rps, 0.0)
	dropped_wire_bottleneck_rps = max(handled_pre_wire_rps - handled_total_rps, 0.0)

	dropped_rps = max(incoming_total_rps - handled_total_rps, 0.0)
	if incoming_total_rps > 0.0:
		dropped_ratio = dropped_rps / incoming_total_rps
	else:
		dropped_ratio = 0.0

	if dropped_rps <= 0.01:
		drop_cause_summary = "None"
	elif active_cluster_count <= 0:
		drop_cause_summary = "No route to internet"
	elif dropped_wire_bottleneck_rps > dropped_pre_wire_rps * 1.1 and dropped_wire_bottleneck_rps > 1.0:
		drop_cause_summary = "Wire bottleneck"
	elif dropped_pre_wire_rps > dropped_wire_bottleneck_rps * 1.1 and dropped_pre_wire_rps > 1.0:
		drop_cause_summary = "Server/cluster capacity"
	else:
		drop_cause_summary = "Mixed bottleneck"

	var valid_share: float = 0.0
	if incoming_total_rps > 0.0:
		valid_share = incoming_valid_rps / incoming_total_rps
	handled_valid_rps = handled_total_rps * valid_share
	handled_invalid_rps = handled_total_rps - handled_valid_rps
	total_incoming_requests += incoming_total_rps * delta
	total_processed_requests += handled_total_rps * delta
	total_dropped_requests += dropped_rps * delta

	# Preserve existing HUD fields while transitioning to request-centric telemetry.
	legit_rps = handled_valid_rps
	ddos_rps = incoming_invalid_rps

	
	# ============================================
	# 3. MONEY LOGIC
	# ============================================
	if servers_active:
		# --- Revenue (Handled Valid Requests Only) ---
		var raw_revenue = handled_valid_rps * revenue_per_valid_handled_request
		
		# Apply Heat Penalty
		# sla_multiplier = calculate_sla_multiplier(temperature)
		var adjusted_revenue = raw_revenue * sla_multiplier
		
		# --- Expenses (Handled Requests) ---
		var valid_processing_expenses: float = handled_valid_rps * server_power_cost
		var invalid_processing_expenses: float = handled_invalid_rps * server_power_cost * invalid_request_power_cost_multiplier
		var server_expenses = valid_processing_expenses + invalid_processing_expenses
		server_expenses += float(active_overdrive_coolers) * cooler_overdrive_power_cost
		
		income_rate = (adjusted_revenue - server_expenses) * time_scale
		
		# Update RPS UI
		jitter = randf_range(-0.5, 0.5) if incoming_total_rps > 1000 else 0.0

	else:
		# --- Shutdown State ---
		# You pay "Idle Power" costs but make $0 revenue
		income_rate = -(max_load * offline_idle_drain_per_capacity) * offline_idle_drain_multiplier


	# Update Global Cash
	revenue += income_rate * delta
	money_changed.emit(revenue)

	_update_reputation_and_failure(delta)
	if is_game_over:
		return

	save_dirty_mark_accumulator += delta
	if save_dirty_mark_accumulator >= 1.0:
		save_dirty_mark_accumulator = 0.0
		if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
			SaveManager.mark_runtime_dirty()

func _get_economy_traffic_ramp_setting(setting_name: String, fallback_value: float) -> float:
	var economy_config: Node = get_node_or_null("/root/EconomyConfig")
	if economy_config != null and economy_config.has_method("get_traffic_ramp_setting"):
		return float(economy_config.call("get_traffic_ramp_setting", setting_name, fallback_value))
	return fallback_value

func _get_economy_starting_money(fallback_value: float) -> float:
	var economy_config: Node = get_node_or_null("/root/EconomyConfig")
	if economy_config != null and economy_config.has_method("get_starting_money"):
		return float(economy_config.call("get_starting_money", fallback_value))
	return fallback_value

func _update_reputation_and_failure(delta: float) -> void:
	var sim_speed: float = float(time_scale) / 12.0
	var sim_delta: float = max(delta * sim_speed, 0.0)

	var previous_reputation: float = datacenter_reputation

	if is_game_over:
		reputation_changed.emit(datacenter_reputation)
		return

	if servers_active and incoming_total_rps > 0.0:
		var softened_drop: float = pow(clamp(dropped_ratio, 0.0, 1.0), max(reputation_soft_drop_exponent, 0.1))
		var any_drop_ratio: float = clamp((dropped_ratio - 0.01) / 0.99, 0.0, 1.0)
		var threshold_overshoot: float = max(dropped_ratio - reputation_threshold_drop_start, 0.0)
		var stress_gain: float = (threshold_overshoot + (softened_drop * 0.25)) * max(reputation_incident_buildup_rate, 0.0) * sim_delta
		var stress_decay_factor: float = 1.0 - clamp(threshold_overshoot * 4.0, 0.0, 1.0)
		var stress_loss: float = max(reputation_incident_decay_per_second, 0.0) * stress_decay_factor * sim_delta
		reputation_incident_stress = clamp(reputation_incident_stress + stress_gain - stress_loss, 0.0, 1.0)

		var incident_multiplier: float = 1.0 + (max(reputation_incident_multiplier_max, 1.0) - 1.0) * reputation_incident_stress
		var any_drop_decay: float = any_drop_ratio * max(reputation_any_drop_penalty_per_second, 0.0) * sim_delta
		var base_decay: float = softened_drop * reputation_decay_per_second * sim_delta
		var threshold_decay: float = threshold_overshoot * reputation_threshold_penalty_per_second * sim_delta
		datacenter_reputation -= any_drop_decay + ((base_decay + threshold_decay) * incident_multiplier)

		if dropped_ratio <= reputation_recovery_drop_ratio_max:
			datacenter_reputation += reputation_recovery_per_second * sim_delta * lerp(1.0, 0.5, reputation_incident_stress)
			reputation_incident_stress = max(reputation_incident_stress - max(reputation_incident_decay_per_second, 0.0) * sim_delta, 0.0)
	else:
		datacenter_reputation += reputation_recovery_per_second * 0.5 * sim_delta
		reputation_incident_stress = max(reputation_incident_stress - max(reputation_incident_decay_per_second, 0.0) * 1.5 * sim_delta, 0.0)

	datacenter_reputation = clamp(datacenter_reputation, 0.0, 100.0)

	if datacenter_reputation <= irreparable_threshold:
		irreparable_timer_seconds += sim_delta
		if irreparable_timer_seconds >= irreparable_duration_seconds and not is_game_over:
			is_game_over = true
			game_over_reason = "Datacenter reputation became irreparable"
			game_over_state_changed.emit(game_over_reason)
	else:
		irreparable_timer_seconds = 0.0

	if not is_equal_approx(previous_reputation, datacenter_reputation):
		reputation_changed.emit(datacenter_reputation)
	

func check_for_events(day, hour):
	if hour == 6:
		for id in EVENTS:
			var ev = EVENTS[id]
			if ev.get("trigger_type") == "calendar" and ev.get("target_day") == day:
				end_active_event()
				start_event(id)
				return 

	if active_event_id != "": return

	var roll = randf_range(0.0, 100.0)
	var cumulative_weight = 0.0

	for id in EVENTS:
		var ev = EVENTS[id]
		# Use .get() with a default of 0 to prevent crashing on missing weights
		if ev.get("trigger_type") == "random":
			var event_weight = ev.get("weight", 0.0)
			cumulative_weight += event_weight

			if roll < cumulative_weight:
				start_event(id)
				return

func start_event(event_id: String):
	if active_event_id != "": 
		return

	var data = EVENTS[event_id]
	active_event_id = event_id
	
	# Calculate Bonuses
	applied_demand_bonus = market_demand * (data.demand_mult - 1.0)
	applied_ddos_bonus = min(max_load, data.ddos_add)
	
	# Apply Bonuses
	market_demand += applied_demand_bonus
	ddos_load += applied_ddos_bonus
	
	event_expiry_time = time + data.duration_minutes

	if data.get("seen_before", false) == false:
		show_event_popup.emit(data)
		# Mark it as seen so we don't spam the player next time
		data["seen_before"] = true


	


func end_active_event():
	if active_event_id == "": return
	
	# Revert the specific amounts we added
	market_demand -= applied_demand_bonus
	ddos_load -= applied_ddos_bonus
	

	
	# Reset tracking
	active_event_id = ""
	event_expiry_time = -1.0
	applied_demand_bonus = 0.0
	applied_ddos_bonus = 0.0

func get_active_event_name() -> String:
	if active_event_id == "":
		return "None"
	return EVENTS[active_event_id].display_name

func increase_demand():
	market_demand *= 1.5

func dev_server_upgrade():
	max_load = max_load * 1.5

func begin_prep_countdown(duration_seconds: float = 30.0) -> void:
	prep_countdown_remaining_seconds = max(duration_seconds, 0.0)
	prep_countdown_active = true
	gameplay_started_flag = false
	prep_countdown_last_logged_second = int(ceil(prep_countdown_remaining_seconds))
	prep_state_changed.emit(prep_countdown_remaining_seconds, prep_countdown_active)

func start_gameplay() -> void:
	prep_countdown_remaining_seconds = 0.0
	prep_countdown_active = false
	gameplay_started_flag = true
	prep_countdown_last_logged_second = 0
	prep_state_changed.emit(prep_countdown_remaining_seconds, prep_countdown_active)
	gameplay_started.emit()

func is_gameplay_started() -> bool:
	return gameplay_started_flag

func is_prep_countdown_active() -> bool:
	return prep_countdown_active

func get_prep_countdown_remaining_seconds() -> float:
	return prep_countdown_remaining_seconds

func speed_time():
	if time_scale == 12.0:
		time_scale = 1200.0
	else:
		time_scale = 12.0 

func can_afford(amount: float) -> bool:
	return revenue >= amount

func spend_money(amount: float) -> bool:
	if not can_afford(amount):
		return false

	revenue -= amount
	money_changed.emit(revenue)
	return true

func add_money(amount: float) -> void:
	revenue += amount
	money_changed.emit(revenue)

func get_money() -> float:
	return revenue

func export_runtime_state() -> Dictionary:
	return {
		"time": time,
		"time_scale": time_scale,
		"current_day": current_day,
		"servers_active": servers_active,
		"total_minutes_today": total_minutes_today,
		"market_demand": market_demand,
		"organic_growth_rate": organic_growth_rate,
		"max_load": max_load,
		"current_load": current_load,
		"ddos_load": ddos_load,
		"target_ratio": target_ratio,
		"current_display_ratio": current_display_ratio,
		"total_active_traffic": total_active_traffic,
		"legit_rps": legit_rps,
		"ddos_rps": ddos_rps,
		"jitter": jitter,
		"traffic_ramp_elapsed_minutes": traffic_ramp_elapsed_minutes,
		"traffic_ramp_started": traffic_ramp_started,
		"discovered_capacity_rps": discovered_capacity_rps,
		"discovery_start_capacity_rps": discovery_start_capacity_rps,
		"discovery_target_capacity_rps": discovery_target_capacity_rps,
		"discovery_progress": discovery_progress,
		"online_server_capacity_units": online_server_capacity_units,
		"online_router_capacity_units": online_router_capacity_units,
		"active_cluster_count": active_cluster_count,
		"capacity_bottleneck": capacity_bottleneck,
		"revenue": revenue,
		"income_rate": income_rate,
		"datacenter_capacity_rps": datacenter_capacity_rps,
		"incoming_valid_rps": incoming_valid_rps,
		"incoming_invalid_rps": incoming_invalid_rps,
		"incoming_total_rps": incoming_total_rps,
		"handled_valid_rps": handled_valid_rps,
		"handled_invalid_rps": handled_invalid_rps,
		"handled_total_rps": handled_total_rps,
		"dropped_rps": dropped_rps,
		"dropped_ratio": dropped_ratio,
		"dropped_pre_wire_rps": dropped_pre_wire_rps,
		"dropped_wire_bottleneck_rps": dropped_wire_bottleneck_rps,
		"drop_cause_summary": drop_cause_summary,
		"total_incoming_requests": total_incoming_requests,
		"total_processed_requests": total_processed_requests,
		"total_dropped_requests": total_dropped_requests,
		"active_overdrive_coolers": active_overdrive_coolers,
		"datacenter_reputation": datacenter_reputation,
		"reputation_incident_stress": reputation_incident_stress,
		"irreparable_timer_seconds": irreparable_timer_seconds,
		"is_game_over": is_game_over,
		"game_over_reason": game_over_reason,
		"active_event_id": active_event_id,
		"event_expiry_time": event_expiry_time,
		"applied_demand_bonus": applied_demand_bonus,
		"applied_ddos_bonus": applied_ddos_bonus,
		"last_roll_hour": last_roll_hour,
		"current_map_scene_path": current_map_scene_path,
		"gameplay_started_flag": gameplay_started_flag,
		"prep_countdown_active": prep_countdown_active,
		"prep_countdown_remaining_seconds": prep_countdown_remaining_seconds
	}

func import_runtime_state(state: Dictionary) -> void:
	time = float(state.get("time", time))
	time_scale = float(state.get("time_scale", time_scale))
	current_day = int(state.get("current_day", current_day))
	servers_active = bool(state.get("servers_active", servers_active))
	total_minutes_today = float(state.get("total_minutes_today", total_minutes_today))
	market_demand = float(state.get("market_demand", market_demand))
	organic_growth_rate = float(state.get("organic_growth_rate", organic_growth_rate))
	max_load = float(state.get("max_load", max_load))
	current_load = float(state.get("current_load", current_load))
	ddos_load = float(state.get("ddos_load", ddos_load))
	target_ratio = float(state.get("target_ratio", target_ratio))
	current_display_ratio = float(state.get("current_display_ratio", current_display_ratio))
	total_active_traffic = int(state.get("total_active_traffic", total_active_traffic))
	legit_rps = float(state.get("legit_rps", legit_rps))
	ddos_rps = float(state.get("ddos_rps", ddos_rps))
	jitter = float(state.get("jitter", jitter))
	traffic_ramp_elapsed_minutes = float(state.get("traffic_ramp_elapsed_minutes", traffic_ramp_elapsed_minutes))
	traffic_ramp_started = bool(state.get("traffic_ramp_started", traffic_ramp_started))
	discovered_capacity_rps = float(state.get("discovered_capacity_rps", discovered_capacity_rps))
	discovery_start_capacity_rps = float(state.get("discovery_start_capacity_rps", discovery_start_capacity_rps))
	discovery_target_capacity_rps = float(state.get("discovery_target_capacity_rps", discovery_target_capacity_rps))
	discovery_progress = float(state.get("discovery_progress", discovery_progress))
	online_server_capacity_units = int(state.get("online_server_capacity_units", online_server_capacity_units))
	online_router_capacity_units = int(state.get("online_router_capacity_units", online_router_capacity_units))
	active_cluster_count = int(state.get("active_cluster_count", active_cluster_count))
	capacity_bottleneck = String(state.get("capacity_bottleneck", capacity_bottleneck))
	revenue = float(state.get("revenue", revenue))
	income_rate = float(state.get("income_rate", income_rate))
	datacenter_capacity_rps = float(state.get("datacenter_capacity_rps", datacenter_capacity_rps))
	incoming_valid_rps = float(state.get("incoming_valid_rps", incoming_valid_rps))
	incoming_invalid_rps = float(state.get("incoming_invalid_rps", incoming_invalid_rps))
	incoming_total_rps = float(state.get("incoming_total_rps", incoming_total_rps))
	handled_valid_rps = float(state.get("handled_valid_rps", handled_valid_rps))
	handled_invalid_rps = float(state.get("handled_invalid_rps", handled_invalid_rps))
	handled_total_rps = float(state.get("handled_total_rps", handled_total_rps))
	dropped_rps = float(state.get("dropped_rps", dropped_rps))
	dropped_ratio = float(state.get("dropped_ratio", dropped_ratio))
	dropped_pre_wire_rps = float(state.get("dropped_pre_wire_rps", dropped_pre_wire_rps))
	dropped_wire_bottleneck_rps = float(state.get("dropped_wire_bottleneck_rps", dropped_wire_bottleneck_rps))
	drop_cause_summary = String(state.get("drop_cause_summary", drop_cause_summary))
	total_incoming_requests = float(state.get("total_incoming_requests", total_incoming_requests))
	total_processed_requests = float(state.get("total_processed_requests", total_processed_requests))
	total_dropped_requests = float(state.get("total_dropped_requests", total_dropped_requests))
	active_overdrive_coolers = int(state.get("active_overdrive_coolers", active_overdrive_coolers))
	datacenter_reputation = float(state.get("datacenter_reputation", datacenter_reputation))
	reputation_incident_stress = float(state.get("reputation_incident_stress", reputation_incident_stress))
	irreparable_timer_seconds = float(state.get("irreparable_timer_seconds", irreparable_timer_seconds))
	is_game_over = bool(state.get("is_game_over", is_game_over))
	game_over_reason = String(state.get("game_over_reason", game_over_reason))
	active_event_id = String(state.get("active_event_id", active_event_id))
	event_expiry_time = float(state.get("event_expiry_time", event_expiry_time))
	applied_demand_bonus = float(state.get("applied_demand_bonus", applied_demand_bonus))
	applied_ddos_bonus = float(state.get("applied_ddos_bonus", applied_ddos_bonus))
	last_roll_hour = int(state.get("last_roll_hour", last_roll_hour))
	current_map_scene_path = String(state.get("current_map_scene_path", current_map_scene_path))
	gameplay_started_flag = bool(state.get("gameplay_started_flag", gameplay_started_flag))
	prep_countdown_active = bool(state.get("prep_countdown_active", prep_countdown_active))
	prep_countdown_remaining_seconds = float(state.get("prep_countdown_remaining_seconds", prep_countdown_remaining_seconds))
	money_changed.emit(revenue)
	reputation_changed.emit(datacenter_reputation)
	prep_state_changed.emit(prep_countdown_remaining_seconds, prep_countdown_active)

func _count_active_overdrive_coolers() -> int:
	var tree := get_tree()
	if tree == null:
		return 0

	var total := 0
	for node in tree.get_nodes_in_group("cooling_units"):
		if node != null and node.has_method("is_overdrive_active") and bool(node.call("is_overdrive_active")):
			total += 1
	return total

func _get_online_servers() -> Array:
	var tree := get_tree()
	if tree == null:
		return []

	var result: Array = []
	for node in tree.get_nodes_in_group("network_nodes"):
		if node == null or not node.has_method("is_available_for_traffic"):
			continue
		if bool(node.call("is_available_for_traffic")):
			result.append(node)
	return result

func _get_online_routers() -> Array:
	var tree := get_tree()
	if tree == null:
		return []

	var result: Array = []
	for node in tree.get_nodes_in_group("network_nodes"):
		if node == null or not node.has_method("is_available_for_routing"):
			continue
		if bool(node.call("is_available_for_routing")):
			result.append(node)
	return result

func _refresh_datacenter_capacity(online_servers: Array, online_routers: Array) -> void:
	var total_server_units: int = 0
	var total_server_capacity_rps: float = 0.0
	for server in online_servers:
		total_server_units += _get_capacity_units_for(server)
		total_server_capacity_rps += _get_node_capacity_rps(server)

	online_server_capacity_units = total_server_units

	var total_router_units: int = 0
	for router in online_routers:
		total_router_units += _get_capacity_units_for(router)

	online_router_capacity_units = total_router_units
	max_load = max(total_server_capacity_rps, 0.0)

	if total_server_capacity_rps > 0.0:
		capacity_bottleneck = "Server"
	else:
		capacity_bottleneck = "Balanced"

func _build_cluster_allocations(online_servers: Array, online_routers: Array, incoming_rps: float) -> Array:
	var clusters: Array = []
	if online_routers.is_empty():
		return clusters

	var visited_nodes: Dictionary = {}
	var server_set: Dictionary = {}
	var router_set: Dictionary = {}
	for server in online_servers:
		server_set[server] = true
	for router in online_routers:
		router_set[router] = true

	for router in online_routers:
		if visited_nodes.has(router):
			continue

		var queue: Array = [router]
		var cluster_servers: Array = []
		var cluster_routers: Array = []

		while not queue.is_empty():
			var current = queue.pop_front()
			if current == null or visited_nodes.has(current):
				continue

			visited_nodes[current] = true
			if router_set.has(current):
				cluster_routers.append(current)
			if server_set.has(current):
				cluster_servers.append(current)

			for next_node in _get_network_neighbors(current):
				if next_node != null and _is_cluster_traversable_node(next_node, server_set, router_set) and not visited_nodes.has(next_node):
					queue.append(next_node)

		if cluster_routers.is_empty():
			continue

		var server_capacity_rps: float = 0.0
		for cluster_server in cluster_servers:
			server_capacity_rps += _get_node_capacity_rps(cluster_server)

		var capacity_rps: float = server_capacity_rps

		clusters.append({
			"routers": cluster_routers,
			"servers": cluster_servers,
			"capacity_rps": capacity_rps,
			"incoming_rps": 0.0,
			"handled_rps": 0.0
		})

	var total_capacity_rps: float = 0.0
	for cluster_entry in clusters:
		total_capacity_rps += float(cluster_entry.get("capacity_rps", 0.0))

	if total_capacity_rps <= 0.0 or incoming_rps <= 0.0:
		return clusters

	for cluster_entry in clusters:
		var capacity_rps: float = float(cluster_entry.get("capacity_rps", 0.0))
		var share: float = capacity_rps / total_capacity_rps
		var cluster_incoming_rps: float = incoming_rps * share
		cluster_entry["incoming_rps"] = cluster_incoming_rps
		cluster_entry["handled_rps"] = min(cluster_incoming_rps, capacity_rps)

	return clusters

func _sum_cluster_handled_rps(clusters: Array) -> float:
	var total: float = 0.0
	for cluster_entry in clusters:
		total += float(cluster_entry.get("handled_rps", 0.0))
	return total

func _apply_server_request_load(cluster_allocations: Array) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var server_flow_map: Dictionary = {}

	for node in tree.get_nodes_in_group("network_nodes"):
		if node == null or String(node.get("network_node_type")) != "server":
			continue
		if node.has_method("set_request_load_rps"):
			node.call("set_request_load_rps", 0.0)
		if node.has_method("set_network_traffic_ratio"):
			node.call("set_network_traffic_ratio", 0.0)

	for cluster_entry in cluster_allocations:
		var cluster_servers: Array = cluster_entry.get("servers", [])
		if cluster_servers.is_empty():
			continue

		var cluster_handled_rps: float = float(cluster_entry.get("handled_rps", 0.0))
		var cluster_capacity_rps: float = 0.0
		for server in cluster_servers:
			cluster_capacity_rps += _get_node_capacity_rps(server)

		if cluster_capacity_rps <= 0.0 or cluster_handled_rps <= 0.0:
			continue

		for server in cluster_servers:
			var server_capacity_rps: float = _get_node_capacity_rps(server)
			var share: float = server_capacity_rps / cluster_capacity_rps
			var server_handled_rps: float = cluster_handled_rps * share
			var server_ratio: float = clamp(server_handled_rps / max(server_capacity_rps, 0.01), 0.0, 1.0)

			if server.has_method("set_request_load_rps"):
				server.call("set_request_load_rps", server_handled_rps)
			if server.has_method("set_network_traffic_ratio"):
				server.call("set_network_traffic_ratio", server_ratio)

			server_flow_map[server] = max(float(server_flow_map.get(server, 0.0)), server_handled_rps)

	return server_flow_map

func _apply_router_request_load(cluster_allocations: Array) -> void:
	var tree := get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("network_nodes"):
		if node == null or not node.has_method("is_available_for_routing"):
			continue
		if node.has_method("set_network_traffic_ratio"):
			node.call("set_network_traffic_ratio", 0.0)

	for cluster_entry in cluster_allocations:
		var cluster_routers: Array = cluster_entry.get("routers", [])
		if cluster_routers.is_empty():
			continue

		var cluster_handled_rps: float = float(cluster_entry.get("handled_rps", 0.0))
		if cluster_handled_rps <= 0.0:
			continue

		var cluster_pressure_ratio: float = clamp(cluster_handled_rps / max(max_load, 0.01), 0.0, 1.0)
		for router in cluster_routers:
			var router_ratio: float = cluster_pressure_ratio

			if router.has_method("set_network_traffic_ratio"):
				router.call("set_network_traffic_ratio", router_ratio)


func _apply_network_cable_flow_utilization(server_flow_map: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var segment_flow_rps: Dictionary = _build_segment_flow_map(server_flow_map)

	for segment in tree.get_nodes_in_group("cable_segments"):
		if segment == null:
			continue
		var load_rps: float = float(segment_flow_rps.get(segment, 0.0))
		if segment.has_method("set_traffic_load_rps"):
			segment.call("set_traffic_load_rps", load_rps)
		elif segment.has_method("set_utilization_ratio"):
			var capacity_rps := _get_segment_capacity_rps(segment)
			segment.call("set_utilization_ratio", clamp(load_rps / capacity_rps, 0.0, 1.0))

func _apply_network_cable_capacity_limits(server_flow_map: Dictionary) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}

	if server_flow_map.is_empty():
		return {}

	var desired_segment_loads: Dictionary = _build_segment_flow_map(server_flow_map)
	if desired_segment_loads.is_empty():
		return {}

	var segment_scale: Dictionary = {}
	for segment in desired_segment_loads.keys():
		if segment == null:
			continue
		var load_rps: float = float(desired_segment_loads.get(segment, 0.0))
		if load_rps <= 0.0:
			segment_scale[segment] = 1.0
			continue

		var capacity_rps: float = _get_segment_capacity_rps(segment)
		segment_scale[segment] = clamp(capacity_rps / load_rps, 0.0, 1.0)

	var capped_server_flow: Dictionary = {}
	for server in server_flow_map.keys():
		var desired_rps: float = float(server_flow_map.get(server, 0.0))
		if desired_rps <= 0.0:
			continue

		var path_segments: Array = _find_path_segments_to_internet(server)
		if path_segments.is_empty():
			continue

		var path_scale: float = 1.0
		for segment in path_segments:
			if segment == null:
				continue
			path_scale = min(path_scale, float(segment_scale.get(segment, 1.0)))

		var capped_rps: float = desired_rps * path_scale
		if capped_rps > 0.0:
			capped_server_flow[server] = capped_rps

	return capped_server_flow

func _build_segment_flow_map(server_flow_map: Dictionary) -> Dictionary:
	var segment_flow_rps: Dictionary = {}
	for server in server_flow_map.keys():
		var server_rps: float = float(server_flow_map.get(server, 0.0))
		if server_rps <= 0.0:
			continue

		var path_segments: Array = _find_path_segments_to_internet(server)
		if path_segments.is_empty():
			continue

		for segment in path_segments:
			if segment == null:
				continue
			segment_flow_rps[segment] = float(segment_flow_rps.get(segment, 0.0)) + server_rps

	return segment_flow_rps

func _sum_server_flow_rps(server_flow_map: Dictionary) -> float:
	var total: float = 0.0
	for server in server_flow_map.keys():
		total += float(server_flow_map.get(server, 0.0))
	return total

func _apply_server_flow_map(server_flow_map: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("network_nodes"):
		if node == null or String(node.get("network_node_type")) != "server":
			continue
		var server_rps: float = float(server_flow_map.get(node, 0.0))
		var server_capacity_rps: float = _get_node_capacity_rps(node)
		var server_ratio: float = clamp(server_rps / max(server_capacity_rps, 0.01), 0.0, 1.0)
		if node.has_method("set_request_load_rps"):
			node.call("set_request_load_rps", server_rps)
		if node.has_method("set_network_traffic_ratio"):
			node.call("set_network_traffic_ratio", server_ratio)

func _get_segment_capacity_rps(segment: Object) -> float:
	if segment == null:
		return 1.0
	if segment.has_method("get_max_traffic_capacity_rps"):
		return max(float(segment.call("get_max_traffic_capacity_rps")), 1.0)
	return 1.0

func _reset_network_cable_utilization() -> void:
	var tree := get_tree()
	if tree == null:
		return

	for segment in tree.get_nodes_in_group("cable_segments"):
		if segment == null:
			continue
		if segment.has_method("set_traffic_load_rps"):
			segment.call("set_traffic_load_rps", 0.0)
		elif segment.has_method("set_utilization_ratio"):
			segment.call("set_utilization_ratio", 0.0)

func _apply_power_cable_utilization() -> void:
	var tree := get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("electrical_connectable"):
		if node == null:
			continue

		var utilization: float = 0.0
		if node.has_method("get_network_load_ratio"):
			utilization = max(utilization, float(node.call("get_network_load_ratio")))

		if node.has_method("is_overdrive_active") and bool(node.call("is_overdrive_active")):
			utilization = max(utilization, 1.0)
		elif node.has_method("_is_active") and bool(node.call("_is_active")):
			utilization = max(utilization, 0.35)

		if utilization <= 0.0:
			continue

		var electrical_segments: Variant = node.get("electrical_connected_segments")
		if electrical_segments is Array:
			for segment in electrical_segments:
				if segment == null or not segment.has_method("set_utilization_ratio"):
					continue
				var existing_ratio: float = 0.0
				if segment.has_method("get_utilization_ratio"):
					existing_ratio = float(segment.call("get_utilization_ratio"))
				segment.call("set_utilization_ratio", max(existing_ratio, utilization))

func _get_segments_for_node(node: Object) -> Array:
	var segments: Array = []
	if node == null:
		return segments

	var primary: Variant = node.get("connected_segments")
	if primary is Array:
		for entry in primary:
			if entry != null and not segments.has(entry):
				segments.append(entry)

	var internet: Variant = node.get("internet_connected_segments")
	if internet is Array:
		for entry in internet:
			if entry != null and not segments.has(entry):
				segments.append(entry)

	return segments

func _get_network_neighbors(node: Object) -> Array:
	var neighbors: Array = []
	if node == null:
		return neighbors

	for segment in _get_segments_for_node(node):
		if segment == null or not segment.has_method("get_other_point"):
			continue
		var next_point: Variant = segment.call("get_other_point", node)
		if next_point != null and not neighbors.has(next_point):
			neighbors.append(next_point)

	return neighbors

func _find_path_segments_to_internet(start_node: Object) -> Array:
	var result: Array = []
	if start_node == null:
		return result

	var queue: Array = [start_node]
	var visited: Dictionary = {start_node: true}
	var parent_node: Dictionary = {}
	var parent_segment: Dictionary = {}

	while not queue.is_empty():
		var current: Variant = queue.pop_front()
		if current == null:
			continue

		if String(current.get("network_node_type")) == "internet_source":
			var walker: Variant = current
			while parent_node.has(walker):
				var seg = parent_segment.get(walker, null)
				if seg != null:
					result.push_front(seg)
				walker = parent_node.get(walker, null)
			return result

		for segment in _get_segments_for_node(current):
			if segment == null or not segment.has_method("get_other_point"):
				continue
			var next_node: Variant = segment.call("get_other_point", current)
			if next_node == null or visited.has(next_node):
				continue
			visited[next_node] = true
			parent_node[next_node] = current
			parent_segment[next_node] = segment
			queue.append(next_node)

	return result

func _is_cluster_traversable_node(node: Object, server_set: Dictionary, router_set: Dictionary) -> bool:
	if node == null:
		return false
	if server_set.has(node) or router_set.has(node):
		return true

	var node_type: String = String(node.get("network_node_type"))
	return node_type == "anchor" or node_type == "internet_source"

func _get_capacity_units_for(node: Object) -> int:
	# Backward-compatible helper retained for existing saved/UI fields.
	if node == null:
		return 1
	if not node.has_method("get_capacity_units"):
		return 1

	var raw_units: Variant = node.call("get_capacity_units")
	return max(int(raw_units), 1)

func _get_node_capacity_rps(node: Object) -> float:
	if node == null:
		return 0.0

	if not node.has_method("get_request_capacity_rps"):
		return 0.0

	return max(float(node.call("get_request_capacity_rps")), 1.0)
