extends CanvasLayer

@onready var title_label = $Panel/MainVBox/TitleLabel
@onready var unit_grid = $Panel/MainVBox/UnitGrid

var unit_data = [
	{ "id": "server_rack_l1", "name": "Server Rack L1", "cost": 100 },
	{ "id": "server_rack_l2", "name": "Server Rack L2", "cost": 200 },
	{ "id": "server_rack_l3", "name": "Server Rack L3", "cost": 300 },
	{ "id": "cooling_unit_l1", "name": "Cooling Unit L1", "cost": 120 },
	{ "id": "cooling_unit_l2", "name": "Cooling Unit L2", "cost": 240 },
	{ "id": "cooling_unit_l3", "name": "Cooling Unit L3", "cost": 360 }
]

func _ready() -> void:
	title_label.text = "Buy Menu"
	build_unit_list()

func build_unit_list() -> void:
	for child in unit_grid.get_children():
		child.queue_free()

	for unit in unit_data:
		var button = Button.new()
		button.text = "%s - $%s" % [unit.name, unit.cost]
		button.custom_minimum_size = Vector2(220, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		unit_grid.add_child(button)