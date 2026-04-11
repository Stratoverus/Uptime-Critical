extends Node2D

@onready var radial_menu = $UI/RadialMenu
@onready var buy_menu = $BuyMenu
@onready var network_overlay = $NetworkOverlay/Control
@onready var placed_units = $PlacedUnits
@onready var placement_preview = $PlacementPreview
@onready var hud = $HUD
@onready var player = get_tree().get_first_node_in_group("player")
@onready var cable_mode_button = $BuyMenu/Panel/MainVBox/CableModeButton
@onready var electrical_overlay_button = $BuyMenu/Panel/MainVBox/ElectricalOverlayButton
@onready var heat_overlay_button = $BuyMenu/Panel/MainVBox/HeatOverlayButton
@onready var build_view_button = $BuyMenu/Panel/MainVBox/BuildViewButton

const MAIN_MENU_SCENE: String = "res://scenes/ui/MainMenu/main_menu.tscn"
const UNIT_SCENE_BY_ID := {
	"server_rack_l1": "res://scenes/units/server_rack_l1.tscn",
	"server_rack_l2": "res://scenes/units/server_rack_l2.tscn",
	"server_rack_l3": "res://scenes/units/server_rack_l3.tscn",
	"router_l1": "res://scenes/units/router_l1.tscn",
	"router_l2": "res://scenes/units/router_l2.tscn",
	"router_l3": "res://scenes/units/router_l3.tscn",
	"cooling_unit_l1": "res://scenes/units/cooling_unit_l1.tscn",
	"cooling_unit_l2": "res://scenes/units/cooling_unit_l2.tscn",
	"cooling_unit_l3": "res://scenes/units/cooling_unit_l3.tscn",
	"breaker": "res://scenes/units/breaker.tscn"
}

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
var top_alert_label: Label = null
var top_alert_hide_at_ms: int = 0
var pause_menu_panel: PanelContainer = null
var pause_menu_status_label: Label = null
var game_over_panel: PanelContainer = null
var game_over_reason_label: Label = null
var settings_panel: PanelContainer = null
var unsaved_quit_dialog: AcceptDialog = null
var pending_quit_action: String = ""
var loading_world_state: bool = false
var pause_status_tween: Tween = null
var save_slot_popup: PopupPanel = null
var save_slot_list: VBoxContainer = null
var save_slot_name_input: LineEdit = null
var delete_save_confirm_dialog: ConfirmationDialog = null
var pending_delete_slot_name: String = ""
var pending_delete_display_label: String = ""
var fps_counter_label: Label = null
var show_fps_counter: bool = false
var pause_bgm_option: OptionButton = null
var place_sfx_player: AudioStreamPlayer = null

const SETTINGS_CONFIG_PATH: String = "user://settings.cfg"
const BUILD_REVEAL_SHADER_PATH: String = "res://assets/shaders/build_reveal.gdshader"
const DEFAULT_BUILD_TIME_SEC: float = 2.0
const UNPOWERED_DIM_MODULATE: Color = Color(0.45, 0.45, 0.45, 1.0)
const BUILD_SETTLE_DIM_SEC: float = 1.0

const PREVIEW_VALID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const PREVIEW_BLOCKED_COLOR: Color = Color(1.0, 0.25, 0.25, 0.65)
const PREVIEW_INSUFFICIENT_FUNDS_COLOR: Color = Color(1.0, 0.25, 0.25, 0.65)
const PREVIEW_BLOCKED_ZONE_COLOR: Color = Color(0.95, 0.45, 0.45, 0.62)
const PLACE_SFX: AudioStream = preload("res://music/build.wav")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("world_save_state")
	_ensure_escape_cancel_action()
	_ensure_pause_menu_ui()
	_ensure_unsaved_quit_dialog()
	_ensure_settings_panel()
	_ensure_pause_status_label()
	_ensure_save_slot_popup()
	_ensure_delete_save_confirm_dialog()
	_ensure_fps_counter_label()
	_load_runtime_display_settings()
	if GameManager != null and GameManager.has_signal("gameplay_started") and not GameManager.gameplay_started.is_connected(_on_gameplay_started):
		GameManager.gameplay_started.connect(_on_gameplay_started)
	if GameManager != null and GameManager.has_signal("game_over_state_changed") and not GameManager.game_over_state_changed.is_connected(_on_game_over_state_changed):
		GameManager.game_over_state_changed.connect(_on_game_over_state_changed)

	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)
	buy_menu.unit_selected.connect(_on_buy_menu_unit_selected)
	if network_overlay and network_overlay.has_signal("cable_mode_changed"):
		network_overlay.cable_mode_changed.connect(_on_network_overlay_mode_changed)


	if cable_mode_button:
		cable_mode_button.pressed.connect(_on_cable_mode_button_pressed)
	if electrical_overlay_button:
		electrical_overlay_button.pressed.connect(_on_electrical_overlay_button_pressed)
	if heat_overlay_button:
		heat_overlay_button.pressed.connect(_on_heat_overlay_button_pressed)
	if build_view_button:
		build_view_button.pressed.connect(_on_build_view_button_pressed)

	_update_cable_mode_button()
	_update_overlay_toggle_buttons()
	_update_buy_menu_mode()
	_ensure_top_alert_label()
	if GameManager != null and GameManager.is_game_over:
		call_deferred("_on_game_over_state_changed", GameManager.game_over_reason)
	call_deferred("_load_world_state_from_save")
	_ensure_place_sfx_player()

func _on_interaction_requested(interactable) -> void:
	if selected_unit_to_place != null:
		if radial_menu.visible:
			radial_menu.hide()
		current_interactable = null
		pending_action = ""
		return

	if interactable != null and str(interactable.get("object_name")) == "Breaker":
		if radial_menu.visible:
			radial_menu.hide()
		current_interactable = null
		pending_action = ""
		return

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
	elif action_name == "Enable Overdrive":
		return load("res://assets/UI/icons/inspect.svg")
	elif action_name == "Disable Overdrive":
		return load("res://assets/UI/icons/turn_off.svg")
	else:
		return null

func _on_buy_menu_unit_selected(unit_data) -> void:
	if network_overlay != null and network_overlay.visible:
		if network_overlay.has_method("set_selected_cable_type"):
			network_overlay.set_selected_cable_type(unit_data)
		return

	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_overlay != null and electrical_overlay.visible:
		if electrical_overlay.has_method("set_selected_cable_type"):
			electrical_overlay.set_selected_cable_type(unit_data)
		return

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
	shape.size = Vector2(94, 94)
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
	_update_fps_counter_label()
	_update_top_alert_visibility()
	_update_buy_menu_mode()
	_update_overlay_toggle_buttons()

	if network_overlay != null and network_overlay.visible:
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
			return

	if preview_area != null:
		var raw_mouse_pos := get_global_mouse_position()
		var snapped_world_pos := _get_snapped_world_position(raw_mouse_pos)
		preview_area.global_position = snapped_world_pos

		if preview_sprite != null:
			var placement_state := get_current_placement_state_at_world_position(snapped_world_pos)
			if bool(placement_state.get("can_place", false)):
				preview_sprite.modulate = PREVIEW_VALID_COLOR
			else:
				var reason := str(placement_state.get("reason", ""))
				if reason == "insufficient_funds":
					preview_sprite.modulate = PREVIEW_INSUFFICIENT_FUNDS_COLOR
				elif reason == "occupied_unit":
					preview_sprite.modulate = PREVIEW_BLOCKED_COLOR
				else:
					preview_sprite.modulate = PREVIEW_BLOCKED_ZONE_COLOR

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
	if event.is_action_pressed("ui_cancel"):
		if _handle_escape_pressed():
			get_viewport().set_input_as_handled()
		return

	if _is_pause_menu_open():
		return

	if network_overlay != null and network_overlay.visible:
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
			place_selected_unit(event.shift_pressed)

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()

func _handle_escape_pressed() -> bool:
	if _is_pause_menu_open():
		_resume_from_pause_menu()
		return true

	if _close_active_overlay_if_any():
		return true

	_open_pause_menu()
	return true

func _close_active_overlay_if_any() -> bool:
	var closed_any := false

	if network_overlay != null and network_overlay.visible and network_overlay.has_method("set_overlay_visible"):
		network_overlay.set_overlay_visible(false)
		closed_any = true

	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_overlay != null and electrical_overlay.visible and electrical_overlay.has_method("set_overlay_visible"):
		electrical_overlay.set_overlay_visible(false)
		closed_any = true

	var thermal_system = _get_thermal_system_node()
	if thermal_system != null and bool(thermal_system.get("heat_view_enabled")) and thermal_system.has_method("set_heat_view_enabled"):
		thermal_system.set_heat_view_enabled(false)
		closed_any = true

	if closed_any:
		_update_buy_menu_mode()
		_update_overlay_toggle_buttons()

	return closed_any

func update_preview_texture() -> void:
	if preview_sprite == null or selected_unit_to_place == null:
		return

	var facing = get_current_facing()
	preview_sprite.texture = load(selected_unit_to_place["sprites"][facing])

func place_selected_unit(keep_placing: bool = false) -> void:
	if selected_unit_to_place == null:
		return

	if is_cable_mode:
		return

	var snapped_world_pos := _get_snapped_world_position(get_global_mouse_position())
	var placement_state := get_current_placement_state_at_world_position(snapped_world_pos)
	if not bool(placement_state.get("can_place", false)):
		var reason := str(placement_state.get("reason", ""))
		if reason == "insufficient_funds":
			_show_top_alert("Cannot afford this server.")
		elif reason == "occupied_unit":
			_show_top_alert("Cannot build here: a server is already there.")
		elif reason == "blocked_placement":
			_show_top_alert("Cannot build here: area is blocked.")
		elif reason == "cannot_build_tile":
			_show_top_alert("Cannot build here: this tile is not buildable.")
		return

	var cost = selected_unit_to_place["cost"]

	if GameManager == null:
		push_error("GameManager not found")
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
	
	# NEW TILEMAP SNAPPING LOGIC
	new_unit.global_position = snapped_world_pos
	# ==========================================

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
	new_unit.set_meta("scene_path", selected_unit_to_place.get("scene_path", ""))
	_play_build_reveal_animation(new_unit)

	GameManager.spend_money(cost)
	
	if place_sfx_player != null:
		place_sfx_player.play()

	_mark_save_dirty()

	if keep_placing:
		# Keep the selected unit active for RTS-style rapid placement.
		if preview_area == null:
			create_placement_preview()
		return

	cancel_placement()

func _resolve_build_time_seconds(new_unit: Node) -> float:
	if new_unit == null:
		return DEFAULT_BUILD_TIME_SEC

	var interactable := new_unit as InteractableObject
	if interactable != null:
		return max(interactable.build_time_sec, 0.05)

	var scene_build_time: Variant = new_unit.get("build_time_sec")
	if scene_build_time != null:
		return max(float(scene_build_time), 0.05)

	return DEFAULT_BUILD_TIME_SEC

func _play_build_reveal_animation(new_unit: Node) -> void:
	if new_unit == null:
		return

	var build_time_sec := _resolve_build_time_seconds(new_unit)
	new_unit.set_meta("build_time_sec", build_time_sec)

	var ignore_until_ms := int(new_unit.get_meta("ignore_interaction_until", 0))
	var build_complete_ms := Time.get_ticks_msec() + int(round(build_time_sec * 1000.0))
	new_unit.set_meta("ignore_interaction_until", max(ignore_until_ms, build_complete_ms))

	var unit_sprite := new_unit.get_node_or_null("Sprite2D") as Sprite2D
	if unit_sprite == null:
		return

	var reveal_shader := load(BUILD_REVEAL_SHADER_PATH) as Shader
	if reveal_shader == null:
		return

	var reveal_material := ShaderMaterial.new()
	reveal_material.shader = reveal_shader
	reveal_material.set_shader_parameter("reveal_progress", 0.0)
	unit_sprite.material = reveal_material

	var reveal_tween := create_tween()
	reveal_tween.set_trans(Tween.TRANS_SINE)
	reveal_tween.set_ease(Tween.EASE_OUT)
	reveal_tween.tween_property(reveal_material, "shader_parameter/reveal_progress", 1.0, build_time_sec)
	reveal_tween.finished.connect(func() -> void:
		if is_instance_valid(unit_sprite) and unit_sprite.material == reveal_material:
			unit_sprite.material = null
		_play_post_build_visual_settle(new_unit, unit_sprite)
	)

func _play_post_build_visual_settle(new_unit: Node, unit_sprite: Sprite2D) -> void:
	if new_unit == null or unit_sprite == null or not is_instance_valid(unit_sprite):
		return

	var target_modulate := _resolve_unit_visual_target_modulate(new_unit)
	var current_modulate: Color = unit_sprite.modulate

	var current_luma: float = (current_modulate.r + current_modulate.g + current_modulate.b) / 3.0
	var target_luma: float = (target_modulate.r + target_modulate.g + target_modulate.b) / 3.0
	# If target is dark (unpowered), force a visible bright-to-dim settle every time build completes.
	if target_luma < 0.95:
		unit_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		var forced_settle_duration: float = BUILD_SETTLE_DIM_SEC
		if new_unit.has_method("set_sprite_modulate"):
			new_unit.call("set_sprite_modulate", target_modulate, forced_settle_duration)
		else:
			var settle_tween := create_tween()
			settle_tween.set_trans(Tween.TRANS_SINE)
			settle_tween.set_ease(Tween.EASE_OUT)
			settle_tween.tween_property(unit_sprite, "modulate", target_modulate, forced_settle_duration)
			settle_tween.finished.connect(func() -> void:
				if new_unit != null and new_unit.has_method("_apply_visual_state"):
					new_unit.call("_apply_visual_state")
			)
		return

	if target_modulate == current_modulate:
		return

	if target_luma >= current_luma:
		if new_unit.has_method("_apply_visual_state"):
			new_unit.call("_apply_visual_state")
		return

	var settle_duration: float = BUILD_SETTLE_DIM_SEC
	if new_unit.has_method("set_sprite_modulate"):
		new_unit.call("set_sprite_modulate", target_modulate, settle_duration)
	else:
		var settle_tween := create_tween()
		settle_tween.set_trans(Tween.TRANS_SINE)
		settle_tween.set_ease(Tween.EASE_OUT)
		settle_tween.tween_property(unit_sprite, "modulate", target_modulate, settle_duration)
		settle_tween.finished.connect(func() -> void:
			if new_unit != null and new_unit.has_method("_apply_visual_state"):
				new_unit.call("_apply_visual_state")
		)

func _resolve_unit_visual_target_modulate(new_unit: Node) -> Color:
	if new_unit == null:
		return Color(1.0, 1.0, 1.0, 1.0)

	if new_unit.has_method("_is_active"):
		var is_active: bool = bool(new_unit.call("_is_active"))
		if is_active:
			return Color(1.0, 1.0, 1.0, 1.0)
		return UNPOWERED_DIM_MODULATE

	if new_unit.get("is_powered") is bool and not bool(new_unit.get("is_powered")):
		return UNPOWERED_DIM_MODULATE

	return Color(1.0, 1.0, 1.0, 1.0)

func cancel_placement() -> void:
	selected_unit_to_place = null
	clear_placement_preview()
	if buy_menu != null and buy_menu.has_method("clear_selected_button"):
		buy_menu.clear_selected_button()

func can_place_at_current_position() -> bool:
	return get_placement_collision_reason() == ""

func get_placement_collision_reason() -> String:
	if preview_area == null or preview_collision == null:
		return "invalid_preview"

	var shape = preview_collision.shape
	if shape == null:
		return "invalid_shape"

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

		if collider.is_in_group("placed_unit"):
			return "occupied_unit"

		if collider.is_in_group("blocked_placement"):
			return "blocked_placement"

	return ""

func get_current_placement_state() -> Dictionary:
	return get_current_placement_state_at_world_position(_get_snapped_world_position(get_global_mouse_position()))

func _get_snapped_world_position(world_position: Vector2) -> Vector2:
	var active_floor := _get_active_floor()
	if active_floor == null:
		return world_position

	var local_position := active_floor.to_local(world_position)
	var map_coords: Vector2i = active_floor.local_to_map(local_position)
	return active_floor.to_global(active_floor.map_to_local(map_coords))

func get_current_placement_state_at_world_position(world_position: Vector2) -> Dictionary:
	if selected_unit_to_place == null:
		return {"can_place": false, "reason": "no_selection"}

	if not _is_buildable_placement_area(world_position):
		return {"can_place": false, "reason": "cannot_build_tile"}

	var collision_reason := get_placement_collision_reason()
	if collision_reason != "":
		return {"can_place": false, "reason": collision_reason}

	if GameManager == null:
		return {"can_place": false, "reason": "no_game_manager"}

	var cost: float = float(selected_unit_to_place.get("cost", 0))
	if not GameManager.can_afford(cost):
		return {"can_place": false, "reason": "insufficient_funds"}

	return {"can_place": true, "reason": ""}

func _is_buildable_placement_area(world_position: Vector2) -> bool:
	if preview_area == null or preview_collision == null:
		return false

	var shape := preview_collision.shape
	if not (shape is RectangleShape2D):
		return false

	var tilemap_layers: Array = get_tree().current_scene.find_children("*", "TileMapLayer", true, false)
	if tilemap_layers.is_empty():
		return false

	var active_floor := _get_active_floor()
	if active_floor == null:
		return false

	var local_center := active_floor.to_local(world_position)
	var extents := (shape as RectangleShape2D).size * 0.5
	var sample_points := PackedVector2Array([
		local_center,
		local_center + Vector2(-extents.x, -extents.y),
		local_center + Vector2(extents.x, -extents.y),
		local_center + Vector2(extents.x, extents.y),
		local_center + Vector2(-extents.x, extents.y),
		local_center + Vector2(0.0, -extents.y),
		local_center + Vector2(extents.x, 0.0),
		local_center + Vector2(0.0, extents.y),
		local_center + Vector2(-extents.x, 0.0)
	])

	for sample_local in sample_points:
		var sample_world := active_floor.to_global(sample_local)
		if not _is_world_position_buildable_on_any_tilemap_layer(sample_world, tilemap_layers):
			return false

	return true

func _is_world_position_buildable_on_any_tilemap_layer(world_position: Vector2, tilemap_layers: Array) -> bool:
	for layer_node in tilemap_layers:
		var layer := layer_node as TileMapLayer
		if layer == null:
			continue

		var local_position := layer.to_local(world_position)
		var map_coords: Vector2i = layer.local_to_map(local_position)
		var tile_data: TileData = layer.get_cell_tile_data(map_coords)
		if tile_data == null:
			continue

		var can_build_value: Variant = tile_data.get_custom_data("can_build")
		if can_build_value is bool:
			if not bool(can_build_value):
				return false
		elif can_build_value is int:
			if int(can_build_value) == 0:
				return false
		elif can_build_value is float:
			if float(can_build_value) == 0.0:
				return false
		elif can_build_value is String:
			var normalized := String(can_build_value).strip_edges().to_lower()
			if normalized != "true" and normalized != "1" and normalized != "yes":
				return false
		else:
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

func _get_electrical_overlay_node():
	return get_tree().get_first_node_in_group("electrical_overlay")

func _get_thermal_system_node():
	return get_tree().get_first_node_in_group("thermal_system")

func _set_overlay_states(network_enabled: bool, electrical_enabled: bool, heat_enabled: bool) -> void:
	if selected_unit_to_place != null and (network_enabled or electrical_enabled or heat_enabled):
		cancel_placement()
	if network_overlay != null and network_overlay.has_method("set_overlay_visible"):
		network_overlay.set_overlay_visible(network_enabled)

	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_overlay != null and electrical_overlay.has_method("set_overlay_visible"):
		electrical_overlay.set_overlay_visible(electrical_enabled)

	var thermal_system = _get_thermal_system_node()
	if thermal_system != null and thermal_system.has_method("set_heat_view_enabled"):
		thermal_system.set_heat_view_enabled(heat_enabled)

	_update_buy_menu_mode()
	_update_overlay_toggle_buttons()

func _on_cable_mode_button_pressed() -> void:
	var network_currently_enabled: bool = network_overlay != null and network_overlay.visible
	_set_overlay_states(not network_currently_enabled, false, false)

func _on_electrical_overlay_button_pressed() -> void:
	var electrical_overlay = _get_electrical_overlay_node()
	var electrical_currently_enabled: bool = electrical_overlay != null and electrical_overlay.visible
	_set_overlay_states(false, not electrical_currently_enabled, false)

func _on_heat_overlay_button_pressed() -> void:
	var thermal_system = _get_thermal_system_node()
	var heat_currently_enabled: bool = thermal_system != null and bool(thermal_system.get("heat_view_enabled"))
	_set_overlay_states(false, false, not heat_currently_enabled)

func _on_build_view_button_pressed() -> void:
	_set_overlay_states(false, false, false)


func _on_network_overlay_mode_changed(is_enabled: bool) -> void:
	is_cable_mode = is_enabled
	_update_cable_mode_button()
	_update_overlay_toggle_buttons()
	update_all_network_node_highlights()
	_update_buy_menu_mode()

func set_cable_mode(enabled: bool) -> void:
	if network_overlay != null and network_overlay.has_method("set_overlay_visible"):
		network_overlay.set_overlay_visible(enabled)

func _update_cable_mode_button() -> void:
	if not cable_mode_button:
		return

	if is_cable_mode:
		cable_mode_button.text = "Hide Network Overlay (N)"
	else:
		cable_mode_button.text = "Toggle Network Overlay (N)"

func _update_overlay_toggle_buttons() -> void:
	if electrical_overlay_button != null:
		var electrical_overlay = get_tree().get_first_node_in_group("electrical_overlay")
		var electrical_visible: bool = electrical_overlay != null and electrical_overlay.visible
		electrical_overlay_button.text = "Hide Electrical Overlay (J)" if electrical_visible else "Toggle Electrical Overlay (J)"

	if heat_overlay_button != null:
		var thermal_system = get_tree().get_first_node_in_group("thermal_system")
		var heat_enabled: bool = thermal_system != null and bool(thermal_system.get("heat_view_enabled"))
		heat_overlay_button.text = "Hide Heat Overlay (H)" if heat_enabled else "Toggle Heat Overlay (H)"

func _update_buy_menu_mode() -> void:
	if buy_menu == null:
		return

	var electrical_overlay = _get_electrical_overlay_node()
	var electrical_visible: bool = electrical_overlay != null and electrical_overlay.visible

	if buy_menu.has_method("set_menu_mode_by_name"):
		if electrical_visible:
			buy_menu.set_menu_mode_by_name("electrical")
		elif is_cable_mode:
			buy_menu.set_menu_mode_by_name("network")
		else:
			buy_menu.set_menu_mode_by_name("units")
	elif buy_menu.has_method("set_menu_mode"):
		buy_menu.set_menu_mode(is_cable_mode)

func update_all_network_node_highlights() -> void:
	for node in get_tree().get_nodes_in_group("network_nodes"):
		if node.has_method("set_cable_mode_highlight"):
			node.set_cable_mode_highlight(is_cable_mode)

func _ensure_top_alert_label() -> void:
	if top_alert_label != null and is_instance_valid(top_alert_label):
		return

	top_alert_label = Label.new()
	top_alert_label.name = "TopAlertLabel"
	top_alert_label.visible = false
	top_alert_label.z_index = 300
	top_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_alert_label.add_theme_font_size_override("font_size", 24)
	top_alert_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))

	if hud != null:
		hud.add_child(top_alert_label)
	else:
		get_tree().current_scene.add_child(top_alert_label)

func _show_top_alert(message: String, duration_ms: int = 1400) -> void:
	_ensure_top_alert_label()
	if top_alert_label == null:
		return

	top_alert_label.text = message
	top_alert_label.position = Vector2(get_viewport_rect().get_center().x - 240.0, 10.0)
	top_alert_label.visible = true
	top_alert_hide_at_ms = Time.get_ticks_msec() + duration_ms

func _update_top_alert_visibility() -> void:
	if top_alert_label == null:
		return
	if top_alert_hide_at_ms <= 0:
		return
	if Time.get_ticks_msec() >= top_alert_hide_at_ms:
		top_alert_label.visible = false
		top_alert_hide_at_ms = 0

func _ensure_escape_cancel_action() -> void:
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")

	for existing_event: InputEvent in InputMap.action_get_events("ui_cancel"):
		if existing_event is InputEventKey and existing_event.physical_keycode == KEY_ESCAPE:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("ui_cancel", key_event)

func _ensure_pause_menu_ui() -> void:
	if pause_menu_panel != null and is_instance_valid(pause_menu_panel):
		return

	pause_menu_panel = PanelContainer.new()
	pause_menu_panel.name = "PauseMenuPanel"
	pause_menu_panel.visible = false
	pause_menu_panel.z_index = 400
	pause_menu_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu_panel.custom_minimum_size = Vector2(360, 420)
	pause_menu_panel.position = Vector2(get_viewport_rect().get_center().x - 180.0, get_viewport_rect().get_center().y - 210.0)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 18)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_right", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	pause_menu_panel.add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	vbox.add_child(_make_pause_menu_button("Resume", Callable(self, "_resume_from_pause_menu")))
	vbox.add_child(_make_pause_menu_button("Restart Level", Callable(self, "_restart_level_from_pause_menu")))
	vbox.add_child(_make_pause_menu_button("Save", Callable(self, "_save_from_pause_menu")))
	vbox.add_child(_make_pause_menu_button("Settings", Callable(self, "_open_settings_panel")))
	vbox.add_child(_make_pause_menu_button("Quit To Menu", Callable(self, "_request_quit_to_menu")))
	vbox.add_child(_make_pause_menu_button("Quit To Desktop", Callable(self, "_request_quit_to_desktop")))

	if hud != null:
		hud.add_child(pause_menu_panel)
	else:
		add_child(pause_menu_panel)

func _make_pause_menu_button(button_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(280, 46)
	button.pressed.connect(callback)
	return button

func _ensure_pause_status_label() -> void:
	if pause_menu_status_label != null and is_instance_valid(pause_menu_status_label):
		return

	pause_menu_status_label = Label.new()
	pause_menu_status_label.visible = false
	pause_menu_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_menu_status_label.add_theme_font_size_override("font_size", 18)
	pause_menu_status_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.88, 1.0))
	pause_menu_panel.add_child(pause_menu_status_label)

func _ensure_settings_panel() -> void:
	if settings_panel != null and is_instance_valid(settings_panel):
		return

	settings_panel = PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(1, 1, 1, 0.1)

	settings_panel.add_theme_stylebox_override("panel", style)
	settings_panel.name = "PauseSettingsPanel"
	settings_panel.visible = false
	settings_panel.z_index = 410
	settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_panel.custom_minimum_size = Vector2(360, 230)
	settings_panel.position = Vector2(get_viewport_rect().get_center().x - 180.0, get_viewport_rect().get_center().y - 110.0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	settings_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var settings_title := Label.new()
	settings_title.text = "Settings"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(settings_title)

	vbox.add_child(_make_volume_slider_row("Master Volume", "Master"))
	vbox.add_child(_make_volume_slider_row("Music Volume", "Music"))
	vbox.add_child(_make_bgm_dropdown_row())
	vbox.add_child(_make_volume_slider_row("Sound Effects", "SoundEffects"))

	var close_button := Button.new()
	close_button.text = "Back"
	close_button.custom_minimum_size = Vector2(120, 38)
	close_button.pressed.connect(func() -> void:
		settings_panel.visible = false
	)
	vbox.add_child(close_button)

	if hud != null:
		hud.add_child(settings_panel)
	else:
		add_child(settings_panel)

func _make_volume_slider_row(title_text: String, bus_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(130, 22)
	row.add_child(title)

	var slider := HSlider.new()
	slider.min_value = -40.0
	slider.max_value = 6.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(170, 22)
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		slider.value = AudioServer.get_bus_volume_db(bus_idx)
	else:
		slider.editable = false
	slider.value_changed.connect(func(new_value: float) -> void:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, new_value)
	)
	row.add_child(slider)

	return row

func _make_bgm_dropdown_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "BGM Track"
	title.custom_minimum_size = Vector2(130, 22)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	pause_bgm_option = OptionButton.new()
	pause_bgm_option.custom_minimum_size = Vector2(150, 32)
	pause_bgm_option.add_item("Sci-Fi")
	pause_bgm_option.add_item("Cyberpunk")
	pause_bgm_option.add_item("Hyperdrive")
	pause_bgm_option.add_item("Lo-Fi")

	var saved_track := _get_saved_bgm_track()
	_select_option_by_text(pause_bgm_option, saved_track)

	pause_bgm_option.item_selected.connect(_on_pause_bgm_selected)
	row.add_child(pause_bgm_option)

	return row

func _ensure_unsaved_quit_dialog() -> void:
	if unsaved_quit_dialog != null and is_instance_valid(unsaved_quit_dialog):
		return

	unsaved_quit_dialog = AcceptDialog.new()
	unsaved_quit_dialog.title = "Unsaved Progress"
	unsaved_quit_dialog.dialog_text = "You have unsaved progress. Save before quitting?"
	unsaved_quit_dialog.size = Vector2(430, 170)
	unsaved_quit_dialog.add_button("Save and Quit", true, "save_quit")
	unsaved_quit_dialog.add_button("Quit Without Saving", false, "quit_without_save")
	unsaved_quit_dialog.add_cancel_button("Cancel")
	unsaved_quit_dialog.get_ok_button().visible = false
	unsaved_quit_dialog.get_ok_button().disabled = true
	unsaved_quit_dialog.custom_action.connect(_on_unsaved_quit_dialog_action)
	unsaved_quit_dialog.canceled.connect(func() -> void:
		pending_quit_action = ""
	)

	if hud != null:
		hud.add_child(unsaved_quit_dialog)
	else:
		add_child(unsaved_quit_dialog)

func _is_pause_menu_open() -> bool:
	return pause_menu_panel != null and pause_menu_panel.visible

func _open_pause_menu() -> void:
	if pause_menu_panel == null:
		return
	if game_over_panel != null:
		game_over_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	pause_menu_panel.visible = true
	pause_menu_status_label.visible = false
	_set_pause_state(true)

func _resume_from_pause_menu() -> void:
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if save_slot_popup != null:
		save_slot_popup.hide()
	if game_over_panel != null:
		game_over_panel.visible = false
	_set_pause_state(false)

func _restart_level_from_pause_menu() -> void:
	_restart_current_level()

func _save_from_pause_menu() -> void:
	_show_save_slot_popup()

func _show_pause_status(message: String, color: Color) -> void:
	if pause_menu_status_label == null:
		return
	if pause_status_tween != null and pause_status_tween.is_valid():
		pause_status_tween.kill()
	pause_menu_status_label.text = message
	pause_menu_status_label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 1.0))
	pause_menu_status_label.modulate.a = 1.0
	pause_menu_status_label.visible = true
	pause_status_tween = create_tween()
	pause_status_tween.tween_interval(1.15)
	pause_status_tween.tween_property(pause_menu_status_label, "modulate:a", 0.0, 0.45)
	pause_status_tween.finished.connect(func() -> void:
		pause_menu_status_label.visible = false
		pause_menu_status_label.modulate.a = 1.0
	)

func _open_settings_panel() -> void:
	if settings_panel != null:
		settings_panel.visible = true
		if pause_bgm_option != null:
			_select_option_by_text(pause_bgm_option, _get_saved_bgm_track())

func _ensure_game_over_ui() -> void:
	if game_over_panel != null and is_instance_valid(game_over_panel):
		return

	game_over_panel = PanelContainer.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.visible = false
	game_over_panel.z_index = 500
	game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_panel.custom_minimum_size = Vector2(420, 280)
	game_over_panel.position = Vector2(get_viewport_rect().get_center().x - 210.0, get_viewport_rect().get_center().y - 140.0)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 18)
	root_margin.add_theme_constant_override("margin_top", 18)
	root_margin.add_theme_constant_override("margin_right", 18)
	root_margin.add_theme_constant_override("margin_bottom", 18)
	game_over_panel.add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	game_over_reason_label = Label.new()
	game_over_reason_label.text = ""
	game_over_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_over_reason_label.custom_minimum_size = Vector2(360, 0)
	vbox.add_child(game_over_reason_label)

	vbox.add_child(_make_pause_menu_button("Restart Level", Callable(self, "_restart_level_from_pause_menu")))
	vbox.add_child(_make_pause_menu_button("Quit To Menu", Callable(self, "_request_quit_to_menu")))
	vbox.add_child(_make_pause_menu_button("Quit To Desktop", Callable(self, "_request_quit_to_desktop")))

	if hud != null:
		hud.add_child(game_over_panel)
	else:
		add_child(game_over_panel)

func _show_game_over_popup(reason: String) -> void:
	_ensure_game_over_ui()
	cancel_placement()
	_close_active_overlay_if_any()
	if game_over_reason_label != null:
		game_over_reason_label.text = reason if not reason.is_empty() else "The datacenter is no longer recoverable."
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if game_over_panel != null:
		game_over_panel.visible = true
	_set_pause_state(true)

func _hide_game_over_popup() -> void:
	if game_over_panel != null:
		game_over_panel.visible = false

func _restart_current_level() -> void:
	var current_map_path: String = GameManager.current_map_scene_path if GameManager != null else get_tree().current_scene.scene_file_path
	if current_map_path.is_empty():
		return

	_hide_game_over_popup()
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if save_slot_popup != null:
		save_slot_popup.hide()
	_set_pause_state(false)
	if GameManager != null and GameManager.has_method("reset_runtime_state"):
		GameManager.reset_runtime_state(current_map_path)
	SceneTransition.change_scene(current_map_path)

func _ensure_save_slot_popup() -> void:
	if save_slot_popup != null and is_instance_valid(save_slot_popup):
		return

	save_slot_popup = PopupPanel.new()
	save_slot_popup.name = "SaveSlotPopup"
	save_slot_popup.size = Vector2i(520, 480)
	save_slot_popup.process_mode = Node.PROCESS_MODE_ALWAYS

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	save_slot_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Save To File"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var current_slot_label := Label.new()
	current_slot_label.name = "CurrentSlotLabel"
	current_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(current_slot_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	save_slot_list = VBoxContainer.new()
	save_slot_list.add_theme_constant_override("separation", 8)
	scroll.add_child(save_slot_list)

	var line := HSeparator.new()
	root.add_child(line)

	save_slot_name_input = LineEdit.new()
	save_slot_name_input.placeholder_text = "Enter a new save file name"
	root.add_child(save_slot_name_input)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	root.add_child(button_row)

	var save_new_button := Button.new()
	save_new_button.text = "Save As New File"
	save_new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_new_button.pressed.connect(_on_save_as_new_slot_pressed)
	button_row.add_child(save_new_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func() -> void:
		save_slot_popup.hide()
		if _is_pause_menu_open():
			_set_pause_state(true)
	)
	button_row.add_child(close_button)

	if hud != null:
		hud.add_child(save_slot_popup)
	else:
		add_child(save_slot_popup)

func _show_save_slot_popup() -> void:
	_ensure_save_slot_popup()
	_ensure_delete_save_confirm_dialog()
	_refresh_save_slot_popup()
	save_slot_popup.popup_centered()
	_set_pause_state(true)

func _ensure_delete_save_confirm_dialog() -> void:
	if delete_save_confirm_dialog != null and is_instance_valid(delete_save_confirm_dialog):
		return

	delete_save_confirm_dialog = ConfirmationDialog.new()
	delete_save_confirm_dialog.title = "Delete Save File"
	delete_save_confirm_dialog.dialog_text = "Delete this save file permanently?"
	delete_save_confirm_dialog.size = Vector2(460, 170)
	delete_save_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	delete_save_confirm_dialog.confirmed.connect(_on_pause_delete_confirmed)
	delete_save_confirm_dialog.canceled.connect(func() -> void:
		pending_delete_slot_name = ""
		pending_delete_display_label = ""
	)
	delete_save_confirm_dialog.get_ok_button().text = "Delete"

	if hud != null:
		hud.add_child(delete_save_confirm_dialog)
	else:
		add_child(delete_save_confirm_dialog)

func _refresh_save_slot_popup() -> void:
	if save_slot_popup == null or save_slot_list == null:
		return

	var current_slot_label := save_slot_popup.get_node_or_null("MarginContainer/VBoxContainer/CurrentSlotLabel") as Label
	if current_slot_label != null and SaveManager != null and SaveManager.has_method("get_active_slot_label"):
		current_slot_label.text = "Current Save File: %s" % String(SaveManager.get_active_slot_label())

	for child in save_slot_list.get_children():
		child.queue_free()

	if SaveManager == null or not SaveManager.has_method("list_slots"):
		return

	var slots: Array = SaveManager.list_slots()
	if slots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No existing save files. Create a new file below."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_slot_list.add_child(empty_label)
		return

	for slot_variant in slots:
		if not (slot_variant is Dictionary):
			continue
		var slot_entry := slot_variant as Dictionary
		var slot_name: String = String(slot_entry.get("slot_name", ""))
		var display_label: String = String(slot_entry.get("display_label", slot_name))
		var updated_unix: int = int(slot_entry.get("updated_unix", 0))
		var day_value: int = int(slot_entry.get("day", 0))
		var money_value: float = float(slot_entry.get("money", 0.0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 44)
		var updated_text := ""
		if updated_unix > 0:
			updated_text = Time.get_datetime_string_from_unix_time(updated_unix, true)
		button.text = "%s (%s)  Day %d  $%.2f" % [display_label, updated_text, day_value, money_value]
		button.pressed.connect(func() -> void:
			_save_to_existing_slot(slot_name, display_label)
		)
		row.add_child(button)

		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.custom_minimum_size = Vector2(90, 44)
		delete_button.pressed.connect(func() -> void:
			_request_delete_save_file_from_pause(slot_name, display_label)
		)
		row.add_child(delete_button)

		save_slot_list.add_child(row)

func _save_to_existing_slot(slot_name: String, display_label: String) -> void:
	if SaveManager == null or not SaveManager.has_method("request_manual_save_to_slot"):
		_show_pause_status("Save manager unavailable.", Color(1.0, 0.45, 0.45, 1.0))
		return

	var success: bool = bool(SaveManager.request_manual_save_to_slot(slot_name, display_label))
	if success:
		save_slot_popup.hide()
		_set_pause_state(true)
		_show_pause_status("Saved to file %s." % display_label, Color(0.82, 1.0, 0.86, 1.0))
	else:
		_show_pause_status("Save failed for selected file.", Color(1.0, 0.45, 0.45, 1.0))

func _request_delete_save_file_from_pause(slot_name: String, display_label: String) -> void:
	if delete_save_confirm_dialog == null:
		_ensure_delete_save_confirm_dialog()
	if delete_save_confirm_dialog == null:
		_show_pause_status("Delete unavailable.", Color(1.0, 0.45, 0.45, 1.0))
		return

	pending_delete_slot_name = slot_name
	pending_delete_display_label = display_label
	delete_save_confirm_dialog.dialog_text = "Delete save file \"%s\" permanently?" % display_label
	delete_save_confirm_dialog.popup_centered()
	_set_pause_state(true)

func _on_pause_delete_confirmed() -> void:
	var slot_name: String = pending_delete_slot_name
	var display_label: String = pending_delete_display_label
	pending_delete_slot_name = ""
	pending_delete_display_label = ""
	if slot_name.is_empty():
		return

	if SaveManager == null or not SaveManager.has_method("delete_save_file"):
		_show_pause_status("Delete unavailable.", Color(1.0, 0.45, 0.45, 1.0))
		return

	var success: bool = bool(SaveManager.delete_save_file(slot_name))
	if success:
		_show_pause_status("Save file %s deleted." % display_label, Color(0.82, 1.0, 0.86, 1.0))
		_refresh_save_slot_popup()
	else:
		_show_pause_status("Failed to delete save file.", Color(1.0, 0.45, 0.45, 1.0))

func _on_save_as_new_slot_pressed() -> void:
	if SaveManager == null:
		_show_pause_status("Save manager unavailable.", Color(1.0, 0.45, 0.45, 1.0))
		return

	var requested_name: String = ""
	if save_slot_name_input != null:
		requested_name = save_slot_name_input.text.strip_edges()

	if requested_name.is_empty():
		_show_pause_status("Enter a save file name first.", Color(1.0, 0.45, 0.45, 1.0))
		return

	if not SaveManager.has_method("sanitize_slot_name") or not SaveManager.has_method("request_manual_save_to_slot"):
		_show_pause_status("Save manager API missing.", Color(1.0, 0.45, 0.45, 1.0))
		return

	var slot_name: String = String(SaveManager.sanitize_slot_name(requested_name))
	if slot_name.is_empty():
		_show_pause_status("Invalid save file name.", Color(1.0, 0.45, 0.45, 1.0))
		return

	var success: bool = bool(SaveManager.request_manual_save_to_slot(slot_name, requested_name))
	if success:
		if save_slot_name_input != null:
			save_slot_name_input.text = ""
		save_slot_popup.hide()
		_set_pause_state(true)
		_show_pause_status("Saved to new file %s." % requested_name, Color(0.82, 1.0, 0.86, 1.0))
	else:
		_show_pause_status("Failed to save new file.", Color(1.0, 0.45, 0.45, 1.0))

func _request_quit_to_menu() -> void:
	pending_quit_action = "menu"
	_prompt_unsaved_before_quit()

func _request_quit_to_desktop() -> void:
	pending_quit_action = "desktop"
	_prompt_unsaved_before_quit()

func _prompt_unsaved_before_quit() -> void:
	if unsaved_quit_dialog == null or not is_instance_valid(unsaved_quit_dialog):
		_ensure_unsaved_quit_dialog()

	var has_unsaved_changes: bool = SaveManager != null and SaveManager.has_method("has_unsaved_changes") and SaveManager.has_unsaved_changes()
	if unsaved_quit_dialog != null:
		if has_unsaved_changes:
			unsaved_quit_dialog.dialog_text = "You have unsaved progress. Save before quitting?"
		else:
			unsaved_quit_dialog.dialog_text = "No unsaved progress detected. Quit anyway?"

	_set_pause_state(true)
	if unsaved_quit_dialog != null:
		unsaved_quit_dialog.popup_centered()
		return

	# Fallback if dialog couldn't be created.
	_perform_quit_action(false)

func _on_unsaved_quit_dialog_action(action: StringName) -> void:
	match String(action):
		"save_quit":
			_perform_quit_action(true)
		"quit_without_save":
			_perform_quit_action(false)

func _perform_quit_action(save_before_quit: bool) -> void:
	if save_before_quit and SaveManager != null and SaveManager.has_method("request_manual_save"):
		SaveManager.request_manual_save()

	_set_pause_state(false)
	if pending_quit_action == "menu":
		SceneTransition.change_scene(MAIN_MENU_SCENE)
	elif pending_quit_action == "desktop":
		get_tree().quit()
	pending_quit_action = ""

func _set_pause_state(is_paused: bool) -> void:
	get_tree().paused = is_paused
	var music_bus_index: int = AudioServer.get_bus_index(&"Music")
	if music_bus_index >= 0:
		var should_mute := is_paused and not (settings_panel != null and settings_panel.visible)
		AudioServer.set_bus_mute(music_bus_index, should_mute)

func begin_prep_session(duration_seconds: float) -> void:
	_set_pause_state(false)
	_show_pause_status("Prepare yourself - setup has started", Color(1.0, 0.92, 0.45, 1.0))
	if GameManager != null and GameManager.has_method("begin_prep_countdown"):
		GameManager.begin_prep_countdown(duration_seconds)

func set_start_dialog_pause(active: bool) -> void:
	_set_pause_state(active)

func _on_gameplay_started() -> void:
	_set_pause_state(false)
	_show_pause_status("Gameplay resumed", Color(0.85, 1.0, 0.88, 1.0))

func _on_game_over_state_changed(reason: String) -> void:
	_show_game_over_popup(reason)

func get_world_state_key() -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null and not current_scene.scene_file_path.is_empty():
		return current_scene.scene_file_path
	return str(get_path())

func export_world_state() -> Dictionary:
	return {
		"saved_at_unix": Time.get_unix_time_from_system(),
		"player_position": _export_player_position(),
		"placed_units": _export_placed_units_state(),
		"network_wiring": _export_network_wiring_state(),
		"electrical_wiring": _export_electrical_wiring_state()
	}

func _load_world_state_from_save() -> void:
	if SaveManager == null or not SaveManager.has_method("load_world_state"):
		return
	var saved_world_state: Variant = SaveManager.load_world_state(get_world_state_key())
	if not (saved_world_state is Dictionary):
		return
	if (saved_world_state as Dictionary).is_empty():
		return
	await import_world_state(saved_world_state)

func import_world_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	loading_world_state = true
	cancel_placement()

	if state.has("player_position"):
		_import_player_position(state["player_position"])

	_clear_dynamic_world_state()
	await get_tree().process_frame

	var placed_units_state: Variant = state.get("placed_units", [])
	if placed_units_state is Array:
		_import_placed_units_state(placed_units_state as Array)

	await get_tree().process_frame

	var network_state: Variant = state.get("network_wiring", {})
	if network_state is Dictionary and network_overlay != null and network_overlay.has_method("import_wiring_state"):
		await network_overlay.import_wiring_state(network_state)

	var electrical_state: Variant = state.get("electrical_wiring", {})
	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_state is Dictionary and electrical_overlay != null and electrical_overlay.has_method("import_wiring_state"):
		await electrical_overlay.import_wiring_state(electrical_state)

	loading_world_state = false
	_update_overlay_toggle_buttons()
	_update_buy_menu_mode()

func _clear_dynamic_world_state() -> void:
	if network_overlay != null and network_overlay.has_method("clear_wiring"):
		network_overlay.clear_wiring()

	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_overlay != null and electrical_overlay.has_method("clear_wiring"):
		electrical_overlay.clear_wiring()

	if placed_units != null:
		for child in placed_units.get_children():
			child.queue_free()

func _export_player_position() -> Vector2:
	var current_player: Node2D = get_player()
	if current_player == null:
		return Vector2.ZERO
	return current_player.global_position

func _import_player_position(saved_position: Variant) -> void:
	var current_player: Node2D = get_player()
	if current_player == null:
		return
	current_player.global_position = _variant_to_vector2(saved_position, current_player.global_position)

func _export_placed_units_state() -> Array:
	var saved_units: Array = []
	if placed_units == null:
		return saved_units

	for unit in placed_units.get_children():
		if not (unit is Node2D):
			continue
		var unit_node := unit as Node2D

		var scene_path: String = String(unit_node.get_meta("scene_path", ""))
		if scene_path.is_empty() and not unit_node.scene_file_path.is_empty():
			scene_path = unit_node.scene_file_path

		var level_value: int = 1
		var raw_level: Variant = unit_node.get("level")
		if raw_level != null:
			level_value = int(raw_level)

		var base_heat_value: float = 0.0
		var raw_base_heat: Variant = unit_node.get("base_heat")
		if raw_base_heat != null:
			base_heat_value = float(raw_base_heat)

		var heat_radius_value: float = 0.0
		var raw_heat_radius: Variant = unit_node.get("heat_radius")
		if raw_heat_radius != null:
			heat_radius_value = float(raw_heat_radius)

		var airflow_rate_value: float = 0.0
		var raw_airflow_rate: Variant = unit_node.get("airflow_rate")
		if raw_airflow_rate != null:
			airflow_rate_value = float(raw_airflow_rate)

		var cooling_capacity_value: float = 0.0
		var raw_cooling_capacity: Variant = unit_node.get("cooling_capacity")
		if raw_cooling_capacity != null:
			cooling_capacity_value = float(raw_cooling_capacity)

		var save_entry := {
			"name": unit_node.name,
			"scene_path": scene_path,
			"unit_id": String(unit_node.get_meta("unit_id", "")),
			"unit_name": String(unit_node.get_meta("unit_name", "")),
			"cost": float(unit_node.get_meta("cost", 0.0)),
			"global_position": unit_node.global_position,
			"global_rotation": unit_node.global_rotation,
			"facing": String(unit_node.get_meta("facing", "front")),
			"level": level_value,
			"base_heat": base_heat_value,
			"heat_radius": heat_radius_value,
			"airflow_rate": airflow_rate_value,
			"cooling_capacity": cooling_capacity_value
		}

		saved_units.append(save_entry)

	return saved_units

func _import_placed_units_state(saved_units: Array) -> void:
	for unit_variant in saved_units:
		if not (unit_variant is Dictionary):
			continue
		var unit_entry := unit_variant as Dictionary
		var scene_path: String = String(unit_entry.get("scene_path", ""))
		if scene_path.is_empty():
			scene_path = String(UNIT_SCENE_BY_ID.get(String(unit_entry.get("unit_id", "")), ""))
		if scene_path.is_empty():
			continue

		var packed_scene := load(scene_path) as PackedScene
		if packed_scene == null:
			continue

		var new_unit := packed_scene.instantiate()
		if not (new_unit is Area2D):
			new_unit.queue_free()
			continue

		new_unit.name = String(unit_entry.get("name", new_unit.name))
		new_unit.collision_layer = 1 << 1
		new_unit.collision_mask = 1 << 1
		new_unit.monitoring = true
		new_unit.monitorable = true
		new_unit.add_to_group("placed_unit")
		placed_units.add_child(new_unit)

		(new_unit as Node2D).global_position = _variant_to_vector2(unit_entry.get("global_position", Vector2.ZERO), Vector2.ZERO)
		var saved_rotation: float = float(unit_entry.get("global_rotation", 0.0))
		new_unit.set_meta("ignore_interaction_until", Time.get_ticks_msec() + 250)

		var facing: String = String(unit_entry.get("facing", "front"))
		if new_unit.has_method("set_facing"):
			new_unit.set_facing(facing)
		(new_unit as Node2D).global_rotation = saved_rotation

		new_unit.set_meta("unit_id", unit_entry.get("unit_id", ""))
		new_unit.set_meta("unit_name", unit_entry.get("unit_name", ""))
		new_unit.set_meta("cost", unit_entry.get("cost", 0.0))
		new_unit.set_meta("facing", facing)
		new_unit.set_meta("scene_path", scene_path)

		if new_unit.has_signal("interaction_requested"):
			new_unit.interaction_requested.connect(_on_interaction_requested)

		if new_unit.get("level") != null:
			new_unit.set("level", int(unit_entry.get("level", new_unit.get("level"))))
		if new_unit.get("base_heat") != null:
			new_unit.set("base_heat", float(unit_entry.get("base_heat", new_unit.get("base_heat"))))
		if new_unit.get("heat_radius") != null:
			new_unit.set("heat_radius", float(unit_entry.get("heat_radius", new_unit.get("heat_radius"))))
		if new_unit.get("airflow_rate") != null:
			new_unit.set("airflow_rate", float(unit_entry.get("airflow_rate", new_unit.get("airflow_rate"))))
		if new_unit.get("cooling_capacity") != null:
			new_unit.set("cooling_capacity", float(unit_entry.get("cooling_capacity", new_unit.get("cooling_capacity"))))

		if new_unit.has_method("update_actions"):
			new_unit.call("update_actions")

func _export_network_wiring_state() -> Dictionary:
	if network_overlay != null and network_overlay.has_method("export_wiring_state"):
		return network_overlay.export_wiring_state()
	return {}

func _export_electrical_wiring_state() -> Dictionary:
	var electrical_overlay = _get_electrical_overlay_node()
	if electrical_overlay != null and electrical_overlay.has_method("export_wiring_state"):
		return electrical_overlay.export_wiring_state()
	return {}

func _mark_save_dirty() -> void:
	if loading_world_state:
		return
	if SaveManager != null and SaveManager.has_method("mark_runtime_dirty"):
		SaveManager.mark_runtime_dirty()

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

func _load_runtime_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_CONFIG_PATH) != OK:
		show_fps_counter = false
		return
	show_fps_counter = bool(cfg.get_value("display", "show_fps", false))

func _ensure_fps_counter_label() -> void:
	if fps_counter_label != null and is_instance_valid(fps_counter_label):
		return
	fps_counter_label = Label.new()
	fps_counter_label.name = "RuntimeFpsLabel"
	fps_counter_label.visible = false
	fps_counter_label.z_index = 350
	fps_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if hud != null:
		hud.add_child(fps_counter_label)
	else:
		add_child(fps_counter_label)

func _update_fps_counter_label() -> void:
	if fps_counter_label == null:
		return
	if show_fps_counter:
		fps_counter_label.visible = true
		fps_counter_label.text = "FPS: %d" % Engine.get_frames_per_second()
		fps_counter_label.position = Vector2(max(0.0, get_viewport_rect().size.x - 140.0), 16.0)
	else:
		fps_counter_label.visible = false

func _get_active_floor() -> TileMapLayer:
	# This asks the engine to find the node with our tag.
	# If the room hasn't loaded yet, it safely returns null.
	return get_tree().get_first_node_in_group("floor_tilemap") as TileMapLayer

func _get_saved_bgm_track() -> String:
	if has_node("/root/MusicManager"):
		return MusicManager.get_current_track()
	return "Sci-Fi"

func _select_option_by_text(option_button: OptionButton, text: String) -> void:
	for i in range(option_button.get_item_count()):
		if option_button.get_item_text(i) == text:
			option_button.select(i)
			return

func _on_pause_bgm_selected(index: int) -> void:
	var selected_name := pause_bgm_option.get_item_text(index)
	_save_runtime_bgm_track(selected_name)
	_apply_runtime_bgm(selected_name)

func _apply_runtime_bgm(track_name: String) -> void:
	if has_node("/root/MusicManager"):
		MusicManager.play_track(track_name)

func _save_runtime_bgm_track(_track_name: String) -> void:
	pass

func _ensure_place_sfx_player() -> void:
	if place_sfx_player != null and is_instance_valid(place_sfx_player):
		return

	place_sfx_player = AudioStreamPlayer.new()
	place_sfx_player.name = "PlaceSfxPlayer"
	place_sfx_player.bus = "SoundEffects"
	place_sfx_player.stream = PLACE_SFX
	add_child(place_sfx_player)