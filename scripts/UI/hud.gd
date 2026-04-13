extends CanvasLayer

@onready var traffic_bar = $Control/MarginContainer/HUDContainer/TrafficContainer/TrafficBar
@onready var service_bar = $Control/MarginContainer/HUDContainer/TrafficContainer/ServiceBar
@onready var ddos_rps_label = $Control/MarginContainer/HUDContainer/TrafficContainer/DemandBox/DDoSLabel
@onready var demand_label = $Control/MarginContainer/HUDContainer/TrafficContainer/DemandBox/MDLabel
@onready var event_label = $Control/MarginContainer/HUDContainer/TrafficContainer/EventLabel
@onready var prep_status_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/PrepStatusLabel")
@onready var bottleneck_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/BottleneckLabel")
@onready var handled_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/HandledLabel")
@onready var dropped_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/DroppedLabel")
@onready var reputation_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/ReputationLabel")
@onready var irreparable_label = get_node_or_null("Control/MarginContainer/HUDContainer/TrafficContainer/IrreparableLabel")
@onready var cash_label = $Control/MarginContainer/HUDContainer/MoneyContainer/RevenueLabel
@onready var income_label = $Control/MarginContainer/HUDContainer/MoneyContainer/IncomeLabel
@onready var deficit_label = get_node_or_null("Control/MarginContainer/HUDContainer/MoneyContainer/DeficitLabel")
@onready var prep_label = get_node_or_null("Control/MarginContainer/HUDContainer/MoneyContainer/PrepLabel")
@onready var prep_banner = get_node_or_null("Control/PrepBanner")
@onready var prep_title = get_node_or_null("Control/PrepBanner/VBoxContainer/PrepTitle")
@onready var prep_subtitle = get_node_or_null("Control/PrepBanner/VBoxContainer/PrepSubtitle")
@onready var prep_countdown = get_node_or_null("Control/PrepBanner/VBoxContainer/PrepCountdown")
@onready var speed_button = $Control/DevControlsDock/VBoxContainer/TestingControls/SpeedButton
@onready var pause_button = get_node_or_null("Control/DevControlsDock/VBoxContainer/TestingControls/PauseButton")
@onready var start_button = get_node_or_null("Control/DevControlsDock/VBoxContainer/TestingControls/StartSessionButton")
@onready var prep_dock_button = get_node_or_null("Control/PrepDock/VBoxContainer/PrepDockButton")
@onready var network_overlay_button = get_node_or_null("Control/MarginContainer/HUDContainer/TestingControls/OverlayButtons/NetworkOverlayButton")
@onready var electrical_overlay_button = get_node_or_null("Control/MarginContainer/HUDContainer/TestingControls/OverlayButtons/ElectricalOverlayButton")
@onready var heat_overlay_button = get_node_or_null("Control/MarginContainer/HUDContainer/TestingControls/OverlayButtons/HeatOverlayButton")
@onready var start_confirmation_dialog = get_node_or_null("Control/StartConfirmationDialog")
@onready var event_confirmation_dialog = get_node_or_null("Control/EventConfirmationDialog")
@onready var clock_pointer = $Control/TimeContainer/VBoxContainer/ClockContainer/Pointer
@onready var day_label = $Control/TimeContainer/VBoxContainer/DayLabel

var target_user_bandwidth_ratio = 0.1
var displayed_traffic: float = 0.0
var update_timer = 0.0

var recovery_threshold = 60.0
var cooling_cost_multiplier = 2.5
var temperature = 35.0
var temp_home_x: float


func _ready():
	await get_tree().process_frame
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enable_hud_mouse_passthrough()
	if traffic_bar != null:
		traffic_bar.max_value = max(GameManager.datacenter_capacity_rps, 1.0)
	if service_bar != null:
		service_bar.visible = false
	if start_button != null:
		start_button.text = "Begin 30s Prep"
		start_button.visible = false
		if not start_button.pressed.is_connected(_on_start_session_button_pressed):
			start_button.pressed.connect(_on_start_session_button_pressed)
		if not start_button.button_down.is_connected(_on_start_session_button_button_down):
			start_button.button_down.connect(_on_start_session_button_button_down)
	if pause_button != null:
		pause_button.text = "Pause Menu"
		if not pause_button.pressed.is_connected(_on_pause_button_pressed):
			pause_button.pressed.connect(_on_pause_button_pressed)
	if prep_dock_button != null:
		prep_dock_button.text = "Begin 30s Prep"
		prep_dock_button.visible = false
		if not prep_dock_button.pressed.is_connected(_on_start_session_button_pressed):
			prep_dock_button.pressed.connect(_on_start_session_button_pressed)
		if not prep_dock_button.button_down.is_connected(_on_start_session_button_button_down):
			prep_dock_button.button_down.connect(_on_start_session_button_button_down)
	if GameManager.has_signal("prep_state_changed") and not GameManager.prep_state_changed.is_connected(_on_prep_state_changed):
		GameManager.prep_state_changed.connect(_on_prep_state_changed)
	_update_overlay_buttons()
	_update_prep_state(GameManager.get_prep_countdown_remaining_seconds(), GameManager.is_prep_countdown_active())
	if start_confirmation_dialog != null:
		_center_start_confirmation_text()
		start_confirmation_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		call_deferred("_show_start_confirmation_dialog")
	if event_confirmation_dialog != null:
		_center_event_confirmation_text()
	if GameManager.has_signal("show_event_popup") and not GameManager.show_event_popup.is_connected(_on_show_event_popup):
		GameManager.show_event_popup.connect(_on_show_event_popup)
		


func _center_start_confirmation_text() -> void:
	if start_confirmation_dialog == null:
		return
	var dialog := start_confirmation_dialog as AcceptDialog
	if dialog == null:
		return
	var dialog_label: Label = dialog.get_label()
	if dialog_label != null:
		dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _center_event_confirmation_text() -> void:
	if event_confirmation_dialog == null:
		return
	var dialog := event_confirmation_dialog as AcceptDialog
	if dialog == null:
		return
	var dialog_label: Label = dialog.get_label()
	if dialog_label != null:
		dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _process(delta: float):
	if not is_instance_valid(traffic_bar):
		return

	event_label.text = "Event: %s" % GameManager.get_active_event_name()

	var day_progress = GameManager.total_minutes_today / 1440.0
	clock_pointer.rotation = (day_progress * TAU) - (PI / 2.0)
	day_label.text = "DAY %s" % GameManager.current_day

	demand_label.text = "Incoming: %d Req/s" % int(round(GameManager.incoming_total_rps))

	var current_incoming_rps: float = float(GameManager.incoming_total_rps)
	displayed_traffic = lerp(displayed_traffic, current_incoming_rps, delta * 5.0)
	var bar_capacity_rps: float = max(GameManager.datacenter_capacity_rps, 1.0)
	traffic_bar.update_display(current_incoming_rps, bar_capacity_rps, GameManager.servers_active, "Req/s", GameManager.dropped_ratio)

	update_timer += delta
	if update_timer > 0.5:
		update_timer = 0.0

	if GameManager.servers_active:
		if (GameManager.ddos_load):
			ddos_rps_label.text = "+ %d Req/s DDoS" % ceil(GameManager.incoming_invalid_rps)
		else:
			ddos_rps_label.text = ""
	else:
		ddos_rps_label.text = ""

	if handled_label != null:
		handled_label.text = "Processed: %d Req/s | Total: %s req" % [int(round(ceil(GameManager.handled_valid_rps + GameManager.jitter))), _format_request_count(GameManager.total_processed_requests)]
	if bottleneck_label != null:
		if GameManager.dropped_rps > 0.01:
			bottleneck_label.text = "Bottleneck: %s (%s)" % [GameManager.capacity_bottleneck, GameManager.drop_cause_summary]
		else:
			bottleneck_label.text = "Bottleneck: %s (%d clusters)" % [GameManager.capacity_bottleneck, GameManager.active_cluster_count]
	if dropped_label != null:
		if GameManager.dropped_rps > 0.01:
			dropped_label.text = "Dropped: %d Req/s (%.1f%%) [%s | Wire: %d | Pre-wire: %d] | Total: %s req" % [
				int(round(GameManager.dropped_rps)),
				GameManager.dropped_ratio * 100.0,
				GameManager.drop_cause_summary,
				int(round(GameManager.dropped_wire_bottleneck_rps)),
				int(round(GameManager.dropped_pre_wire_rps)),
				_format_request_count(GameManager.total_dropped_requests)
			]
		else:
			dropped_label.text = "Dropped: %d Req/s (%.1f%%) | Total: %s req" % [int(round(GameManager.dropped_rps)), GameManager.dropped_ratio * 100.0, _format_request_count(GameManager.total_dropped_requests)]
		dropped_label.modulate = Color(0.9, 0.15, 0.15, 1.0) if GameManager.dropped_ratio > 0.1 else Color(255.0, 255.0, 255.0, 1.0)
	if reputation_label != null:
		reputation_label.text = "Reputation: %.1f%%" % GameManager.datacenter_reputation
		reputation_label.modulate = Color(0.9, 0.15, 0.15, 1.0) if GameManager.datacenter_reputation <= 25.0 else Color(255.0, 255.0, 255.0, 1.0)
	if irreparable_label != null:
		if GameManager.is_game_over:
			irreparable_label.text = "GAME OVER: Reputation irreparable"
			irreparable_label.visible = true
		elif GameManager.datacenter_reputation <= GameManager.irreparable_threshold:
			var remain = max(GameManager.irreparable_duration_seconds - GameManager.irreparable_timer_seconds, 0.0)
			irreparable_label.text = "Irreparable in: %.0fs" % remain
			irreparable_label.visible = true
		else:
			irreparable_label.visible = false

	cash_label.text = "$%.2f" % GameManager.revenue
	var display_income_min = GameManager.income_rate / GameManager.time_scale
	income_label.text = ("+ " if display_income_min >= 0 else "- ") + "$%.2f/min" % abs(display_income_min)

	if GameManager.income_rate >= 0:
		income_label.modulate = Color.GREEN
	else:
		income_label.modulate = Color.RED

	if deficit_label != null:
		if GameManager.income_rate < 0:
			deficit_label.text = "Deficit"
			deficit_label.modulate = Color(0.9, 0.15, 0.15, 1.0)
		else:
			deficit_label.text = ""
	if prep_label != null:
		_update_prep_state(GameManager.get_prep_countdown_remaining_seconds(), GameManager.is_prep_countdown_active())

	_update_overlay_buttons()

func _enable_hud_mouse_passthrough() -> void:
	var passthrough_root: Control = get_node_or_null("Control")
	if passthrough_root == null:
		return
	passthrough_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_control_tree_mouse_passthrough(passthrough_root)

func _set_control_tree_mouse_passthrough(node: Control) -> void:
	for child in node.get_children():
		if not (child is Control):
			continue
		var child_control: Control = child as Control
		if child_control is BaseButton or child_control is HSlider or child_control is VSlider or child_control is LineEdit or child_control is TextEdit:
			child_control.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			child_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_control_tree_mouse_passthrough(child_control)

func calculate_sla_multiplier(current_temp: float) -> float:
	var threshold = 70.0
	if current_temp <= threshold:
		return 1.0

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

func _on_pause_button_pressed() -> void:
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("_open_pause_menu"):
		level_controller.call("_open_pause_menu")

func _on_electrical_overlay_button_pressed() -> void:
	var overlay = get_tree().get_first_node_in_group("electrical_overlay")
	if overlay == null:
		return

	if overlay.has_method("toggle_overlay"):
		overlay.toggle_overlay()
	elif overlay.has_method("set_overlay_visible"):
		overlay.set_overlay_visible(not overlay.visible)

	_update_overlay_buttons()

func _on_network_overlay_button_pressed() -> void:
	var overlay = get_tree().current_scene.get_node_or_null("NetworkOverlay/Control")
	if overlay == null:
		return

	if overlay.has_method("toggle_overlay"):
		overlay.toggle_overlay()
	elif overlay.has_method("set_overlay_visible"):
		overlay.set_overlay_visible(not overlay.visible)

	_update_overlay_buttons()

func _on_heat_overlay_button_pressed() -> void:
	var thermal_system = get_tree().get_first_node_in_group("thermal_system")
	if thermal_system == null:
		return

	var currently_enabled: bool = bool(thermal_system.get("heat_view_enabled"))
	if thermal_system.has_method("set_heat_view_enabled"):
		thermal_system.set_heat_view_enabled(not currently_enabled)

	_update_overlay_buttons()

func _on_ddos_button_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("botnet_attack")

func _on_start_session_button_pressed() -> void:
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("set_start_dialog_pause"):
		level_controller.call("set_start_dialog_pause", true)
	if start_confirmation_dialog != null:
		start_confirmation_dialog.popup_centered_ratio(0.35)

func _on_start_session_button_button_down() -> void:
	return

func _on_start_session_confirmed() -> void:
	if start_confirmation_dialog != null:
		start_confirmation_dialog.hide()
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("set_start_dialog_pause"):
		level_controller.call("set_start_dialog_pause", false)
	if level_controller != null and level_controller.has_method("begin_prep_session"):
		level_controller.call("begin_prep_session", GameManager.default_prep_countdown_seconds)
	else:
		GameManager.begin_prep_countdown(GameManager.default_prep_countdown_seconds)
	if start_button != null:
		start_button.disabled = true
		start_button.text = "Prep In Progress"
	if prep_banner != null:
		prep_banner.visible = false
	if prep_status_label != null:
		prep_status_label.visible = true
		prep_status_label.text = "Prepare yourself - setup has started"

func _show_start_confirmation_dialog() -> void:
	if start_confirmation_dialog == null:
		return
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("set_start_dialog_pause"):
		level_controller.call("set_start_dialog_pause", true)
	start_confirmation_dialog.popup_centered_ratio(0.35)

func _update_prep_state(remaining_seconds: float, is_active: bool) -> void:
	var remaining: float = max(remaining_seconds, 0.0)
	if prep_label != null:
		if is_active:
			prep_label.visible = true
			prep_label.text = "Prepare yourself: %.0fs remaining" % ceil(remaining)
		else:
			prep_label.visible = false
	if prep_status_label != null:
		if is_active:
			prep_status_label.visible = true
			prep_status_label.text = "Setup in progress - traffic begins in %.0fs" % ceil(remaining)
		else:
			prep_status_label.visible = false
	if prep_banner != null:
		prep_banner.z_index = 100
		prep_banner.visible = false
	if prep_title != null:
		prep_title.text = "Prepare yourself"
	if prep_subtitle != null:
		if is_active:
			prep_subtitle.text = "The first traffic wave starts soon."
		else:
			prep_subtitle.text = ""
	if prep_countdown != null:
		prep_countdown.z_index = 101
		if is_active:
			prep_countdown.text = "%.0fs" % ceil(remaining)
		else:
			prep_countdown.text = ""
	if start_button != null:
		start_button.disabled = is_active or GameManager.is_gameplay_started()
		if GameManager.is_gameplay_started():
			start_button.text = "Session Running"
		elif is_active:
			start_button.text = "Prep In Progress"
		else:
			start_button.text = "Begin 30s Prep"

func _on_prep_state_changed(remaining_seconds, is_active) -> void:
	_update_prep_state(float(remaining_seconds), bool(is_active))

func _on_black_friday_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("black_friday")

func _on_viral_video_pressed() -> void:
	GameManager.end_active_event()
	GameManager.start_event("viral_video")

func _update_overlay_buttons() -> void:
	_update_network_overlay_button()
	_update_electrical_overlay_button()
	_update_heat_overlay_button()

func _update_network_overlay_button() -> void:
	if network_overlay_button == null:
		return

	var overlay = get_tree().current_scene.get_node_or_null("NetworkOverlay/Control")
	var overlay_visible: bool = overlay != null and overlay.visible
	if overlay_visible:
		network_overlay_button.text = "Hide Network Overlay (N)"
	else:
		network_overlay_button.text = "Toggle Network Overlay (N)"

func _update_electrical_overlay_button() -> void:
	if electrical_overlay_button == null:
		return

	var overlay = get_tree().get_first_node_in_group("electrical_overlay")
	var overlay_visible: bool = overlay != null and overlay.visible
	if overlay_visible:
		electrical_overlay_button.text = "Hide Electrical Overlay (J)"
	else:
		electrical_overlay_button.text = "Toggle Electrical Overlay (J)"

func _update_heat_overlay_button() -> void:
	if heat_overlay_button == null:
		return

	var thermal_system = get_tree().get_first_node_in_group("thermal_system")
	var heat_enabled: bool = thermal_system != null and bool(thermal_system.get("heat_view_enabled"))
	if heat_enabled:
		heat_overlay_button.text = "Hide Heat Overlay (H)"
	else:
		heat_overlay_button.text = "Toggle Heat Overlay (H)"

func _format_request_count(value: float) -> String:
	var safe_value: float = max(value, 0.0)
	if safe_value >= 1000000.0:
		return "%.2fM" % (safe_value / 1000000.0)
	if safe_value >= 1000.0:
		return "%.2fK" % (safe_value / 1000.0)
	return "%d" % int(round(safe_value))


func _on_show_event_popup(event_data: Dictionary) -> void:
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("set_start_dialog_pause"):
		level_controller.call("set_start_dialog_pause", true)
			
	if event_confirmation_dialog != null:
		event_confirmation_dialog.title = event_data.get("display_name", "Alert")
		if event_data.get("event_is_good") == true:
			# Use add_theme_color_override to change theme colors via code
			event_confirmation_dialog.add_theme_color_override("title_color", Color.GREEN)
		else:
			event_confirmation_dialog.add_theme_color_override("title_color", Color.RED)
		
		# 1. Grab the lore message
		var base_msg = event_data.get("message", "An event has occurred.")
		
		# 2. Dynamically build the stat block
		var stats_text = "\n\n--- EVENT DETAILS ---\n"
		
		var duration = float(event_data.get("duration_minutes", 0))
		if duration > 0:
			stats_text += "• Duration: %d In-Game Hours\n" % int(duration / 60)
			
		var demand = float(event_data.get("demand_mult", 1.0))
		if demand != 1.0:
			var percent = int(round((demand - 1.0) * 100))
			var sign_str = "+" if percent > 0 else ""
			stats_text += "• Market Demand: %s%d%%\n" % [sign_str, percent]
			
		var ddos = float(event_data.get("ddos_add", 0.0))
		if ddos > 0:
			stats_text += "• Malicious Traffic: +%d RPS\n" % int(ddos)

		# Combine them
		event_confirmation_dialog.dialog_text = base_msg + stats_text
		
		# 3. Force the internal label to format correctly
		var label: Label = event_confirmation_dialog.get_label()
		if label != null:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
		# Pop it open
		event_confirmation_dialog.popup_centered_ratio(0.35)

func _on_event_confirmation_dialog_confirmed() -> void:
	var level_controller := get_parent()
	if level_controller != null and level_controller.has_method("set_start_dialog_pause"):
		level_controller.call("set_start_dialog_pause", false)
