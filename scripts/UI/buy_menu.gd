extends CanvasLayer

signal unit_selected(unit_data)
signal add_dev_money_requested(amount)

@onready var title_label = $Panel/MainVBox/TitleLabel
@onready var tabs = $Panel/MainVBox/Tabs
@onready var unit_grid = $Panel/MainVBox/Tabs/UnitsTab/UnitGrid
@onready var other_label = $Panel/MainVBox/Tabs/OtherTab/OtherLabel
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
			"front": "res://assets/object_sprites/server_rack_1_front.png",
			"back": "res://assets/object_sprites/server_rack_1_back.png",
			"left": "res://assets/object_sprites/server_rack_1_left.png",
			"right": "res://assets/object_sprites/server_rack_1_right.png"
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
			"front": "res://assets/object_sprites/server_rack_2_front.png",
			"back": "res://assets/object_sprites/server_rack_2_back.png",
			"left": "res://assets/object_sprites/server_rack_2_left.png",
			"right": "res://assets/object_sprites/server_rack_2_right.png"
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
			"front": "res://assets/object_sprites/server_rack_3_front.png",
			"back": "res://assets/object_sprites/server_rack_3_back.png",
			"left": "res://assets/object_sprites/server_rack_3_left.png",
			"right": "res://assets/object_sprites/server_rack_3_right.png"
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
			"front": "res://assets/object_sprites/cooling_rack_1_front.png",
			"back": "res://assets/object_sprites/cooling_rack_1_back.png",
			"left": "res://assets/object_sprites/cooling_rack_1_left.png",
			"right": "res://assets/object_sprites/cooling_rack_1_right.png"
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
			"front": "res://assets/object_sprites/cooling_rack_2_front.png",
			"back": "res://assets/object_sprites/cooling_rack_2_back.png",
			"left": "res://assets/object_sprites/cooling_rack_2_left.png",
			"right": "res://assets/object_sprites/cooling_rack_2_right.png"
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
			"front": "res://assets/object_sprites/cooling_rack_3_front.png",
			"back": "res://assets/object_sprites/cooling_rack_3_back.png",
			"left": "res://assets/object_sprites/cooling_rack_3_left.png",
			"right": "res://assets/object_sprites/cooling_rack_3_right.png"
		}
	}
]

func _ready() -> void:
	title_label.text = "Buy Menu"
	tabs.set_tab_title(0, "Units")
	tabs.set_tab_title(1, "Other")
	other_label.text = "Nothing here yet"
	build_unit_list()
	dev_money_button.pressed.connect(_on_dev_money_button_pressed)

func build_unit_list() -> void:
	for child in unit_grid.get_children():
		child.queue_free()

	for unit in unit_data:
		var button = Button.new()
		button.text = "%s  |  $%s" % [unit["name"], unit["cost"]]
		button.custom_minimum_size = Vector2(220, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

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
