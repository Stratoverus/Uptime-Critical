extends CanvasLayer


@onready var clock_label = $Control/MarginContainer/HUDContainer/StatsBar/Time
@onready var day_label = $Control/MarginContainer/HUDContainer/StatsBar/Day
@onready var traffic_bar = $Control/MarginContainer/HUDContainer/TrafficContainer/TrafficBar
@onready var rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/RPSLabel
@onready var cash_label = $Control/MarginContainer/HUDContainer/MoneyContainer/RevenueLabel
@onready var revenue_label = $Control/MarginContainer/HUDContainer/MoneyContainer/IncomeLabel
@onready var temp_label = $Control/MarginContainer/HUDContainer/TempContainer/Temp

# Game State Variables
var time = 700.0
var time_scale = 1.0
var current_day = int(time / 1440) + 1
var revenue = 0.0
var income_rate = 0.0
var base_growth_rate = 0.01 
var current_load = 0.0
var ddos_load = 0.0
var temperature = 35.0 # Starting room temp
var target_ratio = 0.1
var current_display_ratio = 0.1
var update_timer = 0.0
var temp_home_x: float


func _ready():
	# Wait one frame for containers to finish setting up
	await get_tree().process_frame
	# Record where the label starts so we can always return to center
	temp_home_x = temp_label.position.x

func _process(delta: float):
	# ============================================
	# TIME LOGIC
	# ============================================
	time += delta * time_scale
	var total_minutes_today = fmod(time, 1440.0)

	var hours_24 = int(total_minutes_today / 60)
	var minutes = int(total_minutes_today) % 60

	var period = "AM" if hours_24 < 12 else "PM"

	var display_hours = hours_24 % 12
	if display_hours == 0:
		display_hours = 12

	day_label.text = "Day %d" % current_day
	clock_label.text = "%d:%02d %s" % [display_hours, minutes, period]


	# ============================================
	# TRAFFIC LOGIC
	# ============================================
	# 1. Calculate Traffic Growth
	current_load += (traffic_bar.max_value * base_growth_rate) * delta
	
	# 2. Update the visual bar
	var total_active_traffic = current_load + ddos_load
	traffic_bar.update_display(total_active_traffic)

	# Update the Target Ratio every 0.5 seconds (prevents the 'jitter')
	update_timer += delta
	if update_timer > 0.5:
		# Pick a new ratio between 8-12 Mbps/person
		target_ratio = randf_range(0.08, 0.12)
		update_timer = 0.0
	
	# 2. Smoothly slide the current ratio toward the target
	# 'delta * 2.0' controls the "speed" of the hover (increase for faster moves)
	current_display_ratio = lerp(current_display_ratio, target_ratio, delta * 2.0)
	var smoothed_rps = total_active_traffic * current_display_ratio
	
	# Add a tiny bit of "visual noise" (1-2 points) so it doesn't look static
	var jitter = randf_range(-0.5, 0.5)

	if smoothed_rps < 1000:
		jitter = 0

	rps_label.text = "%d Requests/Sec" % ceil(smoothed_rps + jitter)


	# ============================================
	# MONEY LOGIC
	# ============================================
	# Handle Revenue (Earn $0.01 per Mbps every second)
	revenue += (total_active_traffic * 0.01) * delta
	cash_label.text = "$%.2f" % revenue

	income_rate = (total_active_traffic * 0.01)
	revenue_label.text = "+ $%.2f/min" % income_rate

	# ============================================
	# TEMPERATURE LOGIC
	# ============================================	
	# Handle Temperature (Temp rises if traffic > 70% of capacity)
	update_temperature(total_active_traffic, delta)
	
	# ============================================
	# GAME OVER LOGIC
	# ============================================	
	# Check for Crash
	if temperature >= 100:
		get_tree().paused = true
		print("Server Meltdown! Final Revenue: ", revenue)

func update_temperature(serverLoad, delta):
	var usage_ratio = serverLoad / traffic_bar.max_value
	
	# Logic for heating up/cooling down
	if usage_ratio > 0.7:
		temperature += 2.0 * delta 
	else:
		temperature -= 1.0 * delta 
	
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


func _on_ddos_button_pressed() -> void:
	# 1. Calculate 20% of capacity
	var attack_amount = traffic_bar.value * 0.25

	# 2. Add it to our "temporary" tracking variable
	ddos_load += attack_amount

	# 3. Start a 10-second countdown to remove it
	# We use a SceneTreeTimer so we don't have to create a node manually
	get_tree().create_timer(10.0).timeout.connect(_end_ddos_attack.bind(attack_amount))

	print("DDoS Started! +", attack_amount, " Mbps")

func _end_ddos_attack(amount_to_remove: float):
	# 4. Remove exactly what we added
	ddos_load -= amount_to_remove
	print("DDoS Attack ended.") 


func _on_upgrade_button_pressed() -> void:
	traffic_bar.max_value = traffic_bar.max_value * 1.1

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