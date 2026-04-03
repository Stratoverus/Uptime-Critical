extends Control

@export var toggle_action_name: StringName = &"toggle_electrical_overlay"
@export var toggle_key: Key = KEY_J
@export var start_visible: bool = false
@export var connectable_group: StringName = &"electrical_connectable"
@export var connector_snap_distance: float = 24.0
@export var connector_radius: float = 7.0
@export var wire_width: float = 4.0
@export var wire_glow_width: float = 10.0
@export var wire_breakout_length: float = 26.0
@export var wire_corner_radius: float = 0.0
@export var overlay_tint: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var wire_color: Color = Color(0.12, 0.86, 1.0, 0.95)
@export var wire_glow_color: Color = Color(0.10, 0.75, 1.0, 0.20)
@export var connector_fill_color: Color = Color(0.95, 0.98, 1.0, 1.0)
@export var connector_outline_color: Color = Color(0.02, 0.04, 0.06, 0.95)
@export var connector_active_fill_color: Color = Color(1.0, 0.88, 0.40, 1.0)
@export var connector_active_outline_color: Color = Color(0.20, 0.14, 0.02, 0.95)

var connectors: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var dragging_connector: Dictionary = {}
var drag_mouse_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	ensure_action_with_key(toggle_action_name, toggle_key)
	set_overlay_visible(start_visible)
	print("ElectricalOverlay ready. Press J to toggle. Currently visible: ", visible)


func _process(_delta: float) -> void:
	if not visible:
		return

	refresh_connectors()
	prune_invalid_connections()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		drag_mouse_position = event.position
		if not dragging_connector.is_empty():
			queue_redraw()
		accept_event()
		return

	if event is InputEventMouseButton:
		drag_mouse_position = event.position
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if dragging_connector.is_empty():
				# Start wiring - click on a connector to begin
				begin_drag(event.position)
			else:
				# Complete wiring - click on another connector or cancel
				finish_drag(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Cancel wiring
			cancel_drag()
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action_name):
		set_overlay_visible(not visible)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			set_overlay_visible(false)
			get_tree().root.set_input_as_handled()


func set_overlay_visible(overlay_visible: bool) -> void:
	visible = overlay_visible
	dragging_connector.clear()
	queue_redraw()


func refresh_connectors() -> void:
	connectors.clear()
	var found_group_count = 0
	
	for node in get_tree().get_nodes_in_group(connectable_group):
		found_group_count += 1
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_electrical_nodes"):
			print("WARNING: Node in electrical_connectable group missing get_electrical_nodes method: ", node.name, " (", node.get_class(), ")")
			continue

		var node_entries: Variant = node.call("get_electrical_nodes")
		if not (node_entries is Array):
			print("WARNING: get_electrical_nodes returned non-Array for ", node.name)
			continue

		print("DEBUG: ", node.name, " returned ", node_entries.size(), " connector nodes")
		for i in range(node_entries.size()):
			var connector_node = node_entries[i]
			print("  Connector ", i, ": ", connector_node, " (is Node2D: ", connector_node is Node2D, ", valid: ", is_instance_valid(connector_node), ")")
			if not (connector_node is Node2D):
				print("    Skipping - not a Node2D")
				continue
			if not is_instance_valid(connector_node):
				print("    Skipping - not instance valid")
				continue

			connectors.append({
				"owner": node,
				"connector": connector_node,
				"screen_position": world_to_screen((connector_node as Node2D).global_position)
			})
	
	if visible:
		if found_group_count == 0:
			print("WARNING: Electrical overlay visible but found 0 objects in electrical_connectable group!")
		if connectors.is_empty() and found_group_count > 0:
			print("WARNING: Electrical overlay visible, found ", found_group_count, " objects but 0 valid connectors!")


func prune_invalid_connections() -> void:
	if connections.is_empty():
		return

	var valid_connections: Array[Dictionary] = []
	for connection in connections:
		var start_connector: Variant = connection.get("start_connector", null)
		var end_connector: Variant = connection.get("end_connector", null)
		if not (start_connector is Node2D and end_connector is Node2D):
			continue
		if not is_instance_valid(start_connector) or not is_instance_valid(end_connector):
			continue
		valid_connections.append(connection)

	connections = valid_connections


func begin_drag(mouse_position: Vector2) -> void:
	var connector := find_connector_at_position(mouse_position)
	if connector.is_empty():
		return

	var connector_node: Node2D = connector.get("connector", null)
	if connector_node == null or node_has_connection(connector_node):
		return

	dragging_connector = connector
	drag_mouse_position = mouse_position
	queue_redraw()


func finish_drag(mouse_position: Vector2) -> void:
	if dragging_connector.is_empty():
		return

	var target_connector := find_connector_at_position(mouse_position)
	if not target_connector.is_empty() and can_connect_connectors(dragging_connector, target_connector):
		add_connection(dragging_connector, target_connector)

	cancel_drag()


func cancel_drag() -> void:
	dragging_connector.clear()
	queue_redraw()


func add_connection(first_connector: Dictionary, second_connector: Dictionary) -> void:
	var start_node: Node2D = first_connector.get("connector", null)
	var end_node: Node2D = second_connector.get("connector", null)
	if start_node == null or end_node == null:
		return

	if connection_exists(start_node, end_node):
		return

	connections.append({
		"start_connector": start_node,
		"end_connector": end_node
	})
	queue_redraw()


func connection_exists(start_node: Node2D, end_node: Node2D) -> bool:
	for connection in connections:
		var stored_start: Variant = connection.get("start_connector", null)
		var stored_end: Variant = connection.get("end_connector", null)
		if stored_start == start_node and stored_end == end_node:
			return true
		if stored_start == end_node and stored_end == start_node:
			return true

	return false


func can_connect_connectors(first_connector: Dictionary, second_connector: Dictionary) -> bool:
	if first_connector.is_empty() or second_connector.is_empty():
		return false
	if first_connector == second_connector:
		return false

	var first_owner: Variant = first_connector.get("owner", null)
	var second_owner: Variant = second_connector.get("owner", null)
	if first_owner == null or second_owner == null:
		return false
	if first_owner == second_owner:
		return false

	var start_node: Node2D = first_connector.get("connector", null)
	var end_node: Node2D = second_connector.get("connector", null)
	if start_node == null or end_node == null:
		return false
	if node_has_connection(start_node):
		return false
	if node_has_connection(end_node):
		return false

	return not connection_exists(start_node, end_node)


func node_has_connection(connector_node: Node2D) -> bool:
	for connection in connections:
		var stored_start: Variant = connection.get("start_connector", null)
		var stored_end: Variant = connection.get("end_connector", null)
		if stored_start == connector_node or stored_end == connector_node:
			return true

	return false


func find_connector_at_position(screen_position: Vector2) -> Dictionary:
	var best_connector: Dictionary = {}
	var best_distance: float = connector_snap_distance

	for connector in connectors:
		var connector_position: Vector2 = connector.get("screen_position", Vector2.ZERO)
		var distance: float = connector_position.distance_to(screen_position)
		if distance > best_distance:
			continue
		best_distance = distance
		best_connector = connector

	return best_connector


func world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position


func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), overlay_tint, true)

	for connection in connections:
		draw_connection(connection)

	if not dragging_connector.is_empty():
		draw_drag_preview()

	for connector in connectors:
		draw_connector(connector)


func draw_connection(connection: Dictionary) -> void:
	var start_connector: Node2D = connection.get("start_connector", null)
	var end_connector: Node2D = connection.get("end_connector", null)
	if start_connector == null or end_connector == null:
		return
	if not is_instance_valid(start_connector) or not is_instance_valid(end_connector):
		return

	var wire_points: PackedVector2Array = build_wire_points(start_connector, end_connector)
	if wire_points.size() < 2:
		return
	draw_polyline(wire_points, wire_glow_color, wire_glow_width, true)
	draw_polyline(wire_points, wire_color, wire_width, true)


func draw_drag_preview() -> void:
	var start_connector: Node2D = dragging_connector.get("connector", null)
	if start_connector == null or not is_instance_valid(start_connector):
		return

	var wire_points: PackedVector2Array = build_wire_points_to_position(start_connector, drag_mouse_position)
	if wire_points.size() < 2:
		return
	draw_polyline(wire_points, wire_glow_color, wire_glow_width, true)
	draw_polyline(wire_points, wire_color, wire_width, true)


func build_wire_points(start_connector: Node2D, end_connector: Node2D) -> PackedVector2Array:
	var start_position: Vector2 = world_to_screen(start_connector.global_position)
	var end_position: Vector2 = world_to_screen(end_connector.global_position)
	var start_direction: Vector2 = get_connector_exit_direction(start_connector)
	var end_direction: Vector2 = get_connector_exit_direction(end_connector)

	var start_anchor: Vector2 = start_position + (start_direction * wire_breakout_length)
	var end_anchor: Vector2 = end_position + (end_direction * wire_breakout_length)

	return build_orthogonal_path(start_position, start_anchor, end_anchor, end_position)


func build_wire_points_to_position(start_connector: Node2D, screen_target: Vector2) -> PackedVector2Array:
	var start_position: Vector2 = world_to_screen(start_connector.global_position)
	var start_direction: Vector2 = get_connector_exit_direction(start_connector)
	var start_anchor: Vector2 = start_position + (start_direction * wire_breakout_length)

	return build_orthogonal_path(start_position, start_anchor, screen_target, screen_target)


func build_orthogonal_path(start_point: Vector2, start_anchor: Vector2, end_anchor: Vector2, end_point: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.append(start_point)
	points.append(start_anchor)

	var dx: float = abs(end_anchor.x - start_anchor.x)
	var dy: float = abs(end_anchor.y - start_anchor.y)
	if dx >= dy:
		append_unique_point(points, Vector2(end_anchor.x, start_anchor.y))
	else:
		append_unique_point(points, Vector2(start_anchor.x, end_anchor.y))

	append_unique_point(points, end_anchor)
	append_unique_point(points, end_point)

	if wire_corner_radius > 0.0:
		return points
	return points


func append_unique_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty():
		points.append(point)
		return
	if points[points.size() - 1].distance_to(point) <= 0.01:
		return
	points.append(point)


func get_connector_exit_direction(connector_node: Node2D) -> Vector2:
	var owner_node: Node2D = connector_node.get_parent() as Node2D
	if owner_node == null:
		return Vector2.RIGHT

	var delta: Vector2 = connector_node.global_position - owner_node.global_position
	if abs(delta.x) >= abs(delta.y):
		return Vector2.RIGHT if delta.x >= 0.0 else Vector2.LEFT

	return Vector2.DOWN if delta.y >= 0.0 else Vector2.UP


func draw_connector(connector: Dictionary) -> void:
	var connector_node: Node2D = connector.get("connector", null)
	if connector_node == null or not is_instance_valid(connector_node):
		return

	var connector_position: Vector2 = connector.get("screen_position", Vector2.ZERO)
	var is_dragging_start: bool = not dragging_connector.is_empty() and dragging_connector.get("connector", null) == connector_node
	var fill_color: Color = connector_active_fill_color if is_dragging_start else connector_fill_color
	var outline_color: Color = connector_active_outline_color if is_dragging_start else connector_outline_color

	draw_circle(connector_position, connector_radius + 2.5, outline_color)
	draw_circle(connector_position, connector_radius, fill_color)


func ensure_action_with_key(action_name: StringName, action_key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == action_key:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = action_key
	InputMap.action_add_event(action_name, key_event)