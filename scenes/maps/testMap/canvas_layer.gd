extends CanvasLayer

@onready var traffic_bar = $Control/MarginContainer/HUDContainer/TrafficContainer/TrafficBar
@onready var rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/HBoxContainer/RPSLabel
@onready var ddos_rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/HBoxContainer/DDoSLabel
@onready var demand_label = $Control/MarginContainer/HUDContainer/TrafficContainer/MDLabel
@onready var event_label = $Control/MarginContainer/HUDContainer/TrafficContainer/EventLabel
@onready var cash_label = $Control/MarginContainer/HUDContainer/MoneyContainer/RevenueLabel
@onready var income_label = $Control/MarginContainer/HUDContainer/MoneyContainer/IncomeLabel
@onready var speed_button = $Control/MarginContainer/HUDContainer/TestingControls/SpeedButton
@onready var clock_pointer = $Control/TimeContainer/VBoxContainer/ClockContainer/Pointer
@onready var day_label = $Control/TimeContainer/VBoxContainer/DayLabel

# TRAFFIC CONSTANTS
var target_user_bandwidth_ratio = 0.1
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
	if traffic_bar != null:
		traffic_bar.max_value = max(GameManager.max_load, 1.0)

func _process(delta: float):
	if not is_instance_valid(traffic_bar): return

	event_label.text = "Event: %s" % GameManager.get_active_event_name()
	
	var day_progress = GameManager.total_minutes_today / 1440.0
	clock_pointer.rotation = (day_progress * TAU) - (PI / 2.0)
	day_label.text = "DAY %s" % GameManager.current_day
	
	# ============================================
	# 2. TRAFFIC UI
	# ============================================
	demand_label.text = "Market Demand: %d" % GameManager.market_demand
	

	displayed_traffic = lerp(displayed_traffic, float(GameManager.total_active_traffic), delta * 5.0)
	traffic_bar.update_display(displayed_traffic, GameManager.servers_active)

	# E. Update RPS Ratio (Jitter)
	update_timer += delta
	if update_timer > 0.5:
		target_user_bandwidth_ratio = randf_range(2.0, 5.0) # 2-5 RPS per Mbps
		update_timer = 0.0
	GameManager.current_display_ratio = lerp(GameManager.current_display_ratio, target_user_bandwidth_ratio, delta * 2.0)


	# ============================================
	# 3. MONEY UI SETTING
	# ============================================
	if GameManager.servers_active:
		rps_label.text = "%d Requests/Sec" % ceil(GameManager.legit_rps + GameManager.jitter)
		if (GameManager.ddos_load):
			ddos_rps_label.text = "+ %d (DDoS)" % ceil(GameManager.ddos_rps + GameManager.jitter)
		else:
			ddos_rps_label.text = ""
	else:
		rps_label.text = "SYSTEM OFFLINE"
		ddos_rps_label.text = ""

	# Update Cash Labels
	cash_label.text = "$%.2f" % GameManager.revenue
	var display_income_min = GameManager.income_rate / GameManager.time_scale
	income_label.text = ("+ " if display_income_min >= 0 else "- ") + "$%.2f/min" % abs(display_income_min)
	
	# Color Alert
	if GameManager.income_rate >= 0:
		income_label.modulate = Color.GREEN
	else:
		income_label.modulate = Color.RED


	# ============================================
	# 4. TEMPERATURE & MELTDOWN
	# ============================================
	# update_temperature(total_active_traffic, delta)
	
	# if temperature >= 100 and servers_active:
	# 	print("Server Meltdown!")

# func update_temperature(serverLoad, delta):
# 	var usage_ratio = serverLoad / traffic_bar.max_value
	
# 	# 1. Standard Heating/Cooling Logic
# 	if GameManager.servers_active:
# 		if usage_ratio > 0.8:
# 			temperature += 2.0 * delta 
# 		else:
# 			temperature -= 1.0 * delta 
# 	else:
# 		# If servers are SHUT DOWN, they produce no heat. 
# 		# The room cools down much faster
# 		temperature -= 4.0 * delta
	
# 	temperature = clamp(temperature, 35, 100)
# 	temp_label.text = "%d°C" % int(temperature)

# 	# --- COLOR LOGIC ---
# 	# We calculate a 'heat_percentage' from 0.0 to 1.0
# 	# 35 is 0%, 100 is 100%
# 	var heat_perc = (temperature - 35) / (100 - 35)
	
# 	var cold_color = Color.GREEN
# 	var hot_color = Color.RED
	
# 	# Apply the color to the text
# 	temp_label.modulate = cold_color.lerp(hot_color, heat_perc)

# 	if temperature > 90:
# 			# We set the position to the HOME plus a random offset
# 			temp_label.position.x = temp_home_x + randf_range(-2, 2)
# 	else:
# 		# If it's cool, make sure it stays at the home position
# 		temp_label.position.x = temp_home_x

# 	# 2. Shutdown Trigger
# 	if temperature >= 100 and servers_active:
# 		servers_active = false
# 		print("CRITICAL OVERHEAT: SERVERS SHUT DOWN")

# 	# 3. Recovery Logic
# 	if not servers_active and temperature <= recovery_threshold:
# 		servers_active = true
# 		print("SYSTEMS RECOVERED: SERVERS REBOOTING")

func calculate_sla_multiplier(current_temp: float) -> float:
	var threshold = 70.0
	if current_temp <= threshold:
		return 1.0
	
	# Penalty: Lose 2% revenue for every degree over 70C
	var degrees_over = current_temp - threshold
	var penalty = degrees_over * 0.02
	
	return clamp(1.0 - penalty, 0.0, 1.0)


func _on_demand_button_pressed() -> void:
	GameManager.increase_demand()

func _on_upgrade_button_pressed() -> void:
	GameManager.dev_server_upgrade()
	traffic_bar.max_value = GameManager.max_load

func _on_speed_button_pressed() -> void:
	GameManager.speed_time()
	speed_button.text = "Speed 100x: ON" if GameManager.time_scale == 1200.0 else "Speed 100x: OFF"

func _on_ddos_button_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("botnet_attack")

func _on_black_friday_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("black_friday")

func _on_viral_video_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("viral_video")

# HELPERS FOR BUYING UNITS (zach)

# func can_afford(amount: float) -> bool:
# 	return revenue >= amount

# func spend_money(amount: float) -> bool:
# 	if revenue < amount:
# 		return false

# 	revenue -= amount
# 	cash_label.text = "$%.2f" % revenue
# 	return true

# func get_money() -> float:
# 	return revenue
