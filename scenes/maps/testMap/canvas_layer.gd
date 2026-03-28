extends CanvasLayer


@onready var clock_label = $Control/MarginContainer/HUDContainer/StatsBar/Time
@onready var day_label = $Control/MarginContainer/HUDContainer/StatsBar/Day
@onready var traffic_bar = $Control/MarginContainer/HUDContainer/TrafficContainer/TrafficBar
@onready var rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/HBoxContainer/RPSLabel
@onready var ddos_rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/HBoxContainer/DDoSLabel
@onready var demand_label = $Control/MarginContainer/HUDContainer/TrafficContainer/MDLabel
@onready var event_label = $Control/MarginContainer/HUDContainer/TrafficContainer/EventLabel
@onready var cash_label = $Control/MarginContainer/HUDContainer/MoneyContainer/RevenueLabel
@onready var income_label = $Control/MarginContainer/HUDContainer/MoneyContainer/IncomeLabel
@onready var temp_label = $Control/MarginContainer/HUDContainer/TempContainer/Temp
@onready var speed_button = $Control/MarginContainer/HUDContainer/TestingControls/SpeedButton

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
		"weight": 3,
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
var time_scale = 1.0
var current_day = int(time / 1440) + 1
var servers_active = true
var event_active = false

# Server-only financial constants
var server_power_cost = 0.0015  # Internal cost to process 1 Mbps 
var sla_multiplier = 1.0
var revenue = 0.0
var income_rate = 0.0

# TRAFFIC CONSTANTS
var market_demand = 60.0 # The "Target" traffic the player has attracted/contracted
var organic_growth_rate = 0.01
var current_load = 0.0
var ddos_load = 0.0
var target_user_bandwidth_ratio = 0.1
var current_display_ratio = 0.1
var displayed_traffic: float = 0.0
var update_timer = 0.0

# TEMP CONSTANTS
var recovery_threshold = 60.0 # Temp must drop to 60°C to reboot
var cooling_cost_multiplier = 2.5 # Cooling works harder/costs more during a meltdown
var temperature = 35.0 # Starting room temp
var temp_home_x: float


func _ready():
	# Wait one frame for containers to finish setting up
	await get_tree().process_frame
	# Record where the label starts so we can always return to center
	temp_home_x = temp_label.position.x

func _process(delta: float):
	if not is_instance_valid(traffic_bar): return
	# ============================================
	# 1. TIME AND EVENT LOGIC
	# ============================================
	time += delta * time_scale
	current_day = (int(time / 1440) + 1)
	var total_minutes_today = fmod(time, 1440.0)
	var hours_24 = int(total_minutes_today / 60)
	var minutes = int(total_minutes_today) % 60

	# --- 1. HOURLY TICK ---
	# We check this every time the hour changes
	if hours_24 != last_roll_hour:
		last_roll_hour = hours_24
		check_for_events(current_day, hours_24)

	# --- 2. EXPIRY CHECK ---
	if active_event_id != "" and time >= event_expiry_time:
		end_active_event()
	
	# Update Labels
	var period = "AM" if hours_24 < 12 else "PM"
	var display_hours = hours_24 % 12
	if display_hours == 0: display_hours = 12
	day_label.text = "Day %d" % current_day
	clock_label.text = "%d:%02d %s" % [display_hours, minutes, period]

	# ============================================
	# 2. TRAFFIC LOGIC (Asymmetric 16/8 Cycle)
	# ============================================
	market_demand += (organic_growth_rate * delta) * time_scale
	demand_label.text = "Market Demand: %d" % market_demand
	
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

	current_load = lerp(min(traffic_bar.max_value - ddos_load, current_load), min(traffic_bar.max_value, target_load), delta * 2.0)
		

	var total_active_traffic = 0

	if servers_active:
		total_active_traffic = min(traffic_bar.max_value, current_load + ddos_load)
	else:
		total_active_traffic = 0

	displayed_traffic = lerp(displayed_traffic, float(total_active_traffic), delta * 5.0)
	traffic_bar.update_display(displayed_traffic, servers_active)

	# E. Update RPS Ratio (Jitter)
	update_timer += delta
	if update_timer > 0.5:
		target_user_bandwidth_ratio = randf_range(2.0, 5.0) # 2-5 RPS per Mbps
		update_timer = 0.0
	current_display_ratio = lerp(current_display_ratio, target_user_bandwidth_ratio, delta * 2.0)

	# ============================================
	# 3. MONEY LOGIC
	# ============================================
	if servers_active:
		# --- Revenue (Legit Traffic Only) ---
		var ddos_rps = ddos_load * current_display_ratio
		var legit_rps = current_load * current_display_ratio
		var raw_revenue = (current_load * 0.005) + (legit_rps * 0.001)
		
		# Apply Heat Penalty
		sla_multiplier = calculate_sla_multiplier(temperature)
		var adjusted_revenue = raw_revenue * sla_multiplier
		
		# --- Expenses (Total Traffic) ---
		var server_expenses = total_active_traffic * server_power_cost
		
		income_rate = (adjusted_revenue - server_expenses) * time_scale
		
		# Update RPS UI
		var jitter = randf_range(-0.5, 0.5) if current_load > 1000 else 0.0
		rps_label.text = "%d Requests/Sec" % ceil(legit_rps + jitter)
		if (ddos_load):
			ddos_rps_label.text = "+ %d (DDoS)" % ceil(ddos_rps + jitter)
		else:
			ddos_rps_label.text = ""
	else:
		# --- Shutdown State ---
		# You pay "Idle Power" costs but make $0 revenue
		income_rate = -(traffic_bar.max_value * 0.005) * 2.0
		rps_label.text = "SYSTEM OFFLINE"
		ddos_rps_label.text = ""

	# Update Global Cash
	revenue += income_rate * delta
	
	# Update Cash Labels
	cash_label.text = "$%.2f" % revenue
	var display_income_min = income_rate / time_scale
	income_label.text = ("+ " if display_income_min >= 0 else "- ") + "$%.2f/min" % abs(display_income_min)
	
	# Color Alert
	if income_rate >= 0:
		income_label.modulate = Color.GREEN
	else:
		income_label.modulate = Color.RED

	# ============================================
	# 4. TEMPERATURE & MELTDOWN
	# ============================================
	update_temperature(total_active_traffic, delta)
	
	if temperature >= 100 and servers_active:
		print("Server Meltdown!")
		# Logic inside update_temperature handles the actual servers_active = false

func update_temperature(serverLoad, delta):
	var usage_ratio = serverLoad / traffic_bar.max_value
	
	# 1. Standard Heating/Cooling Logic
	if servers_active:
		if usage_ratio > 0.8:
			temperature += 2.0 * delta 
		else:
			temperature -= 1.0 * delta 
	else:
		# If servers are SHUT DOWN, they produce no heat. 
		# The room cools down much faster
		temperature -= 4.0 * delta
	
	temperature = clamp(temperature, 35, 100)
	temp_label.text = "%d°C" % int(temperature)

	# --- COLOR LOGIC ---
	# We calculate a 'heat_percentage' from 0.0 to 1.0
	# 35 is 0%, 100 is 100%
	var heat_perc = (temperature - 35) / (100 - 35)
	
	var cold_color = Color.GREEN
	var hot_color = Color.RED
	
	# Apply the color to the text
	temp_label.modulate = cold_color.lerp(hot_color, heat_perc)

	if temperature > 90:
			# We set the position to the HOME plus a random offset
			temp_label.position.x = temp_home_x + randf_range(-2, 2)
	else:
		# If it's cool, make sure it stays at the home position
		temp_label.position.x = temp_home_x

	# 2. Shutdown Trigger
	if temperature >= 100 and servers_active:
		servers_active = false
		print("CRITICAL OVERHEAT: SERVERS SHUT DOWN")

	# 3. Recovery Logic
	if not servers_active and temperature <= recovery_threshold:
		servers_active = true
		print("SYSTEMS RECOVERED: SERVERS REBOOTING")

func calculate_sla_multiplier(current_temp: float) -> float:
	var threshold = 70.0
	if current_temp <= threshold:
		return 1.0
	
	# Penalty: Lose 2% revenue for every degree over 70C
	var degrees_over = current_temp - threshold
	var penalty = degrees_over * 0.02
	
	return clamp(1.0 - penalty, 0.0, 1.0)


func start_event(event_id: String):
	if active_event_id != "": 
		print("An event is already active!")
		return

	var data = EVENTS[event_id]
	active_event_id = event_id
	
	# Calculate Bonuses
	applied_demand_bonus = market_demand * (data.demand_mult - 1.0)
	applied_ddos_bonus = min(traffic_bar.max_value, data.ddos_add)
	
	# Apply Bonuses
	market_demand += applied_demand_bonus
	ddos_load += applied_ddos_bonus
	
	event_expiry_time = time + data.duration_minutes

	event_label.text = "Active Event: %s" % data.display_name
	
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
	event_label.text = "Active Event: None"


func check_for_events(day, hour):
	if active_event_id != "": return

	if hour == 0:
		for id in EVENTS:
			var ev = EVENTS[id]
			if ev.get("trigger_type") == "calendar" and ev.get("target_day") == day:
				start_event(id)
				return 

	var roll = randi() % 100
	for id in EVENTS:
		var ev = EVENTS[id]
		# Use .get() with a default of 0 to prevent crashing on missing weights
		if ev.get("trigger_type") == "random" and roll < ev.get("weight", 0):
			start_event(id)
			break


func _on_demand_button_pressed() -> void:
	market_demand *= 1.5

func _on_upgrade_button_pressed() -> void:
	traffic_bar.max_value = traffic_bar.max_value * 1.5

func _on_speed_button_pressed() -> void:
	if time_scale == 1.0:
		time_scale = 100.0
		speed_button.text = "Speed x100: ON"
	else:
		time_scale = 1.0 
		speed_button.text = "Speed x100: OFF"

func _on_ddos_button_pressed() -> void:
	start_event("botnet_attack")

func _on_black_friday_pressed() -> void:
	start_event("black_friday")

func _on_viral_video_pressed() -> void:
	start_event("viral_video")

# HELPERS FOR BUYING UNITS (zach)

func can_afford(amount: float) -> bool:
	return revenue >= amount

func spend_money(amount: float) -> bool:
	if revenue < amount:
		return false

	revenue -= amount
	cash_label.text = "$%.2f" % revenue
	return true

func get_money() -> float:
	return revenue
