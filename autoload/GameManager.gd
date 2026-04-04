extends Node

@export var starting_traffic_capacity_mbps: float = 1000.0
@export var starting_load_ratio: float = 0.1
@export var min_rps_ratio: float = 0.08
@export var max_rps_ratio: float = 0.12
@export var traffic_growth_rate: float = 0.01

# Event Definitions
const EVENTS = {
	"black_friday": {
		"display_name": "Black Friday",
		"trigger_type": "calendar",
		"target_day": 2,          # Happens ONLY on Day 2
		"duration_minutes": 1440, # 24 Hours
		"demand_mult": 2.5,
		"ddos_add": 0,
		"message": "It's Day 2: Black Friday is here!"
	},
	"botnet_attack": {
		"display_name": "Botnet Attack",
		"trigger_type": "random",
		"weight": 1,              # 1% chance when we roll
		"duration_minutes": 60,   # Only lasts 1 in-game hour
		"demand_mult": 1.0,
		"ddos_add": 800,
		"message": "Emergency: Massive Botnet detected!"
	},
	"viral_video": {
		"display_name": "Viral Video",
		"trigger_type": "random",
		"weight": 3, # 2% chance to roll
		"duration_minutes": 1440,
		"demand_mult": 1.5,
		"ddos_add": 0.0,
		"message": "A tech influencer reviewed your service!"
	}
}

# Tracking variables for the CURRENT active event
var active_event_id: String = ""
var event_expiry_time: float = -1.0
var applied_demand_bonus: float = 0.0
var applied_ddos_bonus: float = 0.0
var last_roll_hour = -1

# Game State Variables
var time = 360.0
var time_scale = 12.0 # Min/Sec
var current_day = int(time / 1440) + 1
var servers_active = true
var total_minutes_today = time

# Server-only financial constants
var server_power_cost = 0.0015  # Internal cost to process 1 Mbps 
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

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	max_load = starting_traffic_capacity_mbps
	current_load = max_load * clamp(starting_load_ratio, 0.08, 0.12)
	target_ratio = min_rps_ratio
	current_display_ratio = min_rps_ratio



func _process(delta: float) -> void:
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
	market_demand += (organic_growth_rate * delta) * time_scale

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
	
	# 0.2 is the floor (20% traffic at night), 0.8 is the range
	var time_of_day_mult = 0.2 + 0.8 * smooth_t
	
	var target_load = market_demand * time_of_day_mult

	current_load = lerp(min(max_load - ddos_load, current_load), min(max_load, target_load), delta * 2.0)
		


	if servers_active:
		total_active_traffic = min(max_load, current_load + ddos_load)
	else:
		total_active_traffic = 0

	

	
	# ============================================
	# 3. MONEY LOGIC
	# ============================================
	if servers_active:
		# --- Revenue (Legit Traffic Only) ---
		ddos_rps = ddos_load * current_display_ratio
		legit_rps = current_load * current_display_ratio
		var raw_revenue = (current_load * 0.005) + (legit_rps * 0.001)
		
		# Apply Heat Penalty
		# sla_multiplier = calculate_sla_multiplier(temperature)
		var adjusted_revenue = raw_revenue * sla_multiplier
		
		# --- Expenses (Total Traffic) ---
		var server_expenses = total_active_traffic * server_power_cost
		
		income_rate = (adjusted_revenue - server_expenses) * time_scale
		
		# Update RPS UI
		jitter = randf_range(-0.5, 0.5) if current_load > 1000 else 0.0

	else:
		# --- Shutdown State ---
		# You pay "Idle Power" costs but make $0 revenue
		income_rate = -(max_load * 0.005) * 2.0


	# Update Global Cash
	revenue += income_rate * delta
	





func check_for_events(day, hour):
	if hour == 6:
		for id in EVENTS:
			var ev = EVENTS[id]
			if ev.get("trigger_type") == "calendar" and ev.get("target_day") == day:
				end_active_event()
				start_event(id)
				return 

	if active_event_id != "": return

	var roll = randi() % 100
	for id in EVENTS:
		var ev = EVENTS[id]
		# Use .get() with a default of 0 to prevent crashing on missing weights
		if ev.get("trigger_type") == "random" and roll < ev.get("weight", 0):
			start_event(id)
			break

func start_event(event_id: String):
	if active_event_id != "": 
		print("An event is already active!")
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

	
	print("EVENT STARTED: ", data.display_name, " - ", data.message)

func end_active_event():
	if active_event_id == "": return
	
	# Revert the specific amounts we added
	market_demand -= applied_demand_bonus
	ddos_load -= applied_ddos_bonus
	
	print("EVENT ENDED: ", EVENTS[active_event_id].display_name)
	
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

func speed_time():
	if time_scale == 12.0:
		time_scale = 1200.0
	else:
		time_scale = 12.0 
