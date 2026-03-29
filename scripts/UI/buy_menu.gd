extends CanvasLayer

signal unit_selected(unit_data)
signal add_dev_money_requested(amount)

@onready var title_label = $Panel/MainVBox/TitleLabel
@onready var unit_grid = $Panel/MainVBox/UnitGrid
@onready var dev_money_button = $Panel/MainVBox/DevMoneyButton

var selected_button: Button = null

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
		print("style_menu_button got null button")
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
	print(get_node_or_null("Panel/MainVBox"))
	print(get_node_or_null("Panel/MainVBox/UnitGrid"))
	print("title_label:", title_label)
	print("unit_grid:", unit_grid)
	print("dev_money_button:", dev_money_button)

	if title_label == null or unit_grid == null or dev_money_button == null:
		push_error("BuyMenu node path mismatch")
		return

	title_label.text = "Buy Menu"
	style_dev_button(dev_money_button)
	build_unit_list()
	dev_money_button.pressed.connect(_on_dev_money_button_pressed)

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

func _on_unit_pressed(button: Button) -> void:
	var unit = button.get_meta("unit_data")

	if selected_button != null:
		selected_button.modulate = Color(1, 1, 1, 1)

	selected_button = button
	selected_button.modulate = Color(0.7, 1.0, 0.7, 1.0)

	print("Selected unit:", unit["id"], " Cost:", unit["cost"])

	unit_selected.emit(unit)

func _on_dev_money_button_pressed() -> void:
	add_dev_money_requested.emit(100)
