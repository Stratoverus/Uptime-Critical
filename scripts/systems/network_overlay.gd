extends Control

const WiringGraph = preload("res://scripts/systems/wiring/wiring_graph.gd")

signal cable_mode_changed(is_enabled)

@onready var radial_menu = get_tree().current_scene.get_node_or_null("UI/RadialMenu")
@onready var buy_menu = get_tree().current_scene.get_node_or_null("BuyMenu")
@onready var placed_units = get_tree().current_scene.get_node_or_null("PlacedUnits")
@onready var placement_preview = get_tree().current_scene.get_node_or_null("PlacementPreview")

@export var overlay_fade_duration: float = 0.16
@export var wire_width: float = 5.0
@export var wire_glow_width: float = 11.0
@export var wire_color: Color = Color(0.24, 0.24, 0.24, 0.96)
@export var wire_glow_color: Color = Color(0.10, 0.10, 0.10, 0.22)
@export var overlay_tint: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var node_radius: float = 6.0
@export var node_fill_color: Color = Color(0.86, 0.90, 0.96, 1.0)
@export var node_outline_color: Color = Color(0.10, 0.12, 0.16, 1.0)
@export var node_active_fill_color: Color = Color(1.0, 0.88, 0.40, 1.0)
@export var node_active_outline_color: Color = Color(0.20, 0.14, 0.02, 0.95)
@export var node_empty_fill_color: Color = Color(0.45, 0.45, 0.45, 1.0)
@export var node_empty_outline_color: Color = Color(0.20, 0.20, 0.20, 0.95)
@export var node_connected_fill_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var node_connected_outline_color: Color = Color(0.70, 0.70, 0.70, 0.95)
@export var node_unaffordable_fill_color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var node_unaffordable_outline_color: Color = Color(0.55, 0.10, 0.10, 1.0)
@export var node_snap_distance: float = 14.0
@export var anchor_min_distance_from_nodes: float = 20.0
@export var wire_highlight_color: Color = Color(1.0, 0.88, 0.40, 1.0)
@export var wire_highlight_glow_color: Color = Color(1.0, 0.70, 0.10, 0.40)
@export var preview_affordable_color: Color = Color(0.80, 1.0, 0.85, 1.0)
@export var preview_unaffordable_color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var node_icon_color: Color = Color(0.10, 0.10, 0.10, 0.95)
@export var node_icon_size: int = 14

var selected_cable_type = null
var manual_selected_cable_type: Dictionary = {}
var uplink_auto_switched: bool = false
var pre_uplink_cable_type: Dictionary = {}
var cable_start_point = null
var cable_start_world_position: Vector2 = Vector2.ZERO
var cable_placement_active := false
var last_cable_click_time := 0
var placed_cable_segments: Array = []
var cable_preview_line: Line2D = null
var cable_preview_label: Label = null
var overlay_status_label: Label = null
var overlay_status_hide_at_ms: int = 0
var overlay_fade_tween: Tween = null
var selected_wire: Line2D = null
var highlighted_wire_segments: Array = []
var wire_delete_confirmation_open := false
var overlay_title_label: Label = null
var default_cable_type := {
	"name": "Cat5",
	"color": Color(0.45, 0.45, 0.45, 1.0),
	"cost": 1
}
const INTERNET_PIPE_NAME: String = "Internet Pipe (Uplink)"

func _ready() -> void:
	add_to_group("network_overlay")
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)

func _process(_delta: float) -> void:
	if not visible:
		return

	queue_redraw()
	update_cable_preview()
	_update_overlay_status_visibility()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_network_overlay"):
		toggle_overlay()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		_handle_cable_mode_input(event)
		accept_event()

func toggle_overlay() -> void:
	set_overlay_visible(not visible)

func set_overlay_visible(overlay_visible: bool, instant_transition: bool = false) -> void:
	var should_use_instant_transition: bool = instant_transition
	if overlay_visible:
		if not should_use_instant_transition:
			should_use_instant_transition = _is_any_other_overlay_active()
		_deactivate_other_overlays()

	if overlay_fade_tween != null and overlay_fade_tween.is_valid():
		overlay_fade_tween.kill()
	overlay_fade_tween = null

	if overlay_visible:
		visible = true
		if should_use_instant_transition or overlay_fade_duration <= 0.0:
			modulate.a = 1.0
		else:
			modulate.a = 0.0
			overlay_fade_tween = create_tween()
			overlay_fade_tween.tween_property(self, "modulate:a", 1.0, overlay_fade_duration)
	else:
		if should_use_instant_transition or overlay_fade_duration <= 0.0:
			modulate.a = 0.0
			visible = false
			update_cable_visibility()
		else:
			overlay_fade_tween = create_tween()
			overlay_fade_tween.tween_property(self, "modulate:a", 0.0, overlay_fade_duration)
			overlay_fade_tween.finished.connect(_on_overlay_fade_out_finished)

	if overlay_visible:
		_ensure_default_cable_type()
		cable_placement_active = selected_cable_type != null
		_sync_buy_menu_cable_selection()
		show_overlay_title("Network Overlay")
		update_all_port_label_visibility(true)
	else:
		selected_cable_type = null
		cable_start_point = null
		cable_start_world_position = Vector2.ZERO
		cable_placement_active = false
		selected_wire = null
		highlighted_wire_segments.clear()
		clear_cable_preview()
		hide_overlay_title()
		update_all_port_label_visibility(false)

	if radial_menu and radial_menu.visible and not overlay_visible:
		radial_menu.hide()

	if overlay_visible:
		update_cable_visibility()
	update_all_network_node_highlights()
	cable_mode_changed.emit(overlay_visible)

func _is_any_other_overlay_active() -> bool:
	for electrical_overlay in get_tree().get_nodes_in_group("electrical_overlay"):
		if electrical_overlay != null and electrical_overlay != self and bool(electrical_overlay.get("visible")):
			return true

	for thermal_system in get_tree().get_nodes_in_group("thermal_system"):
		if thermal_system != null and bool(thermal_system.get("heat_view_enabled")):
			return true

	return false

func _deactivate_other_overlays() -> void:
	for electrical_overlay in get_tree().get_nodes_in_group("electrical_overlay"):
		if electrical_overlay != null and electrical_overlay != self and electrical_overlay.has_method("set_overlay_visible"):
			electrical_overlay.call("set_overlay_visible", false)

	for thermal_system in get_tree().get_nodes_in_group("thermal_system"):
		if thermal_system != null and thermal_system.has_method("set_heat_view_enabled"):
			thermal_system.call("set_heat_view_enabled", false)

func _on_overlay_fade_out_finished() -> void:
	visible = false
	update_cable_visibility()

func set_selected_cable_type(unit_data) -> void:
	if unit_data is Dictionary:
		selected_cable_type = (unit_data as Dictionary).duplicate(true)
		manual_selected_cable_type = (unit_data as Dictionary).duplicate(true)
	else:
		selected_cable_type = unit_data
		manual_selected_cable_type = {}
	uplink_auto_switched = false
	pre_uplink_cable_type.clear()
	cable_start_point = null
	cable_start_world_position = Vector2.ZERO
	cable_placement_active = visible and selected_cable_type != null
	clear_placement_preview()
	clear_cable_preview()
	_sync_buy_menu_cable_selection()

func _ensure_default_cable_type() -> void:
	if selected_cable_type != null:
		return

	selected_cable_type = _get_preferred_cable_type()
	if selected_cable_type is Dictionary:
		manual_selected_cable_type = (selected_cable_type as Dictionary).duplicate(true)

func _get_preferred_cable_type() -> Dictionary:
	if buy_menu != null and buy_menu.has_method("get_cable_item_by_name"):
		var most_used_name = _get_most_used_cable_type_name()
		var cable_from_menu: Variant = buy_menu.call("get_cable_item_by_name", most_used_name)
		if cable_from_menu is Dictionary and not (cable_from_menu as Dictionary).is_empty():
			return (cable_from_menu as Dictionary).duplicate(true)

	return default_cable_type.duplicate(true)

func _get_most_used_cable_type_name() -> String:
	var counts := {
		"Cat5": 0,
		"Cat6": 0,
		"Fiber": 0,
		INTERNET_PIPE_NAME: 0
	}

	for cable in get_tree().get_nodes_in_group("cable_segments"):
		if cable == null:
			continue
		var type_name = str(cable.get("cable_type_name"))
		if counts.has(type_name):
			counts[type_name] += 1

	var best_name := "Cat5"
	var best_count := -1
	for cable_name in ["Cat5", "Cat6", "Fiber", INTERNET_PIPE_NAME]:
		var count: int = int(counts.get(cable_name, 0))
		if count > best_count:
			best_count = count
			best_name = cable_name

	return best_name

func _sync_buy_menu_cable_selection() -> void:
	if buy_menu == null:
		return
	if not buy_menu.has_method("set_selected_cable_by_name"):
		return
	if selected_cable_type == null:
		return

	buy_menu.call("set_selected_cable_by_name", str(selected_cable_type.get("name", "")))

func clear_placement_preview() -> void:
	return

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), overlay_tint, true)
	draw_network_nodes()
	draw_highlighted_wires()

func _handle_cable_mode_input(event: InputEvent) -> void:
	_ensure_default_cable_type()
	cable_placement_active = selected_cable_type != null

	if not cable_placement_active:
		return

	if event is InputEventMouseButton and event.pressed:
		var now = Time.get_ticks_msec()
		if now - last_cable_click_time < 120:
			return
		last_cable_click_time = now

		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_screen_pos = get_viewport().get_mouse_position()
			var mouse_world_pos = screen_to_world(mouse_screen_pos)
			var clicked_node: Dictionary = get_clicked_network_node(mouse_world_pos, mouse_screen_pos)

			if not clicked_node.is_empty():
				selected_wire = null
				highlighted_wire_segments.clear()
				_handle_cable_node_click(clicked_node)
			else:
				# Only allow wire selection when not actively placing a wire,
				# and only after confirming no node was clicked.
				if cable_start_point == null:
					var clicked_wire = find_wire_at_position(mouse_world_pos)
					if clicked_wire != null:
						highlight_wire_route(clicked_wire)
						return

				selected_wire = null
				highlighted_wire_segments.clear()
				_handle_cable_empty_click(mouse_world_pos)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_wire != null:
				show_delete_wire_confirmation()
				return
			
			cable_start_point = null
			cable_start_world_position = Vector2.ZERO
			cable_placement_active = selected_cable_type != null
			clear_cable_preview()

func get_clicked_network_node(mouse_world_position: Vector2, mouse_screen_position: Vector2 = Vector2.ZERO) -> Dictionary:
	var snapped_result: Dictionary = get_snapped_network_node(mouse_world_position, mouse_screen_position)
	return snapped_result

func get_snapped_network_node(world_mouse_position: Vector2, screen_mouse_position: Vector2 = Vector2.ZERO) -> Dictionary:
	var best_result: Dictionary = {}
	var best_distance: float = node_snap_distance
	if screen_mouse_position == Vector2.ZERO:
		screen_mouse_position = world_to_screen(world_mouse_position)

	for marker in get_network_markers():
		var marker_position: Vector2 = marker.get("screen_position", Vector2.ZERO)
		var marker_owner: Node = marker.get("network_node", null) as Node
		var marker_connector: Node2D = marker.get("connector_node", null) as Node2D
		if marker_owner == null or marker_connector == null:
			continue

		var distance: float = marker_position.distance_to(screen_mouse_position)
		if distance <= best_distance:
			best_distance = distance
			best_result = {
				"node": marker_owner,
				"owner": marker_owner,
				"connector": marker_connector,
				"world_position": marker.get("world_position", Vector2.ZERO)
			}

	return best_result

func screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position

func _handle_cable_node_click(click_result: Dictionary) -> void:
	var node: Node = click_result.get("owner", click_result.get("node", null)) as Node
	var connector_node: Node2D = click_result.get("connector", null)
	var world_position: Vector2 = click_result.get("world_position", Vector2.ZERO)
	if node == null or connector_node == null:
		return

	_sync_selection_for_clicked_connector(node, connector_node)

	var clicked_port_type: String = _get_network_port_type_for_connector(node, connector_node)
	if cable_start_point == null and _is_selected_internet_pipe() and not _is_uplink_port_type(clicked_port_type):
		_show_overlay_status("Internet Pipe is only for breaker internet to router internet.")
		return

	if cable_start_point == null:
		if not can_accept_new_connection(node, world_position, null, Vector2.ZERO):
			return
		cable_start_point = node
		cable_start_world_position = world_position
		return

	if node == cable_start_point:
		return

	var success: bool = create_cable_segment(cable_start_point, node, cable_start_world_position, world_position)
	if success:
		if node.get("network_node_type") == "anchor":
			cable_start_point = node
			cable_start_world_position = world_position
		else:
			cable_start_point = null
			cable_start_world_position = Vector2.ZERO

func _handle_cable_empty_click(mouse_position: Vector2) -> void:
	if cable_start_point == null:
		return

	if cable_start_world_position.distance_to(mouse_position) < 20.0:
		return

	if _is_anchor_too_close_to_network_node(mouse_position):
		_show_overlay_status("Cannot place anchor that close to a node.")
		return

	# Prevent attaching anchors onto existing wire geometry.
	if find_wire_at_position(mouse_position) != null:
		return

	var anchor: Node2D = create_cable_anchor(mouse_position)
	var success: bool = create_cable_segment(cable_start_point, anchor, cable_start_world_position, anchor.global_position)

	if success:
		cable_start_point = anchor
		cable_start_world_position = anchor.global_position
	else:
		anchor.queue_free()

func find_network_node_from_collider(node):
	var current = node

	while current != null:
		if current.is_in_group("network_nodes"):
			return current
		current = current.get_parent()

	return null

func create_cable_anchor(anchor_position: Vector2) -> Node2D:
	var scene: PackedScene = preload("res://scenes/units/cable_anchor.tscn")
	var anchor: Node2D = scene.instantiate() as Node2D

	get_tree().current_scene.add_child(anchor)
	anchor.global_position = anchor_position
	anchor.name = "CableAnchor_%d" % Time.get_ticks_msec()
	anchor.object_name = "Cable Anchor"

	update_all_network_node_highlights()

	return anchor

func create_cable_segment(start_node, end_node, start_world_position: Vector2, end_world_position: Vector2) -> bool:
	if selected_cable_type == null:
		_show_overlay_status("Select a cable type first.")
		return false

	var cable_name: String = str(selected_cable_type.get("name", ""))
	var internet_uplink: bool = _is_internet_uplink_connection(start_node, start_world_position, end_node, end_world_position)
	if internet_uplink and cable_name != INTERNET_PIPE_NAME:
		_show_overlay_status("Internet uplink requires Internet Pipe.")
		return false
	if not internet_uplink and cable_name == INTERNET_PIPE_NAME:
		_show_overlay_status("Internet Pipe only connects wall internet to router internet.")
		return false

	if would_create_loop(start_node, end_node):
		_show_overlay_status("Cannot place cable: this creates a loop.")
		return false

	if not can_accept_new_connection(start_node, start_world_position, end_node, end_world_position):
		_show_overlay_status("Cannot place cable: start node has no free ports.")
		return false

	if not can_accept_new_connection(end_node, end_world_position, start_node, start_world_position):
		_show_overlay_status("Cannot place cable: end node has no free ports.")
		return false

	var scene = preload("res://scenes/units/cable_segment.tscn")
	var segment = scene.instantiate()

	get_tree().current_scene.add_child(segment)
	segment.setup(start_node, end_node, selected_cable_type, start_world_position, end_world_position)

	if segment.length < 5.0:
		_show_overlay_status("Cable segment is too short.")
		segment.queue_free()
		return false

	if GameManager == null:
		push_error("GameManager not found")
		segment.queue_free()
		return false

	if GameManager.can_afford(segment.total_cost):
		GameManager.spend_money(segment.total_cost)
	else:
		_show_overlay_status("Can't afford %s ($%d)" % [str(selected_cable_type.get("name", "Cable")), int(segment.total_cost)])
		segment.queue_free()
		return false

	placed_cable_segments.append(segment)
	if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
		SaveManager.mark_runtime_dirty()

	var start_connector := _get_owner_connector_for_world_position(start_node, start_world_position)
	var end_connector := _get_owner_connector_for_world_position(end_node, end_world_position)

	if start_node.has_method("add_connection_for_node"):
		start_node.add_connection_for_node(segment, start_connector)
	elif start_node.has_method("add_connection"):
		start_node.add_connection(segment)

	if end_node.has_method("add_connection_for_node"):
		end_node.add_connection_for_node(segment, end_connector)
	elif end_node.has_method("add_connection"):
		end_node.add_connection(segment)

	if start_node.get("network_node_type") == "router":
		print(
			get_network_point_name(start_node),
			" ports used: ",
			start_node.connected_segments.size(),
			"/",
			start_node.get_port_limit()
		)

	if end_node.get("network_node_type") == "router":
		print(get_network_point_name(end_node), " ports used: ", end_node.connected_segments.size(), "/", end_node.get_port_limit())

	update_all_server_network_status()
	return true

func update_cable_visibility() -> void:
	for cable in get_tree().get_nodes_in_group("cable_segments"):
		cable.visible = visible

func ensure_cable_preview_exists() -> void:
	if cable_preview_line == null:
		cable_preview_line = Line2D.new()
		cable_preview_line.width = wire_width
		cable_preview_line.z_as_relative = false
		cable_preview_line.z_index = 140
		cable_preview_line.visible = false
		get_tree().current_scene.add_child(cable_preview_line)

	if cable_preview_label == null:
		cable_preview_label = Label.new()
		cable_preview_label.visible = false
		cable_preview_label.z_as_relative = false
		cable_preview_label.z_index = 141
		get_tree().current_scene.add_child(cable_preview_label)

	if overlay_status_label == null:
		overlay_status_label = Label.new()
		overlay_status_label.visible = false
		overlay_status_label.z_as_relative = false
		overlay_status_label.z_index = 142
		overlay_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay_status_label.add_theme_font_size_override("font_size", 18)
		get_tree().current_scene.add_child(overlay_status_label)

func draw_network_nodes() -> void:
	var preview_unaffordable := _is_current_preview_unaffordable()
	for marker in get_network_markers():
		var marker_position: Vector2 = marker.get("screen_position", Vector2.ZERO)
		var marker_world_pos: Vector2 = marker.get("world_position", Vector2.ZERO)
		var network_node: Node = marker.get("network_node", null) as Node
		var connector_node: Node2D = marker.get("connector_node", null)
		var icon_text: String = _get_network_port_icon(network_node, connector_node)
		
		var is_active: bool = cable_start_world_position.distance_to(marker_world_pos) <= 1.0
		var endpoint_state: int = get_endpoint_state(network_node, marker_world_pos)
		var is_server_node: bool = network_node != null and str(network_node.get("network_node_type")) == "server"
		var show_unaffordable: bool = preview_unaffordable and is_server_node and not is_active
		
		draw_network_node_marker(marker_position, icon_text, is_active, endpoint_state, show_unaffordable)

func draw_network_node_marker(screen_position: Vector2, icon_text: String = "", is_active: bool = false, endpoint_state: int = 0, is_unaffordable: bool = false) -> void:
	var fill_color: Color
	var outline_color: Color
	
	if is_active:
		fill_color = node_active_fill_color
		outline_color = node_active_outline_color
	elif is_unaffordable:
		fill_color = node_unaffordable_fill_color
		outline_color = node_unaffordable_outline_color
	elif endpoint_state == 1:  # connected
		fill_color = node_connected_fill_color
		outline_color = node_connected_outline_color
	else:  # empty (0)
		fill_color = node_empty_fill_color
		outline_color = node_empty_outline_color
	
	draw_circle(screen_position, node_radius + 2.0, outline_color)
	draw_circle(screen_position, node_radius, fill_color)
	_draw_network_node_icon(screen_position, icon_text)

func draw_highlighted_wires() -> void:
	if highlighted_wire_segments.is_empty():
		return
	
	for segment in highlighted_wire_segments:
		if segment == null or not is_instance_valid(segment):
			continue
		if not segment is Line2D:
			continue
		
		# Draw glow first
		draw_set_transform(segment.global_position, segment.rotation, segment.scale)
		var glow_width = wire_glow_width + 4.0
		for point in range(segment.points.size() - 1):
			draw_line(segment.points[point], segment.points[point + 1], wire_highlight_glow_color, glow_width)
		
		# Draw main highlight line
		for point in range(segment.points.size() - 1):
			draw_line(segment.points[point], segment.points[point + 1], wire_highlight_color, wire_width + 2.0)
		
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_network_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []

	for node in get_tree().get_nodes_in_group("network_nodes"):
		if not is_instance_valid(node):
			continue

		if node.has_method("get_network_nodes"):
			var endpoints: Variant = node.call("get_network_nodes")
			if endpoints is Array:
				for endpoint in endpoints:
					if endpoint is Node2D and is_instance_valid(endpoint):
						markers.append({
							"screen_position": world_to_screen((endpoint as Node2D).global_position),
							"world_position": (endpoint as Node2D).global_position,
							"network_node": node,
							"connector_node": endpoint
						})
			continue

		if node.has_method("get_electrical_nodes"):
			var fallback_endpoints: Variant = node.call("get_electrical_nodes")
			if fallback_endpoints is Array:
				for endpoint in fallback_endpoints:
					if endpoint is Node2D and is_instance_valid(endpoint):
						markers.append({
							"screen_position": world_to_screen((endpoint as Node2D).global_position),
							"world_position": (endpoint as Node2D).global_position,
							"network_node": node,
							"connector_node": endpoint
						})
			continue

		if node is Node2D:
			markers.append({
				"screen_position": world_to_screen((node as Node2D).global_position),
				"world_position": (node as Node2D).global_position,
				"network_node": node,
				"connector_node": node
			})

	return markers

func world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position

func clear_cable_preview() -> void:
	if cable_preview_line:
		cable_preview_line.visible = false
		cable_preview_line.clear_points()

	if cable_preview_label:
		cable_preview_label.visible = false
		cable_preview_label.text = ""

func update_cable_preview() -> void:
	if not visible:
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

	var start_pos = cable_start_world_position
	var end_pos = screen_to_world(get_viewport().get_mouse_position())
	var preview_points = build_orthogonal_preview_points(start_pos, end_pos)

	cable_preview_line.clear_points()
	for p in preview_points:
		cable_preview_line.add_point(p)
	cable_preview_line.default_color = selected_cable_type.get("color", wire_color)
	cable_preview_line.visible = true

	var preview_length = calculate_polyline_length(preview_points)
	var preview_cost = preview_length * selected_cable_type.get("cost", 0)
	var can_afford_preview := GameManager != null and GameManager.can_afford(preview_cost)

	cable_preview_line.default_color = selected_cable_type.get("color", wire_color) if can_afford_preview else preview_unaffordable_color
	cable_preview_label.text = "$%d" % int(preview_cost)
	if not can_afford_preview:
		cable_preview_label.text += "  (Can't afford)"
	cable_preview_label.add_theme_color_override("font_color", preview_affordable_color if can_afford_preview else preview_unaffordable_color)
	cable_preview_label.position = (start_pos + end_pos) * 0.5
	cable_preview_label.visible = true

func _is_current_preview_unaffordable() -> bool:
	if not visible:
		return false
	if not cable_placement_active:
		return false
	if cable_start_point == null:
		return false
	if selected_cable_type == null:
		return false
	if GameManager == null:
		return false

	var start_pos = cable_start_world_position
	var end_pos = screen_to_world(get_viewport().get_mouse_position())
	var preview_points = build_orthogonal_preview_points(start_pos, end_pos)
	var preview_length = calculate_polyline_length(preview_points)
	var preview_cost = preview_length * selected_cable_type.get("cost", 0)
	return not GameManager.can_afford(preview_cost)

func _show_overlay_status(message: String, duration_ms: int = 1300) -> void:
	ensure_cable_preview_exists()
	if overlay_status_label == null:
		return
	overlay_status_label.text = message
	overlay_status_label.add_theme_color_override("font_color", preview_unaffordable_color)
	overlay_status_label.position = Vector2(get_viewport_rect().get_center().x - 140.0, 56.0)
	overlay_status_label.visible = true
	overlay_status_hide_at_ms = Time.get_ticks_msec() + duration_ms

func _update_overlay_status_visibility() -> void:
	if overlay_status_label == null:
		return
	if overlay_status_hide_at_ms <= 0:
		return
	if Time.get_ticks_msec() >= overlay_status_hide_at_ms:
		overlay_status_label.visible = false
		overlay_status_hide_at_ms = 0

func build_orthogonal_preview_points(start_pos: Vector2, end_pos: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(start_pos)

	var dx = abs(end_pos.x - start_pos.x)
	var dy = abs(end_pos.y - start_pos.y)
	if dx >= dy:
		append_unique_preview_point(points, Vector2(end_pos.x, start_pos.y))
	else:
		append_unique_preview_point(points, Vector2(start_pos.x, end_pos.y))

	append_unique_preview_point(points, end_pos)
	return points

func append_unique_preview_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty():
		points.append(point)
		return
	if points[points.size() - 1].distance_to(point) <= 0.01:
		return
	points.append(point)

func calculate_polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

func get_network_point_name(node) -> String:
	if node == null:
		return "Unknown"

	var object_name_value: Variant = node.get("object_name")
	if object_name_value != null and str(object_name_value) != "":
		return str(object_name_value)

	return str(node.name)

func can_reach_router(start_node) -> bool:
	if start_node == null:
		return false

	var visited: Dictionary = {}
	var queue: Array = [start_node]

	while queue.size() > 0:
		var current: Variant = queue.pop_front()

		if current == null:
			continue

		if visited.has(current):
			continue

		visited[current] = true

		var node_type: Variant = current.get("network_node_type")
		if node_type == "internet_source":
			return true

		var segments: Variant = current.get("connected_segments")
		if segments == null:
			continue

		for segment in segments:
			if segment == null:
				continue
			if not segment.has_method("get_other_point"):
				continue

			var next_point: Variant = segment.get_other_point(current)
			if next_point != null and not visited.has(next_point):
				queue.append(next_point)

	return false

func update_all_server_network_status() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.get("network_node_type") == "server":
			var connected = can_reach_router(node)
			node.update_network_status(connected)

func can_accept_new_connection(node: Node, endpoint_world_position: Vector2 = Vector2.ZERO, remote_node: Node = null, remote_world_position: Vector2 = Vector2.ZERO) -> bool:
	if node == null:
		return false

	var connector_node := _get_owner_connector_for_world_position(node, endpoint_world_position)
	var remote_connector: Node2D = null
	if remote_node != null:
		remote_connector = _get_owner_connector_for_world_position(remote_node, remote_world_position)

	var endpoint_connection_count: int = _get_endpoint_connection_count(node, endpoint_world_position)
	if node.has_method("can_accept_network_connection"):
		return bool(node.call("can_accept_network_connection", connector_node, remote_node, remote_connector, endpoint_connection_count))

	var node_type: Variant = node.get("network_node_type")

	if node_type == "router":
		if node.has_method("has_free_port"):
			return node.has_free_port()
		return false

	if node_type == "internet_source":
		return endpoint_connection_count < 1

	if node_type == "anchor":
		var anchor_segments: Variant = node.get("connected_segments")
		if anchor_segments is Array:
			return anchor_segments.size() < 2
		return true

	if node_type == "server":
		if endpoint_world_position == Vector2.ZERO:
			return true

		var server_segments: Variant = node.get("connected_segments")
		if not (server_segments is Array):
			return true

		for segment in server_segments:
			if segment == null:
				continue
			if segment.has_method("uses_endpoint") and segment.uses_endpoint(node, endpoint_world_position):
				return false

		return true

	return true

func _get_owner_connector_for_world_position(owner_node: Node, endpoint_world_position: Vector2) -> Node2D:
	if owner_node == null:
		return null

	if endpoint_world_position == Vector2.ZERO:
		if owner_node is Node2D:
			return owner_node as Node2D
		return null

	var best_connector: Node2D = null
	var best_distance: float = max(node_snap_distance, 1.0)

	for marker in get_network_markers():
		if marker.get("network_node", null) != owner_node:
			continue
		var connector_node: Node2D = marker.get("connector_node", null)
		if connector_node == null:
			continue
		var marker_world_pos: Vector2 = marker.get("world_position", Vector2.ZERO)
		var distance: float = marker_world_pos.distance_to(endpoint_world_position)
		if distance > best_distance:
			continue
		best_distance = distance
		best_connector = connector_node

	if best_connector != null:
		return best_connector

	if owner_node is Node2D:
		return owner_node as Node2D
	return null

func _get_endpoint_connection_count(owner_node: Node, endpoint_world_position: Vector2) -> int:
	if owner_node == null or endpoint_world_position == Vector2.ZERO:
		return 0

	var count: int = 0
	for segment in get_tree().get_nodes_in_group("cable_segments"):
		if segment == null:
			continue
		if segment.has_method("uses_endpoint") and segment.uses_endpoint(owner_node, endpoint_world_position):
			count += 1
	return count

func _is_anchor_too_close_to_network_node(world_position: Vector2) -> bool:
	for marker in get_network_markers():
		var marker_world_pos: Vector2 = marker.get("world_position", Vector2.ZERO)
		if marker_world_pos.distance_to(world_position) < anchor_min_distance_from_nodes:
			return true
	return false

func _get_network_port_icon(owner_node: Node, connector_node: Node2D) -> String:
	if owner_node != null and owner_node.has_method("get_network_port_icon"):
		return str(owner_node.call("get_network_port_icon", connector_node))

	if owner_node != null and owner_node.has_method("get_network_port_type"):
		var port_type: String = str(owner_node.call("get_network_port_type", connector_node))
		if port_type == "internet_source" or port_type == "internet":
			return "🌐"
		if port_type == "server":
			return "⚡"

	return ""

func _draw_network_node_icon(screen_position: Vector2, icon_text: String) -> void:
	if icon_text == "":
		return

	var icon_font: Font = ThemeDB.fallback_font
	if icon_font == null:
		return

	var icon_size_px: int = max(node_icon_size, 8)
	var text_size: Vector2 = icon_font.get_string_size(icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size_px)
	var baseline_offset: float = text_size.y * 0.35
	var draw_position := Vector2(screen_position.x - (text_size.x * 0.5), screen_position.y + baseline_offset)
	draw_string(icon_font, draw_position, icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size_px, node_icon_color)

func would_create_loop(start_node, end_node) -> bool:
	if start_node == null or end_node == null:
		return false
	# If a path already exists, adding another edge closes a cycle.
	return WiringGraph.has_path(start_node, end_node, Callable(self, "_get_network_neighbors"))

func _get_network_neighbors(current_node) -> Array:
	return WiringGraph.neighbors_from_segment_connections(current_node)

func update_all_network_node_highlights() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.has_method("set_cable_mode_highlight"):
			node.set_cable_mode_highlight(visible)

func get_endpoint_state(node, endpoint_world_position: Vector2) -> int:
	# Returns: 0 = empty (gray), 1 = connected (white)
	for segment in get_tree().get_nodes_in_group("cable_segments"):
		if segment == null:
			continue
		if segment.has_method("uses_endpoint") and segment.uses_endpoint(node, endpoint_world_position):
			return 1  # connected
	return 0  # empty

func find_wire_at_position(world_position: Vector2, tolerance: float = 8.0) -> Line2D:
	for segment in get_tree().get_nodes_in_group("cable_segments"):
		if segment == null or not is_instance_valid(segment):
			continue
		if not segment is Line2D:
			continue
		
		for i in range(segment.points.size() - 1):
			var p1 = segment.to_global(segment.points[i])
			var p2 = segment.to_global(segment.points[i + 1])
			var closest_point = get_closest_point_on_segment(world_position, p1, p2)
			var dist = world_position.distance_to(closest_point)
			if dist <= tolerance:
				return segment
	
	return null

func get_closest_point_on_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> Vector2:
	var seg_vec = seg_end - seg_start
	var point_vec = point - seg_start
	var seg_len_sq = seg_vec.length_squared()
	
	if seg_len_sq == 0.0:
		return seg_start
	
	var t = max(0.0, min(1.0, point_vec.dot(seg_vec) / seg_len_sq))
	return seg_start + seg_vec * t

func highlight_wire_route(wire: Line2D) -> void:
	if wire == null:
		return
	
	selected_wire = wire
	highlighted_wire_segments.clear()

	var start_node = wire.get("start_point")
	var end_node = wire.get("end_point")
	if start_node == null or end_node == null:
		return

	# Route highlight should only follow the clicked segment chain through anchors,
	# not the whole graph. This avoids unrelated intersecting routes lighting up.
	var route_segments: Array = WiringGraph.collect_anchor_chain_route(
		wire,
		start_node,
		end_node,
		Callable(self, "_is_network_anchor_node"),
		Callable(self, "_get_connected_network_edges"),
		Callable(self, "_get_other_network_node")
	)
	highlighted_wire_segments = route_segments
	queue_redraw()

func _is_network_anchor_node(node) -> bool:
	if node == null:
		return false
	return str(node.get("network_node_type")) == "anchor"

func _get_connected_network_edges(node) -> Array:
	if node == null:
		return []
	var connected: Variant = node.get("connected_segments")
	if connected is Array:
		return connected
	return []

func _get_other_network_node(edge, node):
	if edge == null or not edge.has_method("get_other_point"):
		return null
	return edge.get_other_point(node)

func show_delete_wire_confirmation() -> void:
	if selected_wire == null or wire_delete_confirmation_open:
		return
	
	wire_delete_confirmation_open = true
	var dialog = ConfirmationDialog.new()
	dialog.title = "Delete Wire"
	dialog.dialog_text = "Are you sure you want to delete this wire?"
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	dialog.size = Vector2(300, 140)
	
	get_tree().current_scene.add_child(dialog)
	
	# Center-align the text
	for child in dialog.get_children():
		if child is Label:
			child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	dialog.confirmed.connect(_on_delete_wire_confirmed)
	dialog.canceled.connect(_on_delete_wire_canceled)
	dialog.popup_centered()

func _on_delete_wire_confirmed() -> void:
	if selected_wire == null or not is_instance_valid(selected_wire):
		wire_delete_confirmation_open = false
		return
	
	var start_node: Node = selected_wire.get("start_point") as Node
	var end_node: Node = selected_wire.get("end_point") as Node
	var start_world_variant: Variant = selected_wire.get("start_visual_position")
	var end_world_variant: Variant = selected_wire.get("end_visual_position")
	var start_world_position: Vector2 = start_world_variant if start_world_variant is Vector2 else Vector2.ZERO
	var end_world_position: Vector2 = end_world_variant if end_world_variant is Vector2 else Vector2.ZERO
	var start_connector: Node2D = _get_owner_connector_for_world_position(start_node, start_world_position)
	var end_connector: Node2D = _get_owner_connector_for_world_position(end_node, end_world_position)
	
	if start_node != null and start_node.has_method("remove_connection_for_node"):
		start_node.remove_connection_for_node(selected_wire, start_connector)
	elif start_node != null and start_node.has_method("remove_connection"):
		start_node.remove_connection(selected_wire)
	
	if end_node != null and end_node.has_method("remove_connection_for_node"):
		end_node.remove_connection_for_node(selected_wire, end_connector)
	elif end_node != null and end_node.has_method("remove_connection"):
		end_node.remove_connection(selected_wire)
	
	selected_wire.queue_free()
	selected_wire = null
	highlighted_wire_segments.clear()
	wire_delete_confirmation_open = false
	if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
		SaveManager.mark_runtime_dirty()
	
	update_all_server_network_status()
	queue_redraw()

func _on_delete_wire_canceled() -> void:
	wire_delete_confirmation_open = false

func clear_wiring() -> void:
	for cable in get_tree().get_nodes_in_group("cable_segments"):
		if cable == null or not is_instance_valid(cable):
			continue
		var start_node: Node = cable.get("start_point") as Node
		var end_node: Node = cable.get("end_point") as Node
		var start_world_variant: Variant = cable.get("start_visual_position")
		var end_world_variant: Variant = cable.get("end_visual_position")
		var start_world_position: Vector2 = start_world_variant if start_world_variant is Vector2 else Vector2.ZERO
		var end_world_position: Vector2 = end_world_variant if end_world_variant is Vector2 else Vector2.ZERO
		var start_connector: Node2D = _get_owner_connector_for_world_position(start_node, start_world_position)
		var end_connector: Node2D = _get_owner_connector_for_world_position(end_node, end_world_position)

		if start_node != null and start_node.has_method("remove_connection_for_node"):
			start_node.remove_connection_for_node(cable, start_connector)
		elif start_node != null and start_node.has_method("remove_connection"):
			start_node.remove_connection(cable)

		if end_node != null and end_node.has_method("remove_connection_for_node"):
			end_node.remove_connection_for_node(cable, end_connector)
		elif end_node != null and end_node.has_method("remove_connection"):
			end_node.remove_connection(cable)
		cable.queue_free()

	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node == null or not is_instance_valid(node):
			continue
		if str(node.get("network_node_type")) != "anchor":
			continue
		node.queue_free()

	placed_cable_segments.clear()
	selected_wire = null
	highlighted_wire_segments.clear()
	cable_start_point = null
	cable_start_world_position = Vector2.ZERO
	clear_cable_preview()
	update_all_server_network_status()
	queue_redraw()

func export_wiring_state() -> Dictionary:
	var anchors: Array = []
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node == null or not is_instance_valid(node):
			continue
		if str(node.get("network_node_type")) != "anchor":
			continue
		if not (node is Node2D):
			continue
		anchors.append({
			"name": node.name,
			"global_position": (node as Node2D).global_position
		})

	var segments: Array = []
	for cable in get_tree().get_nodes_in_group("cable_segments"):
		if cable == null or not is_instance_valid(cable):
			continue
		var start_node = cable.get("start_point")
		var end_node = cable.get("end_point")
		if start_node == null or end_node == null:
			continue
		var start_visual_position: Variant = cable.get("start_visual_position")
		if start_visual_position == null:
			start_visual_position = Vector2.ZERO
		var end_visual_position: Variant = cable.get("end_visual_position")
		if end_visual_position == null:
			end_visual_position = Vector2.ZERO
		var cable_type_name: Variant = cable.get("cable_type_name")
		if cable_type_name == null:
			cable_type_name = "Cat5"
		segments.append({
			"start_path": _node_to_scene_path(start_node),
			"end_path": _node_to_scene_path(end_node),
			"start_visual_position": start_visual_position,
			"end_visual_position": end_visual_position,
			"cable_type_name": str(cable_type_name)
		})

	return {
		"anchors": anchors,
		"segments": segments
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
			var anchor_pos: Vector2 = _variant_to_vector2(anchor_entry.get("global_position", Vector2.ZERO), Vector2.ZERO)
			var anchor = create_cable_anchor(anchor_pos)
			if anchor == null:
				continue
			var requested_name: String = String(anchor_entry.get("name", ""))
			if not requested_name.is_empty():
				anchor.name = requested_name

	await get_tree().process_frame

	var segments: Variant = state.get("segments", [])
	if segments is Array:
		var pending_segments: Array = []
		for segment_variant in segments:
			if not (segment_variant is Dictionary):
				continue
			var segment_entry := segment_variant as Dictionary
			var start_pos: Vector2 = _variant_to_vector2(segment_entry.get("start_visual_position", Vector2.ZERO), Vector2.ZERO)
			var end_pos: Vector2 = _variant_to_vector2(segment_entry.get("end_visual_position", Vector2.ZERO), Vector2.ZERO)
			var start_node = _resolve_network_node_from_saved(String(segment_entry.get("start_path", "")), start_pos)
			var end_node = _resolve_network_node_from_saved(String(segment_entry.get("end_path", "")), end_pos)
			if start_node == null or end_node == null:
				pending_segments.append(segment_entry)
				continue

			var cable_data := _get_cable_data_by_name(String(segment_entry.get("cable_type_name", "Cat5")))
			if start_pos == Vector2.ZERO:
				start_pos = (start_node as Node2D).global_position
			if end_pos == Vector2.ZERO:
				end_pos = (end_node as Node2D).global_position

			var scene = preload("res://scenes/units/cable_segment.tscn")
			var segment = scene.instantiate()
			get_tree().current_scene.add_child(segment)
			segment.setup(start_node, end_node, cable_data, start_pos, end_pos)
			segment.visible = visible

			var start_connector := _get_owner_connector_for_world_position(start_node, start_pos)
			var end_connector := _get_owner_connector_for_world_position(end_node, end_pos)

			if start_node.has_method("add_connection_for_node"):
				start_node.add_connection_for_node(segment, start_connector)
			elif start_node.has_method("add_connection"):
				start_node.add_connection(segment)
			if end_node.has_method("add_connection_for_node"):
				end_node.add_connection_for_node(segment, end_connector)
			elif end_node.has_method("add_connection"):
				end_node.add_connection(segment)

			placed_cable_segments.append(segment)

		var retries_left := 8
		while not pending_segments.is_empty() and retries_left > 0:
			await get_tree().process_frame
			retries_left -= 1
			var still_pending: Array = []
			for pending_variant in pending_segments:
				if not (pending_variant is Dictionary):
					continue
				var pending_entry := pending_variant as Dictionary
				var pending_start_pos: Vector2 = _variant_to_vector2(pending_entry.get("start_visual_position", Vector2.ZERO), Vector2.ZERO)
				var pending_end_pos: Vector2 = _variant_to_vector2(pending_entry.get("end_visual_position", Vector2.ZERO), Vector2.ZERO)
				var pending_start = _resolve_network_node_from_saved(String(pending_entry.get("start_path", "")), pending_start_pos)
				var pending_end = _resolve_network_node_from_saved(String(pending_entry.get("end_path", "")), pending_end_pos)
				if pending_start == null or pending_end == null:
					still_pending.append(pending_entry)
					continue

				var pending_cable_data := _get_cable_data_by_name(String(pending_entry.get("cable_type_name", "Cat5")))
				if pending_start_pos == Vector2.ZERO:
					pending_start_pos = (pending_start as Node2D).global_position
				if pending_end_pos == Vector2.ZERO:
					pending_end_pos = (pending_end as Node2D).global_position

				var pending_scene = preload("res://scenes/units/cable_segment.tscn")
				var pending_segment = pending_scene.instantiate()
				get_tree().current_scene.add_child(pending_segment)
				pending_segment.setup(pending_start, pending_end, pending_cable_data, pending_start_pos, pending_end_pos)
				pending_segment.visible = visible

				var pending_start_connector := _get_owner_connector_for_world_position(pending_start, pending_start_pos)
				var pending_end_connector := _get_owner_connector_for_world_position(pending_end, pending_end_pos)

				if pending_start.has_method("add_connection_for_node"):
					pending_start.add_connection_for_node(pending_segment, pending_start_connector)
				elif pending_start.has_method("add_connection"):
					pending_start.add_connection(pending_segment)
				if pending_end.has_method("add_connection_for_node"):
					pending_end.add_connection_for_node(pending_segment, pending_end_connector)
				elif pending_end.has_method("add_connection"):
					pending_end.add_connection(pending_segment)

				placed_cable_segments.append(pending_segment)

			pending_segments = still_pending

	update_all_server_network_status()
	queue_redraw()

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

func _resolve_network_node_from_saved(path_text: String, fallback_world_pos: Vector2):
	var resolved = _node_from_scene_path(path_text)
	if resolved != null:
		return resolved
	if fallback_world_pos == Vector2.ZERO:
		return null
	var snapped_result = get_snapped_network_node(fallback_world_pos)
	if snapped_result is Dictionary:
		return (snapped_result as Dictionary).get("node", null)
	return null

func _get_cable_data_by_name(cable_name: String) -> Dictionary:
	if buy_menu != null and buy_menu.has_method("get_cable_item_by_name"):
		var data: Variant = buy_menu.call("get_cable_item_by_name", cable_name)
		if data is Dictionary and not (data as Dictionary).is_empty():
			return (data as Dictionary).duplicate(true)

	if cable_name == INTERNET_PIPE_NAME:
		return {
			"name": INTERNET_PIPE_NAME,
			"color": Color(0.94, 0.76, 0.18, 1.0),
			"cost": 12
		}

	if cable_name == "Fiber":
		return {
			"name": "Fiber",
			"color": Color(0.90, 0.95, 1.0, 1.0),
			"cost": 3
		}
	if cable_name == "Cat6":
		return {
			"name": "Cat6",
			"color": Color(0.65, 0.65, 0.65, 1.0),
			"cost": 2
		}
	return {
		"name": "Cat5",
		"color": Color(0.45, 0.45, 0.45, 1.0),
		"cost": 1
	}

func _get_network_port_type_for_endpoint(owner_node: Node, endpoint_world_position: Vector2) -> String:
	if owner_node == null or not owner_node.has_method("get_network_port_type"):
		return ""
	var connector_node: Node2D = _get_owner_connector_for_world_position(owner_node, endpoint_world_position)
	if connector_node == null:
		return ""
	return str(owner_node.call("get_network_port_type", connector_node))

func _get_network_port_type_for_connector(owner_node: Node, connector_node: Node2D) -> String:
	if owner_node == null or connector_node == null:
		return ""
	if not owner_node.has_method("get_network_port_type"):
		return ""
	return str(owner_node.call("get_network_port_type", connector_node))

func _is_uplink_port_type(port_type: String) -> bool:
	return port_type == "internet_source" or port_type == "internet"

func _is_selected_internet_pipe() -> bool:
	if not (selected_cable_type is Dictionary):
		return false
	return str((selected_cable_type as Dictionary).get("name", "")) == INTERNET_PIPE_NAME

func _switch_to_internet_pipe_if_needed() -> void:
	if _is_selected_internet_pipe():
		return

	if not uplink_auto_switched:
		if selected_cable_type is Dictionary:
			pre_uplink_cable_type = (selected_cable_type as Dictionary).duplicate(true)
		elif manual_selected_cable_type is Dictionary and not manual_selected_cable_type.is_empty():
			pre_uplink_cable_type = manual_selected_cable_type.duplicate(true)

	var uplink_cable := _get_cable_data_by_name(INTERNET_PIPE_NAME)
	selected_cable_type = uplink_cable
	uplink_auto_switched = true
	_sync_buy_menu_cable_selection()
	_show_overlay_status("Auto-switched to Internet Pipe for uplink.")

func _restore_manual_cable_after_uplink_if_needed() -> void:
	if not uplink_auto_switched:
		return

	if pre_uplink_cable_type is Dictionary and not pre_uplink_cable_type.is_empty():
		selected_cable_type = pre_uplink_cable_type.duplicate(true)
	elif manual_selected_cable_type is Dictionary and not manual_selected_cable_type.is_empty():
		selected_cable_type = manual_selected_cable_type.duplicate(true)
	else:
		selected_cable_type = _get_preferred_cable_type()

	uplink_auto_switched = false
	pre_uplink_cable_type.clear()
	_sync_buy_menu_cable_selection()
	_show_overlay_status("Restored previous cable selection.")

func _sync_selection_for_clicked_connector(owner_node: Node, connector_node: Node2D) -> void:
	var port_type: String = _get_network_port_type_for_connector(owner_node, connector_node)
	if _is_uplink_port_type(port_type):
		_switch_to_internet_pipe_if_needed()
	else:
		_restore_manual_cable_after_uplink_if_needed()

func _is_internet_uplink_connection(start_node: Node, start_world_position: Vector2, end_node: Node, end_world_position: Vector2) -> bool:
	var start_port_type: String = _get_network_port_type_for_endpoint(start_node, start_world_position)
	var end_port_type: String = _get_network_port_type_for_endpoint(end_node, end_world_position)
	return (start_port_type == "internet_source" and end_port_type == "internet") or (start_port_type == "internet" and end_port_type == "internet_source")

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

func update_all_port_label_visibility(should_show: bool) -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.has_method("set_port_label_visible"):
			node.call("set_port_label_visible", should_show)
