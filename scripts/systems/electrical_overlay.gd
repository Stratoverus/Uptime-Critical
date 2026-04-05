extends Control

const WiringGraph = preload("res://scripts/systems/wiring/wiring_graph.gd")

@onready var buy_menu = get_tree().current_scene.get_node_or_null("BuyMenu")

@export var start_visible: bool = false
@export var connectable_group: StringName = &"electrical_connectable"
@export var anchor_group: StringName = &"electrical_anchors"
@export var connector_snap_distance: float = 24.0
@export var anchor_min_distance_from_nodes: float = 20.0
@export var connector_radius: float = 7.0
@export var wire_width: float = 4.0
@export var wire_glow_width: float = 10.0
@export var wire_breakout_length: float = 26.0
@export var overlay_fade_duration: float = 0.0
@export var overlay_tint: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var wire_color: Color = Color(0.12, 0.86, 1.0, 0.95)
@export var wire_glow_color: Color = Color(0.10, 0.75, 1.0, 0.20)
@export var wire_highlight_color: Color = Color(1.0, 0.88, 0.40, 1.0)
@export var wire_highlight_glow_color: Color = Color(1.0, 0.70, 0.10, 0.40)
@export var connector_fill_color: Color = Color(0.95, 0.98, 1.0, 1.0)
@export var connector_outline_color: Color = Color(0.02, 0.04, 0.06, 0.95)
@export var connector_active_fill_color: Color = Color(1.0, 0.88, 0.40, 1.0)
@export var connector_active_outline_color: Color = Color(0.20, 0.14, 0.02, 0.95)
@export var connector_icon_color: Color = Color(0.10, 0.10, 0.10, 0.95)
@export var connector_icon_size: int = 14
@export var status_message_duration: float = 1.4

var connectors: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var dragging_connector: Dictionary = {}
var drag_mouse_position: Vector2 = Vector2.ZERO
var overlay_fade_tween: Tween = null
var overlay_title_label: Label = null
var overlay_status_label: Label = null
var overlay_status_hide_at_ms: int = 0
var selected_cable_type: Dictionary = {}
var selected_connection: Dictionary = {}
var highlighted_connections: Array[Dictionary] = []
var wire_delete_confirmation_open := false
var default_power_cable := {
	"name": "Power Cable",
	"color": Color(0.12, 0.86, 1.0, 0.95),
	"cost": 2
}

func _ready() -> void:
	add_to_group("electrical_overlay")
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = start_visible
	modulate = Color(1.0, 1.0, 1.0, 1.0 if start_visible else 0.0)
	update_anchor_visibility(start_visible)
	call_deferred("update_all_power_states")

func _process(_delta: float) -> void:
	if not visible:
		return

	refresh_connectors()
	prune_invalid_connections()
	update_all_power_states()
	_update_overlay_status_visibility()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		drag_mouse_position = event.position
		if not dragging_connector.is_empty():
			queue_redraw()
		return

	if event is InputEventMouseButton:
		drag_mouse_position = event.position
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if dragging_connector.is_empty():
				# Node/connector clicks must take priority over wire hits.
				var clicked_connector := find_connector_at_position(event.position)
				if not clicked_connector.is_empty():
					selected_connection.clear()
					highlighted_connections.clear()
					begin_drag(event.position)
					accept_event()
					return

				var clicked_connection := find_connection_at_position(event.position)
				if not clicked_connection.is_empty():
					highlight_wire_route(clicked_connection)
					accept_event()
					return

				selected_connection.clear()
				highlighted_connections.clear()
			else:
				selected_connection.clear()
				highlighted_connections.clear()
				handle_placement_click(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not selected_connection.is_empty():
				show_delete_wire_confirmation()
				accept_event()
				return
			selected_connection.clear()
			highlighted_connections.clear()
			cancel_drag()
			accept_event()

func handle_placement_click(mouse_position: Vector2) -> void:
	var target_connector := find_connector_at_position(mouse_position)
	if not target_connector.is_empty() and can_connect_connectors(dragging_connector, target_connector):
		add_connection(dragging_connector, target_connector)
		var target_node: Node2D = target_connector.get("connector", null)
		if target_node != null and target_node.is_in_group(anchor_group):
			dragging_connector = target_connector
			queue_redraw()
		else:
			cancel_drag()
		return

	if not target_connector.is_empty() and would_create_loop(dragging_connector.get("connector", null), target_connector.get("connector", null)):
		_show_overlay_status("Cannot place electrical wire: this would create a loop.")
		return

	var anchor_connector := create_anchor_connector(mouse_position)
	if anchor_connector.is_empty():
		return

	if can_connect_connectors(dragging_connector, anchor_connector):
		add_connection(dragging_connector, anchor_connector)
		dragging_connector = anchor_connector
		queue_redraw()
	else:
		var anchor_owner: Node = anchor_connector.get("owner", null)
		if anchor_owner != null and is_instance_valid(anchor_owner):
			anchor_owner.queue_free()
		if would_create_loop(dragging_connector.get("connector", null), anchor_connector.get("connector", null)):
			_show_overlay_status("Cannot place electrical wire: this would create a loop.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_electrical_overlay"):
		toggle_overlay()
		get_viewport().set_input_as_handled()

func set_overlay_visible(overlay_visible: bool) -> void:
	if overlay_visible:
		_deactivate_other_overlays()

	if overlay_fade_tween != null and overlay_fade_tween.is_valid():
		overlay_fade_tween.kill()

	if overlay_fade_duration <= 0.0:
		visible = overlay_visible
		modulate.a = 1.0 if overlay_visible else 0.0
		if overlay_visible:
			show_overlay_title("Electrical Overlay")
		else:
			hide_overlay_title()
		update_all_port_label_visibility(overlay_visible)
		update_anchor_visibility(overlay_visible)
		dragging_connector.clear()
		selected_connection.clear()
		highlighted_connections.clear()
		update_all_power_states()
		queue_redraw()
		return

	if overlay_visible:
		visible = true
		modulate.a = 0.0
		overlay_fade_tween = create_tween()
		overlay_fade_tween.tween_property(self, "modulate:a", 1.0, overlay_fade_duration)
	else:
		overlay_fade_tween = create_tween()
		overlay_fade_tween.tween_property(self, "modulate:a", 0.0, overlay_fade_duration)
		overlay_fade_tween.finished.connect(_on_fade_out_finished)

	if overlay_visible:
		_ensure_default_cable_type()
		_sync_buy_menu_cable_selection()
		show_overlay_title("Electrical Overlay")
	else:
		hide_overlay_title()
		if overlay_status_label != null:
			overlay_status_label.visible = false
			overlay_status_hide_at_ms = 0

	update_all_port_label_visibility(overlay_visible)

	update_anchor_visibility(overlay_visible)
	dragging_connector.clear()
	selected_connection.clear()
	highlighted_connections.clear()
	update_all_power_states()
	queue_redraw()

func _deactivate_other_overlays() -> void:
	for network_overlay in get_tree().get_nodes_in_group("network_overlay"):
		if network_overlay != null and network_overlay.has_method("set_overlay_visible"):
			network_overlay.call("set_overlay_visible", false, true)

	for thermal_system in get_tree().get_nodes_in_group("thermal_system"):
		if thermal_system != null and thermal_system.has_method("set_heat_view_enabled"):
			thermal_system.call("set_heat_view_enabled", false)

func _on_fade_out_finished() -> void:
	visible = false
	queue_redraw()

func update_anchor_visibility(anchor_visible: bool) -> void:
	for node in get_tree().get_nodes_in_group(anchor_group):
		if node is CanvasItem:
			(node as CanvasItem).visible = anchor_visible

func toggle_overlay() -> void:
	set_overlay_visible(not visible)

func refresh_connectors() -> void:
	connectors.clear()

	for node in get_tree().get_nodes_in_group(connectable_group):
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_electrical_nodes"):
			continue

		var node_entries: Variant = node.call("get_electrical_nodes")
		if not (node_entries is Array):
			continue

		for connector_node in node_entries:
			if not (connector_node is Node2D):
				continue
			if not is_instance_valid(connector_node):
				continue

			connectors.append({
				"owner": node,
				"connector": connector_node,
				"screen_position": world_to_screen((connector_node as Node2D).global_position)
			})

	for node in get_tree().get_nodes_in_group(anchor_group):
		if not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		connectors.append({
			"owner": node,
			"connector": node,
			"screen_position": world_to_screen(node.global_position)
		})

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

func begin_drag(mouse_position: Vector2) -> bool:
	var connector := find_connector_at_position(mouse_position)
	if connector.is_empty():
		return false

	var connector_node: Node2D = connector.get("connector", null)
	var owner_node: Node = connector.get("owner", null)
	if connector_node == null:
		return false
	if not _connector_has_capacity(connector_node, owner_node):
		return false

	dragging_connector = connector
	drag_mouse_position = mouse_position
	queue_redraw()
	return true

func cancel_drag() -> void:
	dragging_connector.clear()
	queue_redraw()

func create_anchor_connector(mouse_position: Vector2) -> Dictionary:
	if _is_anchor_too_close_to_connector(mouse_position):
		_show_overlay_status("Cannot place anchor that close to a node.")
		return {}

	var scene = preload("res://scenes/units/cable_anchor.tscn")
	var anchor = scene.instantiate()
	anchor.anchor_group_name = anchor_group
	get_tree().current_scene.add_child(anchor)
	anchor.global_position = mouse_position
	anchor.name = "ElectricalAnchor_%d" % Time.get_ticks_msec()
	return {
		"owner": anchor,
		"connector": anchor,
		"screen_position": world_to_screen(anchor.global_position)
	}

func add_connection(first_connector: Dictionary, second_connector: Dictionary) -> void:
	var start_node: Node2D = first_connector.get("connector", null)
	var end_node: Node2D = second_connector.get("connector", null)
	var start_owner: Node = first_connector.get("owner", null)
	var end_owner: Node = second_connector.get("owner", null)
	if start_node == null or end_node == null:
		return

	if connection_exists(start_node, end_node):
		return
	if would_create_loop(start_node, end_node):
		return

	if not _connector_has_capacity(start_node, start_owner):
		return
	if not _connector_has_capacity(end_node, end_owner):
		return
	if _is_router_electrical_connector(start_owner, start_node) and get_connection_count_for_node(start_node) >= 1:
		return
	if _is_router_electrical_connector(end_owner, end_node) and get_connection_count_for_node(end_node) >= 1:
		return

	connections.append({
		"start_connector": start_node,
		"end_connector": end_node,
		"wire_color": _get_selected_wire_color(),
		"wire_glow_color": _get_selected_wire_glow_color()
	})
	if start_owner != null:
		if start_owner.has_method("add_electrical_connection"):
			start_owner.add_electrical_connection(end_node)
		elif start_owner.has_method("add_connection") and not start_owner.is_in_group("network_nodes"):
			start_owner.add_connection(end_node)
	if end_owner != null:
		if end_owner.has_method("add_electrical_connection"):
			end_owner.add_electrical_connection(start_node)
		elif end_owner.has_method("add_connection") and not end_owner.is_in_group("network_nodes"):
			end_owner.add_connection(start_node)
	if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
		SaveManager.mark_runtime_dirty()
	selected_connection.clear()
	highlighted_connections.clear()
	update_all_power_states()
	queue_redraw()

func remove_connection_at_position(screen_position: Vector2) -> bool:
	var target_connection := find_connection_at_position(screen_position)
	if target_connection.is_empty():
		return false

	remove_connection(target_connection)
	return true

func remove_connection(connection: Dictionary) -> void:
	var start_node: Node2D = connection.get("start_connector", null)
	var end_node: Node2D = connection.get("end_connector", null)
	var start_owner: Node = _find_connector_owner(start_node)
	var end_owner: Node = _find_connector_owner(end_node)
	connections.erase(connection)

	if start_owner != null:
		if start_owner.has_method("remove_electrical_connection"):
			start_owner.remove_electrical_connection(end_node)
		elif start_owner.has_method("remove_connection") and not start_owner.is_in_group("network_nodes"):
			start_owner.remove_connection(end_node)
	if end_owner != null:
		if end_owner.has_method("remove_electrical_connection"):
			end_owner.remove_electrical_connection(start_node)
		elif end_owner.has_method("remove_connection") and not end_owner.is_in_group("network_nodes"):
			end_owner.remove_connection(start_node)

	if start_node != null and start_node.is_in_group(anchor_group) and not node_has_connection(start_node):
		start_node.queue_free()
	if end_node != null and end_node.is_in_group(anchor_group) and not node_has_connection(end_node):
		end_node.queue_free()

	if selected_connection == connection:
		selected_connection.clear()
	highlighted_connections.clear()
	if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
		SaveManager.mark_runtime_dirty()
	update_all_power_states()
	queue_redraw()

func find_connection_at_position(screen_position: Vector2) -> Dictionary:
	var best_connection: Dictionary = {}
	var best_distance := connector_snap_distance

	for connection in connections:
		var start_node: Node2D = connection.get("start_connector", null)
		var end_node: Node2D = connection.get("end_connector", null)
		if start_node == null or end_node == null:
			continue

		var wire_points := build_wire_points(start_node, end_node)
		if wire_points.size() < 2:
			continue

		var distance := distance_to_polyline(screen_position, wire_points)
		if distance <= best_distance:
			best_distance = distance
			best_connection = connection

	return best_connection

func distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var best_distance := 999999.0
	for i in range(points.size() - 1):
		best_distance = min(best_distance, distance_to_segment(point, points[i], points[i + 1]))
	return best_distance

func distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment_vector := segment_end - segment_start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.001:
		return point.distance_to(segment_start)

	var t: float = clamp((point - segment_start).dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	var projection: Vector2 = segment_start + segment_vector * t
	return point.distance_to(projection)

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
	var start_owner: Node = first_connector.get("owner", null)
	var end_owner: Node = second_connector.get("owner", null)
	if start_node == null or end_node == null:
		return false
	if not _connector_has_capacity(start_node, start_owner):
		return false
	if not _connector_has_capacity(end_node, end_owner):
		return false
	if _is_router_electrical_connector(start_owner, start_node) and get_connection_count_for_node(start_node) >= 1:
		return false
	if _is_router_electrical_connector(end_owner, end_node) and get_connection_count_for_node(end_node) >= 1:
		return false
	if would_create_loop(start_node, end_node):
		return false

	return not connection_exists(start_node, end_node)

func node_has_connection(connector_node: Node2D) -> bool:
	for connection in connections:
		var stored_start: Variant = connection.get("start_connector", null)
		var stored_end: Variant = connection.get("end_connector", null)
		if stored_start == connector_node or stored_end == connector_node:
			return true

	return false

func get_connection_count_for_node(connector_node: Node2D) -> int:
	if connector_node == null:
		return 0

	var count := 0
	for connection in connections:
		var stored_start: Variant = connection.get("start_connector", null)
		var stored_end: Variant = connection.get("end_connector", null)
		if stored_start == connector_node or stored_end == connector_node:
			count += 1

	return count

func _connector_has_capacity(connector_node: Node2D, owner_node: Node) -> bool:
	if connector_node == null:
		return false

	if connector_node.is_in_group(anchor_group):
		return true

	var connection_count := get_connection_count_for_node(connector_node)

	if owner_node != null and owner_node.has_method("can_accept_electrical_connection"):
		return bool(owner_node.call("can_accept_electrical_connection", connector_node, connection_count))

	return connection_count == 0

func _is_router_electrical_connector(owner_node: Node, connector_node: Node2D) -> bool:
	if owner_node == null or connector_node == null:
		return false
	if not owner_node.is_in_group("network_nodes"):
		return false
	if str(owner_node.get("network_node_type")) != "router":
		return false

	if owner_node.has_method("get_electrical_nodes"):
		var nodes: Variant = owner_node.call("get_electrical_nodes")
		if nodes is Array:
			return (nodes as Array).has(connector_node)

	return false

func would_create_loop(start_node: Node2D, end_node: Node2D) -> bool:
	if start_node == null or end_node == null:
		return false
	return WiringGraph.has_path(start_node, end_node, Callable(self, "_get_electrical_neighbors"))

func _get_electrical_neighbors(current_node) -> Array:
	var neighbors: Array = WiringGraph.neighbors_from_edge_list(current_node, connections, &"start_connector", &"end_connector")
	for sibling in _get_same_owner_connector_neighbors(current_node):
		if sibling != null and not neighbors.has(sibling):
			neighbors.append(sibling)
	return neighbors

func _get_same_owner_connector_neighbors(current_node: Node2D) -> Array:
	var neighbors: Array = []
	if current_node == null:
		return neighbors

	var owner_node: Node = _find_connector_owner(current_node)
	if owner_node == null:
		return neighbors
	if not owner_node.has_method("get_electrical_nodes"):
		return neighbors

	var owner_connectors: Variant = owner_node.call("get_electrical_nodes")
	if not (owner_connectors is Array):
		return neighbors

	for connector in owner_connectors:
		if not (connector is Node2D):
			continue
		if connector == current_node:
			continue
		if not is_instance_valid(connector):
			continue
		neighbors.append(connector)

	return neighbors

func _find_connector_owner(connector_node: Node2D) -> Node:
	if connector_node == null:
		return null

	for node in get_tree().get_nodes_in_group(connectable_group):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("get_electrical_nodes"):
			continue

		var node_connectors: Variant = node.call("get_electrical_nodes")
		if not (node_connectors is Array):
			continue

		for candidate in node_connectors:
			if candidate == connector_node:
				return node

	return null

func update_all_port_label_visibility(should_show: bool) -> void:
	for node in get_tree().get_nodes_in_group(connectable_group):
		var is_router_node: bool = node != null and node.is_in_group("network_nodes") and str(node.get("network_node_type")) == "router"
		if node.has_method("set_port_label_visible"):
			node.call("set_port_label_visible", should_show and not is_router_node)

func update_all_power_states() -> void:
	var powered_connectors: Dictionary = _get_powered_connectors()

	for connectable_owner in get_tree().get_nodes_in_group(connectable_group):
		if connectable_owner == null or not is_instance_valid(connectable_owner):
			continue
		if not connectable_owner.has_method("set_powered_state"):
			continue
		if not connectable_owner.has_method("get_electrical_nodes"):
			continue

		var owner_connectors: Variant = connectable_owner.call("get_electrical_nodes")
		if not (owner_connectors is Array):
			connectable_owner.call("set_powered_state", false)
			continue

		var owner_powered := false
		for connector in owner_connectors:
			if connector != null and powered_connectors.has(connector):
				owner_powered = true
				break

		connectable_owner.call("set_powered_state", owner_powered)

func _get_powered_connectors() -> Dictionary:
	var powered: Dictionary = {}
	var queue: Array = []

	for connectable_owner in get_tree().get_nodes_in_group(connectable_group):
		if connectable_owner == null or not is_instance_valid(connectable_owner):
			continue
		if not connectable_owner.has_method("is_electrical_power_source"):
			continue
		if not bool(connectable_owner.call("is_electrical_power_source")):
			continue
		if not connectable_owner.has_method("get_electrical_nodes"):
			continue

		var source_connectors: Variant = connectable_owner.call("get_electrical_nodes")
		if not (source_connectors is Array):
			continue

		for connector in source_connectors:
			if connector == null:
				continue
			if powered.has(connector):
				continue
			powered[connector] = true
			queue.append(connector)

	while queue.size() > 0:
		var current = queue.pop_front()
		if current == null:
			continue

		for neighbor in _get_electrical_neighbors(current):
			if neighbor == null:
				continue
			if powered.has(neighbor):
				continue
			powered[neighbor] = true
			queue.append(neighbor)

	return powered

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

	draw_highlighted_wires()

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
	var is_highlighted := highlighted_connections.has(connection)
	var connection_glow_color: Color = wire_highlight_glow_color if is_highlighted else connection.get("wire_glow_color", wire_glow_color)
	var connection_wire_color: Color = wire_highlight_color if is_highlighted else connection.get("wire_color", wire_color)
	draw_polyline(wire_points, connection_glow_color, wire_glow_width, true)
	draw_polyline(wire_points, connection_wire_color, wire_width, true)

func draw_drag_preview() -> void:
	var start_connector: Node2D = dragging_connector.get("connector", null)
	if start_connector == null or not is_instance_valid(start_connector):
		return

	var wire_points: PackedVector2Array = build_wire_points_to_position(start_connector, drag_mouse_position)
	if wire_points.size() < 2:
		return
	draw_polyline(wire_points, wire_glow_color, wire_glow_width, true)
	draw_polyline(wire_points, wire_color, wire_width, true)

func draw_highlighted_wires() -> void:
	if highlighted_connections.is_empty():
		return
	# Highlights are rendered through draw_connection color overrides.
	return

func highlight_wire_route(connection: Dictionary) -> void:
	if connection.is_empty():
		return

	selected_connection = connection
	var start_node = connection.get("start_connector", null)
	var end_node = connection.get("end_connector", null)
	if start_node == null or end_node == null:
		highlighted_connections = [connection]
		queue_redraw()
		return

	var route: Array = WiringGraph.collect_anchor_chain_route(
		connection,
		start_node,
		end_node,
		Callable(self, "_is_anchor_node"),
		Callable(self, "_get_connections_for_node"),
		Callable(self, "_get_other_node_from_connection")
	)

	highlighted_connections.clear()
	for route_connection in route:
		if route_connection is Dictionary and connections.has(route_connection):
			highlighted_connections.append(route_connection)

	queue_redraw()

func _is_anchor_node(node) -> bool:
	if node == null:
		return false
	return node is Node2D and (node as Node2D).is_in_group(anchor_group)

func _get_connections_for_node(node) -> Array:
	var node_connections: Array = []
	for connection in connections:
		var start_node: Variant = connection.get("start_connector", null)
		var end_node: Variant = connection.get("end_connector", null)
		if start_node == node or end_node == node:
			node_connections.append(connection)
	return node_connections

func _get_other_node_from_connection(connection, node):
	if not (connection is Dictionary):
		return null
	var start_node: Variant = connection.get("start_connector", null)
	var end_node: Variant = connection.get("end_connector", null)
	if start_node == node:
		return end_node
	if end_node == node:
		return start_node
	return null

func show_delete_wire_confirmation() -> void:
	if selected_connection.is_empty() or wire_delete_confirmation_open:
		return

	wire_delete_confirmation_open = true
	var dialog = ConfirmationDialog.new()
	dialog.title = "Delete Wire"
	dialog.dialog_text = "Are you sure you want to delete this wire?"
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	dialog.size = Vector2(300, 140)

	get_tree().current_scene.add_child(dialog)

	for child in dialog.get_children():
		if child is Label:
			child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	dialog.confirmed.connect(_on_delete_wire_confirmed)
	dialog.canceled.connect(_on_delete_wire_canceled)
	dialog.popup_centered()

func _on_delete_wire_confirmed() -> void:
	if selected_connection.is_empty():
		wire_delete_confirmation_open = false
		return

	if connections.has(selected_connection):
		remove_connection(selected_connection)

	selected_connection.clear()
	highlighted_connections.clear()
	wire_delete_confirmation_open = false
	queue_redraw()

func _on_delete_wire_canceled() -> void:
	wire_delete_confirmation_open = false

func clear_wiring() -> void:
	while not connections.is_empty():
		remove_connection(connections[connections.size() - 1])

	for node in get_tree().get_nodes_in_group(anchor_group):
		if node == null or not is_instance_valid(node):
			continue
		node.queue_free()

	dragging_connector.clear()
	selected_connection.clear()
	highlighted_connections.clear()
	update_all_power_states()
	queue_redraw()

func export_wiring_state() -> Dictionary:
	var anchors: Array = []
	for node in get_tree().get_nodes_in_group(anchor_group):
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		anchors.append({
			"name": node.name,
			"global_position": (node as Node2D).global_position
		})

	var serialized_connections: Array = []
	for connection in connections:
		var start_node: Node2D = connection.get("start_connector", null)
		var end_node: Node2D = connection.get("end_connector", null)
		if start_node == null or end_node == null:
			continue
		if not is_instance_valid(start_node) or not is_instance_valid(end_node):
			continue

		serialized_connections.append({
			"start_path": _node_to_scene_path(start_node),
			"end_path": _node_to_scene_path(end_node),
			"start_world_position": start_node.global_position,
			"end_world_position": end_node.global_position,
			"wire_color": connection.get("wire_color", wire_color),
			"wire_glow_color": connection.get("wire_glow_color", wire_glow_color)
		})

	return {
		"anchors": anchors,
		"connections": serialized_connections
	}

func import_wiring_state(state: Dictionary) -> void:
	clear_wiring()

	if state.is_empty():
		return

	var anchors: Variant = state.get("anchors", [])
	if anchors is Array:
		for anchor_variant in anchors:
			if not (anchor_variant is Dictionary):
				continue
			var anchor_entry := anchor_variant as Dictionary
			var scene = preload("res://scenes/units/cable_anchor.tscn")
			var anchor = scene.instantiate()
			anchor.anchor_group_name = anchor_group
			get_tree().current_scene.add_child(anchor)
			anchor.global_position = _variant_to_vector2(anchor_entry.get("global_position", Vector2.ZERO), Vector2.ZERO)
			var requested_name: String = String(anchor_entry.get("name", ""))
			if not requested_name.is_empty():
				anchor.name = requested_name

	await get_tree().process_frame

	var serialized_connections: Variant = state.get("connections", [])
	if serialized_connections is Array:
		var pending_connections: Array = []
		for connection_variant in serialized_connections:
			if not (connection_variant is Dictionary):
				continue
			var connection_entry := connection_variant as Dictionary
			var start_world_pos: Vector2 = _variant_to_vector2(connection_entry.get("start_world_position", Vector2.ZERO), Vector2.ZERO)
			var end_world_pos: Vector2 = _variant_to_vector2(connection_entry.get("end_world_position", Vector2.ZERO), Vector2.ZERO)
			var start_node := _resolve_saved_connector_node(String(connection_entry.get("start_path", "")), start_world_pos)
			var end_node := _resolve_saved_connector_node(String(connection_entry.get("end_path", "")), end_world_pos)
			if start_node == null or end_node == null:
				pending_connections.append(connection_entry)
				continue

			var saved_wire_color: Color = _variant_to_color(connection_entry.get("wire_color", wire_color), wire_color)
			var saved_wire_glow_color: Color = _variant_to_color(connection_entry.get("wire_glow_color", wire_glow_color), wire_glow_color)
			_append_connection(start_node, end_node, saved_wire_color, saved_wire_glow_color)

		var retries_left := 8
		while not pending_connections.is_empty() and retries_left > 0:
			await get_tree().process_frame
			retries_left -= 1
			var still_pending: Array = []
			for pending_variant in pending_connections:
				if not (pending_variant is Dictionary):
					continue
				var pending_entry := pending_variant as Dictionary
				var pending_start_world: Vector2 = _variant_to_vector2(pending_entry.get("start_world_position", Vector2.ZERO), Vector2.ZERO)
				var pending_end_world: Vector2 = _variant_to_vector2(pending_entry.get("end_world_position", Vector2.ZERO), Vector2.ZERO)
				var pending_start := _resolve_saved_connector_node(String(pending_entry.get("start_path", "")), pending_start_world)
				var pending_end := _resolve_saved_connector_node(String(pending_entry.get("end_path", "")), pending_end_world)
				if pending_start == null or pending_end == null:
					still_pending.append(pending_entry)
					continue

				var pending_wire_color: Color = _variant_to_color(pending_entry.get("wire_color", wire_color), wire_color)
				var pending_wire_glow_color: Color = _variant_to_color(pending_entry.get("wire_glow_color", wire_glow_color), wire_glow_color)
				_append_connection(pending_start, pending_end, pending_wire_color, pending_wire_glow_color)

			pending_connections = still_pending

	update_all_power_states()
	queue_redraw()

func _append_connection(start_node: Node2D, end_node: Node2D, saved_wire_color: Color, saved_wire_glow_color: Color) -> void:
	if start_node == null or end_node == null:
		return
	if connection_exists(start_node, end_node):
		return

	var start_owner: Node = _find_connector_owner(start_node)
	var end_owner: Node = _find_connector_owner(end_node)
	connections.append({
		"start_connector": start_node,
		"end_connector": end_node,
		"wire_color": saved_wire_color,
		"wire_glow_color": saved_wire_glow_color
	})

	if start_owner != null:
		if start_owner.has_method("add_electrical_connection"):
			start_owner.add_electrical_connection(end_node)
		elif start_owner.has_method("add_connection") and not start_owner.is_in_group("network_nodes"):
			start_owner.add_connection(end_node)

	if end_owner != null:
		if end_owner.has_method("add_electrical_connection"):
			end_owner.add_electrical_connection(start_node)
		elif end_owner.has_method("add_connection") and not end_owner.is_in_group("network_nodes"):
			end_owner.add_connection(start_node)

func _node_to_scene_path(node: Node) -> String:
	if node == null:
		return ""
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return str(scene.get_path_to(node))

func _node_from_scene_path(path_text: String):
	if path_text.is_empty():
		return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(NodePath(path_text))

func _resolve_saved_connector_node(path_text: String, fallback_world_pos: Vector2) -> Node2D:
	var from_path := _node_from_scene_path(path_text) as Node2D
	if from_path != null:
		return from_path
	if fallback_world_pos == Vector2.ZERO:
		return null
	return _find_nearest_connector_node(fallback_world_pos, connector_snap_distance * 1.6)

func _find_nearest_connector_node(world_position: Vector2, max_distance: float) -> Node2D:
	refresh_connectors()
	var best_node: Node2D = null
	var best_distance := max_distance
	for connector_entry in connectors:
		if not (connector_entry is Dictionary):
			continue
		var connector_node: Node2D = (connector_entry as Dictionary).get("connector", null)
		if connector_node == null or not is_instance_valid(connector_node):
			continue
		var distance := connector_node.global_position.distance_to(world_position)
		if distance > best_distance:
			continue
		best_distance = distance
		best_node = connector_node
	return best_node

func _variant_to_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts := text.split(",")
		if parts.size() == 2:
			return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	if value is Array:
		var arr := value as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	if value is Dictionary:
		var dict := value as Dictionary
		if dict.has("x") and dict.has("y"):
			return Vector2(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)))
	return fallback

func _variant_to_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
			var parts := text.split(",")
			if parts.size() == 3:
				return Color(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()), 1.0)
			if parts.size() == 4:
				return Color(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()), float(parts[3].strip_edges()))
		if text.begins_with("#"):
			return Color(text)
	if value is Array:
		var arr := value as Array
		if arr.size() == 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
		if arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	if value is Dictionary:
		var dict := value as Dictionary
		if dict.has("r") and dict.has("g") and dict.has("b"):
			return Color(float(dict.get("r", 0.0)), float(dict.get("g", 0.0)), float(dict.get("b", 0.0)), float(dict.get("a", 1.0)))
	return fallback

func build_wire_points(start_connector: Node2D, end_connector: Node2D) -> PackedVector2Array:
	var start_position: Vector2 = world_to_screen(start_connector.global_position)
	var end_position: Vector2 = world_to_screen(end_connector.global_position)
	return build_orthogonal_path(start_position, end_position)

func build_wire_points_to_position(start_connector: Node2D, screen_target: Vector2) -> PackedVector2Array:
	var start_position: Vector2 = world_to_screen(start_connector.global_position)
	return build_orthogonal_path(start_position, screen_target)

func build_orthogonal_path(start_point: Vector2, end_point: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.append(start_point)

	var dx: float = abs(end_point.x - start_point.x)
	var dy: float = abs(end_point.y - start_point.y)
	if dx >= dy:
		append_unique_point(points, Vector2(end_point.x, start_point.y))
	else:
		append_unique_point(points, Vector2(start_point.x, end_point.y))

	append_unique_point(points, end_point)
	return points

func append_unique_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty():
		points.append(point)
		return
	if points[points.size() - 1].distance_to(point) <= 0.01:
		return
	points.append(point)

func draw_connector(connector: Dictionary) -> void:
	var connector_node: Node2D = connector.get("connector", null)
	if connector_node == null or not is_instance_valid(connector_node):
		return

	var connector_owner: Node = connector.get("owner", null)
	var connector_position: Vector2 = connector.get("screen_position", Vector2.ZERO)
	var is_dragging_start: bool = not dragging_connector.is_empty() and dragging_connector.get("connector", null) == connector_node
	var fill_color: Color = connector_active_fill_color if is_dragging_start else connector_fill_color
	var outline_color: Color = connector_active_outline_color if is_dragging_start else connector_outline_color
	var icon_text := _get_electrical_connector_icon(connector_owner, connector_node)

	draw_circle(connector_position, connector_radius + 2.5, outline_color)
	draw_circle(connector_position, connector_radius, fill_color)
	_draw_connector_icon(connector_position, icon_text)

func _is_anchor_too_close_to_connector(mouse_position: Vector2) -> bool:
	refresh_connectors()
	for connector in connectors:
		var connector_position: Vector2 = connector.get("screen_position", Vector2.ZERO)
		if connector_position.distance_to(mouse_position) < anchor_min_distance_from_nodes:
			return true
	return false

func _get_electrical_connector_icon(owner_node: Node, connector_node: Node2D) -> String:
	if connector_node != null and connector_node.is_in_group(anchor_group):
		return ""

	if owner_node != null and owner_node.has_method("get_electrical_port_icon"):
		return str(owner_node.call("get_electrical_port_icon", connector_node))

	return "⚡"

func _draw_connector_icon(screen_position: Vector2, icon_text: String) -> void:
	if icon_text == "":
		return

	var icon_font: Font = ThemeDB.fallback_font
	if icon_font == null:
		return

	var icon_size_px: int = max(connector_icon_size, 8)
	var text_size: Vector2 = icon_font.get_string_size(icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size_px)
	var baseline_offset: float = text_size.y * 0.35
	var draw_position := Vector2(screen_position.x - (text_size.x * 0.5), screen_position.y + baseline_offset)
	draw_string(icon_font, draw_position, icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size_px, connector_icon_color)

func show_overlay_title(title: String) -> void:
	if overlay_title_label == null:
		overlay_title_label = Label.new()
		overlay_title_label.name = "OverlayTitle"
		overlay_title_label.z_index = 100
		overlay_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay_title_label.add_theme_font_size_override("font_size", 24)
		overlay_title_label.add_to_group("overlay_titles")
		get_tree().current_scene.add_child(overlay_title_label)

	for title_node in get_tree().get_nodes_in_group("overlay_titles"):
		if title_node is Label and title_node != overlay_title_label:
			(title_node as Label).visible = false
	
	overlay_title_label.text = title
	overlay_title_label.position = Vector2(get_viewport_rect().get_center().x - 60, 20)
	overlay_title_label.visible = true

func hide_overlay_title() -> void:
	if overlay_title_label != null and is_instance_valid(overlay_title_label):
		overlay_title_label.visible = false

func _show_overlay_status(message: String) -> void:
	if overlay_status_label == null:
		overlay_status_label = Label.new()
		overlay_status_label.name = "OverlayStatus"
		overlay_status_label.z_index = 101
		overlay_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay_status_label.add_theme_font_size_override("font_size", 18)
		overlay_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
		get_tree().current_scene.add_child(overlay_status_label)

	overlay_status_label.text = message
	overlay_status_label.position = Vector2(get_viewport_rect().get_center().x - 180.0, 56.0)
	overlay_status_label.visible = true
	overlay_status_hide_at_ms = Time.get_ticks_msec() + int(status_message_duration * 1000.0)

func _update_overlay_status_visibility() -> void:
	if overlay_status_label == null:
		return
	if overlay_status_hide_at_ms <= 0:
		return
	if Time.get_ticks_msec() >= overlay_status_hide_at_ms:
		overlay_status_label.visible = false
		overlay_status_hide_at_ms = 0

func set_selected_cable_type(cable_data) -> void:
	if cable_data is Dictionary:
		selected_cable_type = (cable_data as Dictionary).duplicate(true)
	else:
		selected_cable_type = default_power_cable.duplicate(true)
	queue_redraw()

func _ensure_default_cable_type() -> void:
	if not selected_cable_type.is_empty():
		return

	if buy_menu != null and buy_menu.has_method("get_cable_item_by_name"):
		var cable_from_menu: Variant = buy_menu.call("get_cable_item_by_name", "Power Cable")
		if cable_from_menu is Dictionary and not (cable_from_menu as Dictionary).is_empty():
			selected_cable_type = (cable_from_menu as Dictionary).duplicate(true)
			return

	selected_cable_type = default_power_cable.duplicate(true)

func _sync_buy_menu_cable_selection() -> void:
	if buy_menu == null:
		return
	if not buy_menu.has_method("set_selected_cable_by_name"):
		return
	if selected_cable_type.is_empty():
		return

	buy_menu.call("set_selected_cable_by_name", str(selected_cable_type.get("name", "")))

func _get_selected_wire_color() -> Color:
	if selected_cable_type.is_empty():
		return wire_color
	return selected_cable_type.get("color", wire_color)

func _get_selected_wire_glow_color() -> Color:
	var base_color: Color = _get_selected_wire_color()
	return Color(base_color.r * 0.55, base_color.g * 0.55, base_color.b * 0.55, wire_glow_color.a)
