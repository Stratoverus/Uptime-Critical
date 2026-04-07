extends CanvasLayer

signal unit_selected(unit_data)


@onready var title_label = $Panel/MainVBox/TitleLabel
@onready var unit_grid = $Panel/MainVBox/UnitGrid
@onready var dev_money_button = $Panel/MainVBox/DevMoneyButton
@onready var menu_panel = $Panel

var selected_button: Button = null
var day_label_node: Control = null

@export var panel_day_label_gap: float = 8.0

var cable_items = [
	{ "name": "Cat5", "color": Color(0.53, 0.53, 0.53, 1.0), "cost": 0.25 },
	{ "name": "Cat6", "color": Color(0.36, 0.56, 0.72, 1.0), "cost": 0.40 },
	{ "name": "Fiber", "color": Color(0.16, 0.74, 0.66, 1.0), "cost": 0.90 },
	{ "name": "Internet Pipe (Uplink)", "color": Color(0.94, 0.76, 0.18, 1.0), "cost": 2.50 }
]

var electrical_cable_items = [
	{ "name": "Power Cable", "color": Color(0.12, 0.86, 1.0, 0.95), "cost": 0.005 }
]

var current_menu_mode: String = "units"

var unit_data = [
	{
		"id": "server_rack_l1",
		"name": "Server Rack L1",
		"cost": 100,
		"category": "server",
		"level": 1,
		"scene_path": "res://scenes/units/server_rack_l1.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/servers/server_rack_1_front.png",
			"back": "res://assets/object_sprites/servers/server_rack_1_back.png",
			"left": "res://assets/object_sprites/servers/server_rack_1_left.png",
			"right": "res://assets/object_sprites/servers/server_rack_1_right.png"
		}
	},
	{
		"id": "server_rack_l2",
		"name": "Server Rack L2",
		"cost": 200,
		"category": "server",
		"level": 2,
		"scene_path": "res://scenes/units/server_rack_l2.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/servers/server_rack_2_front.png",
			"back": "res://assets/object_sprites/servers/server_rack_2_back.png",
			"left": "res://assets/object_sprites/servers/server_rack_2_left.png",
			"right": "res://assets/object_sprites/servers/server_rack_2_right.png"
		}
	},
	{
		"id": "server_rack_l3",
		"name": "Server Rack L3",
		"cost": 300,
		"category": "server",
		"level": 3,
		"scene_path": "res://scenes/units/server_rack_l3.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/servers/server_rack_3_front.png",
			"back": "res://assets/object_sprites/servers/server_rack_3_back.png",
			"left": "res://assets/object_sprites/servers/server_rack_3_left.png",
			"right": "res://assets/object_sprites/servers/server_rack_3_right.png"
		}
	},
	{
		"id": "cooling_unit_l1",
		"name": "Cooling Unit L1",
		"cost": 120,
		"category": "cooling",
		"level": 1,
		"scene_path": "res://scenes/units/cooling_unit_l1.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/coolingRacks/cooling_rack_1_front.png",
			"back": "res://assets/object_sprites/coolingRacks/cooling_rack_1_back.png",
			"left": "res://assets/object_sprites/coolingRacks/cooling_rack_1_left.png",
			"right": "res://assets/object_sprites/coolingRacks/cooling_rack_1_right.png"
		}
	},
	{
		"id": "cooling_unit_l2",
		"name": "Cooling Unit L2",
		"cost": 240,
		"category": "cooling",
		"level": 2,
		"scene_path": "res://scenes/units/cooling_unit_l2.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/coolingRacks/cooling_rack_2_front.png",
			"back": "res://assets/object_sprites/coolingRacks/cooling_rack_2_back.png",
			"left": "res://assets/object_sprites/coolingRacks/cooling_rack_2_left.png",
			"right": "res://assets/object_sprites/coolingRacks/cooling_rack_2_right.png"
		}
	},
	{
		"id": "cooling_unit_l3",
		"name": "Cooling Unit L3",
		"cost": 360,
		"category": "cooling",
		"level": 3,
		"scene_path": "res://scenes/units/cooling_unit_l3.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/coolingRacks/cooling_rack_3_front.png",
			"back": "res://assets/object_sprites/coolingRacks/cooling_rack_3_back.png",
			"left": "res://assets/object_sprites/coolingRacks/cooling_rack_3_left.png",
			"right": "res://assets/object_sprites/coolingRacks/cooling_rack_3_right.png"
		}
	},
	{
		"id": "router_l1",
		"name": "Router L1",
		"cost": 200,
		"category": "router",
		"level": 1,
		"scene_path": "res://scenes/units/router_l1.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/routers/router_1_front.png",
			"back": "res://assets/object_sprites/routers/router_1_back.png",
			"left": "res://assets/object_sprites/routers/router_1_left.png",
			"right": "res://assets/object_sprites/routers/router_1_right.png"
		}
	},
	{
		"id": "router_l2",
		"name": "Router L2",
		"cost": 400,
		"category": "router",
		"level": 2,
		"scene_path": "res://scenes/units/router_l2.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/routers/router_2_front.png",
			"back": "res://assets/object_sprites/routers/router_2_back.png",
			"left": "res://assets/object_sprites/routers/router_2_left.png",
			"right": "res://assets/object_sprites/routers/router_2_right.png"
		}
	},
	{
		"id": "router_l3",
		"name": "Router L3",
		"cost": 600,
		"category": "router",
		"level": 3,
		"scene_path": "res://scenes/units/router_l3.tscn",
		"sprites": {
			"front": "res://assets/object_sprites/routers/router_3_front.png",
			"back": "res://assets/object_sprites/routers/router_3_back.png",
			"left": "res://assets/object_sprites/routers/router_3_left.png",
			"right": "res://assets/object_sprites/routers/router_3_right.png"
		}
	}
]

func style_menu_button(button: Button, color: Color) -> void:
	if button == null:
		return

	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = Color.WHITE
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5

	var hover = StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.08)
	hover.border_color = Color.WHITE
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(5)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	hover.content_margin_top = 5
	hover.content_margin_bottom = 5

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.08)
	pressed.border_color = Color.WHITE
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(5)
	pressed.content_margin_left = 10
	pressed.content_margin_right = 10
	pressed.content_margin_top = 5
	pressed.content_margin_bottom = 5

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func style_tab_button(button: Button, active: bool) -> void:
	var color = Color("3b82f6") if active else Color("6b7280")
	style_menu_button(button, color)

func style_dev_button(button: Button) -> void:
	style_menu_button(button, Color("16a34a"))



func _ready() -> void:
	if title_label == null or unit_grid == null or dev_money_button == null:
		push_error("BuyMenu node path mismatch")
		return

	title_label.text = "Buy Menu"
	style_dev_button(dev_money_button)
	build_unit_list()
	dev_money_button.pressed.connect(_on_dev_money_button_pressed)
	_cache_day_label_node()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_pin_panel_below_day_label")

func build_unit_list() -> void:
	for child in unit_grid.get_children():
		child.queue_free()

	unit_grid.add_theme_constant_override("h_separation", 6)
	unit_grid.add_theme_constant_override("v_separation", 6)

	for unit in unit_data:
		var button = Button.new()
		button.text = "%s  |  $%s" % [unit["name"], unit["cost"]]
		button.custom_minimum_size = Vector2(220, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

		if unit["name"].contains("Server Rack"):
			style_menu_button(button, Color(0.101960786, 0.6, 0.6, 1))
		elif unit["name"].contains("Cooling Unit"):
			style_menu_button(button, Color(0.23609412, 0.6139884, 0.35257745, 1))
		else:
			style_menu_button(button, Color(0.6455514, 1.8289685e-06, 3.3691526e-07, 1))

		button.set_meta("unit_data", unit)
		button.pressed.connect(_on_unit_pressed.bind(button))

		unit_grid.add_child(button)

func populate_menu(items: Array, is_cable: bool) -> void:
	for child in unit_grid.get_children():
		child.queue_free()

	for item in items:
		var button = Button.new()

		if is_cable:
			button.text = "%s  |  $%s/ft" % [item["name"], item["cost"]]
			style_menu_button(button, item["color"])
			button.set_meta("cable_data", item)
			button.pressed.connect(_on_cable_pressed.bind(button))
		else:
			button.text = "%s  |  $%s" % [item["name"], item["cost"]]

			if item["name"].contains("Server Rack"):
				style_menu_button(button, Color(0.101960786, 0.6, 0.6, 1))
			elif item["name"].contains("Cooling Unit"):
				style_menu_button(button, Color(0.23609412, 0.6139884, 0.35257745, 1))
			else:
				style_menu_button(button, Color(0.6455514, 1.8289685e-06, 3.3691526e-07, 1))

			button.set_meta("unit_data", item)
			button.pressed.connect(_on_unit_pressed.bind(button))

		button.custom_minimum_size = Vector2(220, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

		unit_grid.add_child(button)

func _on_unit_pressed(button: Button) -> void:
	var unit = button.get_meta("unit_data")

	if selected_button != null:
		selected_button.modulate = Color(1, 1, 1, 1)

	selected_button = button
	selected_button.modulate = Color(0.7, 1.0, 0.7, 1.0)

	unit_selected.emit(unit)

func _on_dev_money_button_pressed() -> void:
	GameManager.revenue += 100

func set_menu_mode(is_cable: bool):
	set_menu_mode_by_name("network" if is_cable else "units")

func set_menu_mode_by_name(mode: String) -> void:
	if mode == current_menu_mode:
		return

	current_menu_mode = mode
	selected_button = null

	if mode == "network":
		title_label.text = "Network Wiring"
		populate_menu(cable_items, true)
	elif mode == "electrical":
		title_label.text = "Electrical Wiring"
		populate_menu(electrical_cable_items, true)
		call_deferred("_select_default_cable_item")
	else:
		title_label.text = "Buy Menu"
		populate_menu(unit_data, false)

	call_deferred("_pin_panel_below_day_label")

func _cache_day_label_node() -> void:
	if day_label_node != null and is_instance_valid(day_label_node):
		return
	if get_tree() == null or get_tree().current_scene == null:
		return
	day_label_node = get_tree().current_scene.get_node_or_null("HUD/Control/TimeContainer/VBoxContainer/DayLabel") as Control

func _pin_panel_below_day_label() -> void:
	if menu_panel == null:
		return

	_cache_day_label_node()
	if day_label_node == null or not is_instance_valid(day_label_node):
		return

	var day_rect: Rect2 = day_label_node.get_global_rect()
	menu_panel.global_position = Vector2(menu_panel.global_position.x, day_rect.position.y + day_rect.size.y + panel_day_label_gap)

func _on_viewport_size_changed() -> void:
	call_deferred("_pin_panel_below_day_label")

func _select_default_cable_item() -> void:
	if current_menu_mode != "electrical":
		return

	for child in unit_grid.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		if not button.has_meta("cable_data"):
			continue
		var cable_data: Variant = button.get_meta("cable_data")
		if cable_data is Dictionary and str(cable_data.get("name", "")) == "Power Cable":
			apply_cable_selection_visual(button)
			return

	if unit_grid.get_child_count() > 0 and unit_grid.get_child(0) is Button:
		apply_cable_selection_visual(unit_grid.get_child(0) as Button)

func _on_cable_pressed(button: Button) -> void:
	var cable = button.get_meta("cable_data")
	apply_cable_selection_visual(button)

	# we'll use this later for placement
	emit_signal("unit_selected", cable)

func apply_cable_selection_visual(selected: Button) -> void:
	selected_button = selected
	for child in unit_grid.get_children():
		if child is Button:
			(child as Button).modulate = Color(1, 1, 1, 0.55)

	if selected_button != null:
		selected_button.modulate = Color(1.0, 1.0, 1.0, 1.0)

func clear_selected_button() -> void:
	selected_button = null
	for child in unit_grid.get_children():
		if child is Button:
			(child as Button).modulate = Color(1.0, 1.0, 1.0, 1.0)

func set_selected_cable_by_name(cable_name: String) -> void:
	if cable_name == "":
		return

	for child in unit_grid.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		if not button.has_meta("cable_data"):
			continue
		var cable_data: Variant = button.get_meta("cable_data")
		if cable_data is Dictionary and str(cable_data.get("name", "")) == cable_name:
			apply_cable_selection_visual(button)
			return

func get_cable_item_by_name(cable_name: String) -> Dictionary:
	var source_items: Array = []
	if current_menu_mode == "electrical":
		source_items = electrical_cable_items
	else:
		source_items = cable_items

	for cable in source_items:
		if str(cable.get("name", "")) == cable_name:
			return cable.duplicate(true)

	for cable in cable_items:
		if str(cable.get("name", "")) == cable_name:
			return cable.duplicate(true)
	for cable in electrical_cable_items:
		if str(cable.get("name", "")) == cable_name:
			return cable.duplicate(true)
	return {}