extends Node2D

@onready var radial_menu = $UI/RadialMenu
@onready var buy_menu = $BuyMenu
@onready var placed_units = $PlacedUnits
@onready var placement_preview = $PlacementPreview
@onready var hud = $CanvasLayer

var current_interactable = null
var selected_unit_to_place = null
var preview_area: Area2D = null
var preview_sprite: Sprite2D = null
var preview_collision: CollisionShape2D = null

var facing_order = ["front", "right", "back", "left"]
var current_facing_index := 0

func _ready() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)
	buy_menu.unit_selected.connect(_on_buy_menu_unit_selected)


func _on_interaction_requested(interactable) -> void:
	current_interactable = interactable

	var items = []
	for action in interactable.get_actions():
		items.append({
			"title": action,
			"id": action,
			"texture": get_action_icon(action)
		})

	radial_menu.set_items(items)
	radial_menu.open_menu(get_viewport().get_mouse_position())

func _on_menu_item_selected(id, _position) -> void:
	if current_interactable:
		current_interactable.perform_action(id)
		current_interactable = null

func get_action_icon(action_name: String) -> Texture2D:
	if action_name == "Turn Off":
		return load("res://assets/UI/icons/turn_off.svg")
	elif action_name == "Turn On":
		return load("res://assets/UI/icons/turn_on.svg")
	elif action_name == "Reboot":
		return load("res://assets/UI/icons/reboot.svg")
	elif action_name == "Inspect":
		return load("res://assets/UI/icons/inspect.svg")
	elif action_name.begins_with("Upgrade"):
		return load("res://assets/UI/icons/upgrade.svg")
	else:
		return null

func _on_buy_menu_unit_selected(unit_data) -> void:
	selected_unit_to_place = unit_data
	current_facing_index = 0
	create_placement_preview()

	print("Ready to place:", unit_data["name"])

func create_placement_preview() -> void:
	clear_placement_preview()

	if selected_unit_to_place == null:
		return

	preview_area = Area2D.new()
	preview_area.name = "PlacementPreviewArea"
	preview_area.collision_layer = 1 << 1
	preview_area.collision_mask = 1 << 1
	preview_area.monitoring = true
	preview_area.monitorable = true

	preview_sprite = Sprite2D.new()
	preview_collision = CollisionShape2D.new()

	var shape = RectangleShape2D.new()
	shape.size = Vector2(100, 100)
	preview_collision.shape = shape

	preview_sprite.texture = load(selected_unit_to_place["sprites"][get_current_facing()])
	preview_sprite.modulate = Color(1, 1, 1, 0.5)
	preview_sprite.z_index = 100

	preview_area.add_child(preview_sprite)
	preview_area.add_child(preview_collision)
	placement_preview.add_child(preview_area)

func get_current_facing() -> String:
	return facing_order[current_facing_index]

func clear_placement_preview() -> void:
	for child in placement_preview.get_children():
		child.queue_free()

	preview_area = null
	preview_sprite = null
	preview_collision = null

func _physics_process(_delta: float) -> void:
	if preview_area != null:
		preview_area.global_position = get_global_mouse_position()

		if can_place_at_current_position():
			preview_sprite.modulate = Color(1, 1, 1, 0.5)
		else:
			preview_sprite.modulate = Color(1, 0.3, 0.3, 0.5)

func _unhandled_input(event: InputEvent) -> void:
	if selected_unit_to_place == null or preview_area == null:
		return

	if event.is_action_pressed("rotate_left"):
		current_facing_index -= 1
		if current_facing_index < 0:
			current_facing_index = facing_order.size() - 1
		update_preview_texture()

	elif event.is_action_pressed("rotate_right"):
		current_facing_index += 1
		if current_facing_index >= facing_order.size():
			current_facing_index = 0
		update_preview_texture()

	elif event is InputEventMouseButton and event.pressed:
		print("mouse button detected: ", event.button_index)

		if event.button_index == MOUSE_BUTTON_LEFT:
			print("left click trying to place")
			place_selected_unit()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			print("right click cancel")
			cancel_placement()

func update_preview_texture() -> void:
	if preview_sprite == null or selected_unit_to_place == null:
		return

	var facing = get_current_facing()
	preview_sprite.texture = load(selected_unit_to_place["sprites"][facing])

	print("Facing:", facing)

func place_selected_unit() -> void:
	if selected_unit_to_place == null:
		return

	var cost = selected_unit_to_place["cost"]

	if not hud.can_afford(cost):
		print("Not enough money")
		return

	if not can_place_at_current_position():
		print("Cannot place here")
		return

	var packed_scene = load(selected_unit_to_place["scene_path"])
	if packed_scene == null:
		print("FAILED TO LOAD SCENE: ", selected_unit_to_place["scene_path"])
		return

	var new_unit = packed_scene.instantiate()

	# must be an Area2D root for your current placement validation
	if not (new_unit is Area2D):
		print("Placed scene root is not Area2D")
		return

	new_unit.name = selected_unit_to_place["id"]
	new_unit.collision_layer = 1 << 1
	new_unit.collision_mask = 1 << 1
	new_unit.monitoring = true
	new_unit.monitorable = true
	new_unit.add_to_group("placed_unit")

	placed_units.add_child(new_unit)
	new_unit.global_position = get_global_mouse_position()

	var facing = get_current_facing()

	if new_unit.has_method("set_facing"):
		new_unit.set_facing(facing)
	else:
		new_unit.set_meta("facing", facing)

	if new_unit.has_signal("interaction_requested"):
		new_unit.interaction_requested.connect(_on_interaction_requested)

	new_unit.set_meta("unit_id", selected_unit_to_place["id"])
	new_unit.set_meta("unit_name", selected_unit_to_place["name"])
	new_unit.set_meta("cost", selected_unit_to_place["cost"])
	new_unit.set_meta("facing", facing)

	hud.spend_money(cost)

	print("Placed:", selected_unit_to_place["name"], " facing ", facing)

	cancel_placement()

func cancel_placement() -> void:
	selected_unit_to_place = null
	clear_placement_preview()
	print("Placement cancelled")

func can_place_at_current_position() -> bool:
	if preview_area == null or preview_collision == null:
		return false

	var shape = preview_collision.shape
	if shape == null:
		print("preview collision has no shape")
		return false

	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = preview_area.global_transform
	query.collision_mask = 1 << 1
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state = get_world_2d().direct_space_state
	var results = space_state.intersect_shape(query)

	print("query hit count: ", results.size())

	for hit in results:
		var collider = hit["collider"]

		if collider == preview_area:
			continue

		print("hit collider: ", collider.name)

		if collider.is_in_group("placed_unit") or collider.is_in_group("blocked_placement"):
			return false

	return true

func _on_add_dev_money_requested(amount: float) -> void:
	hud.revenue += amount
	hud.cash_label.text = "$%.2f" % hud.revenue
	print("Dev money added:", amount)
