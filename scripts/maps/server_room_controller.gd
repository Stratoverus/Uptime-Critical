extends Node2D

signal cable_mode_changed(is_enabled)

@onready var radial_menu = $UI/RadialMenu
@onready var buy_menu = $BuyMenu
@onready var placed_units = $PlacedUnits
@onready var placement_preview = $PlacementPreview
@onready var hud = $HUD
@onready var player = get_tree().get_first_node_in_group("player")
@onready var cable_mode_button = $BuyMenu/Panel/MainVBox/CableModeButton


var pending_action: String = ""
var current_interactable = null
var selected_unit_to_place = null
var preview_area: Area2D = null
var preview_sprite: Sprite2D = null
var preview_collision: CollisionShape2D = null
var menu_opened_in_range: bool = false
var facing_order = ["front", "right", "back", "left"]
var current_facing_index := 0
var is_cable_mode := false
var selected_cable_type = null
var cable_start_point = null
var cable_placement_active := false
var last_cable_click_time := 0
var placed_cable_segments: Array = []
var cable_preview_line: Line2D = null
var cable_preview_label: Label = null

func _ready() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)
	buy_menu.unit_selected.connect(_on_buy_menu_unit_selected)


	if cable_mode_button:
		cable_mode_button.pressed.connect(_on_cable_mode_button_pressed)

func _on_interaction_requested(interactable) -> void:
	if is_cable_mode:
		if radial_menu.visible:
			radial_menu.hide()
		return

	current_interactable = interactable
	pending_action = ""
	menu_opened_in_range = interactable.is_player_in_range()

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
	if current_interactable == null:
		return

	pending_action = id

	if current_interactable.is_player_in_range():
		_perform_pending_action()
	else:
		var current_player = get_player()
		if current_player != null and current_player.has_method("move_to_interactable"):
			current_player.move_to_interactable(current_interactable)

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
	if is_cable_mode:
		selected_cable_type = unit_data
		selected_unit_to_place = null
		clear_placement_preview()
		cable_start_point = null
		cable_placement_active = true
		clear_cable_preview()
		return

	selected_cable_type = null
	cable_placement_active = false
	cable_start_point = null

	selected_unit_to_place = unit_data
	current_facing_index = 0
	create_placement_preview()

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

		if preview_sprite != null:
			if can_place_at_current_position():
				preview_sprite.modulate = Color(1, 1, 1, 0.5)
			else:
				preview_sprite.modulate = Color(1, 0.3, 0.3, 0.5)
	update_cable_preview()

	if current_interactable != null and pending_action != "":
		var current_player = get_player()
		if current_interactable.is_player_in_range():
			if current_player != null and "auto_moving" in current_player:
				current_player.auto_moving = false
			_perform_pending_action()

	if current_interactable != null and radial_menu.visible and pending_action == "":
		if menu_opened_in_range and not current_interactable.is_player_in_range():
			radial_menu.hide()
			current_interactable = null
			menu_opened_in_range = false

func _unhandled_input(event: InputEvent) -> void:
	if is_cable_mode:
		_handle_cable_mode_input(event)
		return

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
		if event.button_index == MOUSE_BUTTON_LEFT:
			place_selected_unit()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()

func update_preview_texture() -> void:
	if preview_sprite == null or selected_unit_to_place == null:
		return

	var facing = get_current_facing()
	preview_sprite.texture = load(selected_unit_to_place["sprites"][facing])

func place_selected_unit() -> void:
	if selected_unit_to_place == null:
		return

	var cost = selected_unit_to_place["cost"]

	if is_cable_mode:
		return

	if GameManager == null:
		push_error("GameManager not found")
		return

	if not GameManager.can_afford(cost):
		return

	if not can_place_at_current_position():
		return

	var packed_scene = load(selected_unit_to_place["scene_path"])
	if packed_scene == null:
		push_error("FAILED TO LOAD SCENE: %s" % selected_unit_to_place["scene_path"])
		return

	var new_unit = packed_scene.instantiate()

	if not (new_unit is Area2D):
		push_error("Placed scene root is not Area2D")
		return

	new_unit.name = selected_unit_to_place["id"]
	new_unit.collision_layer = 1 << 1
	new_unit.collision_mask = 1 << 1
	new_unit.monitoring = true
	new_unit.monitorable = true
	new_unit.add_to_group("placed_unit")

	placed_units.add_child(new_unit)
	new_unit.global_position = get_global_mouse_position()
	new_unit.set_meta("ignore_interaction_until", Time.get_ticks_msec() + 150)

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

	GameManager.spend_money(cost)

	cancel_placement()

func cancel_placement() -> void:
	selected_unit_to_place = null
	clear_placement_preview()

func can_place_at_current_position() -> bool:
	if preview_area == null or preview_collision == null:
		return false

	var shape = preview_collision.shape
	if shape == null:
		return false

	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = preview_area.global_transform
	query.collision_mask = 1 << 1
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var space_state = get_world_2d().direct_space_state
	var results = space_state.intersect_shape(query)

	for hit in results:
		var collider = hit["collider"]

		if collider == preview_area:
			continue

		if collider.is_in_group("placed_unit") or collider.is_in_group("blocked_placement"):
			return false

	return true

func _on_add_dev_money_requested(amount: float) -> void:
	if GameManager == null:
		push_error("GameManager not found")
		return

	GameManager.add_money(amount)

func _perform_pending_action() -> void:
	if current_interactable == null or pending_action == "":
		return

	current_interactable.perform_action(pending_action)
	pending_action = ""
	menu_opened_in_range = false
	radial_menu.hide()
	current_interactable = null

func get_player():
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	return player

func _on_cable_mode_button_pressed() -> void:
	set_cable_mode(not is_cable_mode)

func set_cable_mode(enabled: bool) -> void:
	if is_cable_mode == enabled:
		return

	is_cable_mode = enabled

	if is_cable_mode:
		selected_unit_to_place = null
		clear_placement_preview()
		clear_cable_preview()
	else:
		selected_cable_type = null
		cable_start_point = null
		cable_placement_active = false
		clear_cable_preview()

	if is_cable_mode and radial_menu:
		radial_menu.hide()

	cable_mode_changed.emit(is_cable_mode)
	_update_cable_mode_button()
	update_all_network_node_highlights()

	if buy_menu and buy_menu.has_method("set_menu_mode"):
		buy_menu.set_menu_mode(is_cable_mode)

	update_cable_visibility()

func _update_cable_mode_button() -> void:
	if not cable_mode_button:
		return

	if is_cable_mode:
		cable_mode_button.text = "Exit Cable Mode"
	else:
		cable_mode_button.text = "Cable Mode"

func update_all_network_node_highlights() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.has_method("set_cable_mode_highlight"):
			node.set_cable_mode_highlight(is_cable_mode)



func _handle_cable_mode_input(event: InputEvent) -> void:
	if not cable_placement_active:
		return

	if event is InputEventMouseButton and event.pressed:
		var now = Time.get_ticks_msec()
		if now - last_cable_click_time < 120:
			return
		last_cable_click_time = now

		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			var clicked_node = get_clicked_network_node(mouse_pos)

			if clicked_node != null:
				_handle_cable_node_click(clicked_node)
			else:
				_handle_cable_empty_click(mouse_pos)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected_cable_type = null
			cable_start_point = null
			cable_placement_active = false
			clear_cable_preview()

func get_clicked_network_node(mouse_position: Vector2):
	var space_state = get_world_2d().direct_space_state

	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_position
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var results = space_state.intersect_point(query, 16)

	for result in results:
		var collider = result.collider
		var network_node = find_network_node_from_collider(collider)
		if network_node != null:
			return network_node

	return null

func _handle_cable_node_click(node) -> void:
	if cable_start_point == null:
		cable_start_point = node
		return

	if node == cable_start_point:
		return

	var success = create_cable_segment(cable_start_point, node)
	if success:
		cable_start_point = node

func _handle_cable_empty_click(mouse_position: Vector2) -> void:
	if cable_start_point == null:
		return

	if cable_start_point.global_position.distance_to(mouse_position) < 20.0:
		return

	var anchor = create_cable_anchor(mouse_position)
	var success = create_cable_segment(cable_start_point, anchor)

	if success:
		cable_start_point = anchor
	else:
		anchor.queue_free()

func find_network_node_from_collider(node):
	var current = node

	while current != null:
		if current.is_in_group("network_nodes"):
			return current
		current = current.get_parent()

	return null

# "res://scenes/units/cable_anchor.tscn"

func create_cable_anchor(anchor_position: Vector2):
	var scene = preload("res://scenes/units/cable_anchor.tscn")
	var anchor = scene.instantiate()

	get_tree().current_scene.add_child(anchor)
	anchor.global_position = anchor_position
	anchor.name = "CableAnchor_%d" % Time.get_ticks_msec()
	anchor.object_name = "Cable Anchor"

	update_all_network_node_highlights()

	return anchor

func get_network_point_name(node) -> String:
	if node == null:
		return "Unknown"

	var object_name_value = node.get("object_name")
	if object_name_value != null and str(object_name_value) != "":
		return str(object_name_value)

	return str(node.name)

func create_cable_segment(start_node, end_node) -> bool:
	if selected_cable_type == null:
		return false

	if not can_accept_new_connection(start_node):
		return false

	if not can_accept_new_connection(end_node):
		return false

	var scene = preload("res://scenes/units/cable_segment.tscn")
	var segment = scene.instantiate()

	get_tree().current_scene.add_child(segment)
	segment.setup(start_node, end_node, selected_cable_type)

	if segment.length < 5.0:
		segment.queue_free()
		return false

	if GameManager == null:
		push_error("GameManager not found")
		segment.queue_free()
		return false

	if GameManager.can_afford(segment.total_cost):
		GameManager.spend_money(segment.total_cost)
	else:
		segment.queue_free()
		return false

	placed_cable_segments.append(segment)

	if start_node.has_method("add_connection"):
		start_node.add_connection(segment)

	if end_node.has_method("add_connection"):
		end_node.add_connection(segment)

	# print(
	# 	"Created segment from",
	# 	get_network_point_name(start_node),
	# 	"to",
	# 	get_network_point_name(end_node),
	# 	"| length:",
	# 	int(segment.length),
	# 	"| cost:",
	# 	int(segment.total_cost)
	# )

	# print(get_network_point_name(start_node), " connections: ", start_node.connected_segments.size())
	# print(get_network_point_name(end_node), " connections: ", end_node.connected_segments.size())

	if start_node.get("network_node_type") == "router":
		print(
			get_network_point_name(start_node),
			" ports used: ",
			start_node.connected_segments.size(),
			"/",
			start_node.get_port_limit()
		)

	if end_node.get("network_node_type") == "router":
		print(get_network_point_name(end_node), " ports used: ", end_node.connected_segments.size(), "/", end_node.port_limit)

	debug_check_all_servers()
	update_all_server_network_status()
	return true

func update_cable_visibility() -> void:
	for cable in get_tree().get_nodes_in_group("cable_segments"):
		cable.visible = is_cable_mode

func ensure_cable_preview_exists() -> void:
	if cable_preview_line == null:
		cable_preview_line = Line2D.new()
		cable_preview_line.width = 4.0
		cable_preview_line.visible = false
		get_tree().current_scene.add_child(cable_preview_line)

	if cable_preview_label == null:
		cable_preview_label = Label.new()
		cable_preview_label.visible = false
		cable_preview_label.z_index = 100
		get_tree().current_scene.add_child(cable_preview_label)

func clear_cable_preview() -> void:
	if cable_preview_line:
		cable_preview_line.visible = false
		cable_preview_line.clear_points()

	if cable_preview_label:
		cable_preview_label.visible = false
		cable_preview_label.text = ""

func update_cable_preview() -> void:
	if not is_cable_mode:
		clear_cable_preview()
		return

	if not cable_placement_active:
		clear_cable_preview()
		return

	if cable_start_point == null:
		clear_cable_preview()
		return

	if selected_cable_type == null:
		clear_cable_preview()
		return

	ensure_cable_preview_exists()

	var start_pos = cable_start_point.global_position
	var end_pos = get_global_mouse_position()

	cable_preview_line.clear_points()
	cable_preview_line.add_point(start_pos)
	cable_preview_line.add_point(end_pos)
	cable_preview_line.default_color = selected_cable_type.get("color", Color.WHITE)
	cable_preview_line.visible = true

	var preview_length = start_pos.distance_to(end_pos)
	var preview_cost = preview_length * selected_cable_type.get("cost", 0)

	cable_preview_label.text = "$" + str(int(preview_cost))
	cable_preview_label.position = (start_pos + end_pos) * 0.5
	cable_preview_label.visible = true

func can_reach_router(start_node) -> bool:
	if start_node == null:
		return false

	var visited = {}
	var queue = [start_node]

	while queue.size() > 0:
		var current = queue.pop_front()

		if current == null:
			continue

		if visited.has(current):
			continue

		visited[current] = true

		var node_type = current.get("network_node_type")
		if node_type == "router":
			return true

		var segments = current.get("connected_segments")
		if segments == null:
			continue

		for segment in segments:
			if segment == null:
				continue

			var next_point = segment.get_other_point(current)
			if next_point != null and not visited.has(next_point):
				queue.append(next_point)

	return false

func debug_check_all_servers() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.get("network_node_type") == "server":
			var connected = can_reach_router(node)
			print(get_network_point_name(node), " router reachable: ", connected)

func update_all_server_network_status() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.get("network_node_type") == "server":
			var connected = can_reach_router(node)
			node.update_network_status(connected)

func can_accept_new_connection(node) -> bool:
	if node == null:
		return false

	var node_type = node.get("network_node_type")

	if node_type == "router":
		if node.has_method("has_free_port"):
			return node.has_free_port()
		return false

	# Servers and anchors can accept connections for now
	return true