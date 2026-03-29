extends Node2D

@onready var radial_menu = $UI/RadialMenu
@onready var thermal_system = $ThermalSystem
var current_interactable = null
var debug_spawned_servers: Array[Node2D] = []
var debug_stress_servers: Array[Node2D] = []
var stress_preset_index: int = 0
var perf_elapsed: float = 0.0
var perf_frames: int = 0
var perf_label: Label = null
var probe_label: Label = null
var perf_recent_fps_samples: PackedFloat32Array = PackedFloat32Array()
var perf_second_frame_ms_samples: PackedFloat32Array = PackedFloat32Array()
var perf_slow_frames: int = 0
var perf_frame_time_threshold_ms: float = 15.0
var perf_log_each_slow_frame: bool = false
var perf_log_detailed_slow_frames: bool = true
@export var clear_persisted_placed_structures_on_startup: bool = true
@export var draw_airflow_debug_gizmos: bool = false
@export var airflow_debug_arrow_length: float = 56.0
@export var airflow_debug_arrow_width: float = 2.0
@export var show_cursor_probe_readout: bool = true
var placement_rotation_radians: float = 0.0
var placement_level: int = 1
var placement_attempts: int = 0
var placement_successes: int = 0
var placement_blocked_overlaps: int = 0
var placed_type_counts: Dictionary = {
	"server": 0,
	"cooler": 0
}
var placement_active: bool = false
var placement_preview_node: Node2D = null
var placement_preview_scene: PackedScene = null
var placement_preview_type: String = ""
var placement_preview_scene_path: String = ""
var placement_preview_valid: bool = false
var airflow_gizmo_layer: Node2D = null

const DEBUG_SPAWN_ACTION_NAME: StringName = &"debug_spawn_server"
const DEBUG_SPAWN_COOLER_ACTION_NAME: StringName = &"debug_spawn_cooler"
const DEBUG_REMOVE_ACTION_NAME: StringName = &"debug_remove_server"
const DEBUG_ROTATE_LEFT_ACTION_NAME: StringName = &"debug_rotate_placement_left"
const DEBUG_ROTATE_RIGHT_ACTION_NAME: StringName = &"debug_rotate_placement_right"
const DEBUG_SET_LEVEL_1_ACTION_NAME: StringName = &"debug_set_placement_level_1"
const DEBUG_SET_LEVEL_2_ACTION_NAME: StringName = &"debug_set_placement_level_2"
const DEBUG_SET_LEVEL_3_ACTION_NAME: StringName = &"debug_set_placement_level_3"
const DEBUG_CYCLE_MIXED_PRESET_ACTION_NAME: StringName = &"debug_cycle_mixed_preset"
const DEBUG_SPAWN_KEY: Key = KEY_N
const DEBUG_SPAWN_COOLER_KEY: Key = KEY_B
const DEBUG_REMOVE_KEY: Key = KEY_M
const DEBUG_ROTATE_LEFT_KEY: Key = KEY_Q
const DEBUG_ROTATE_RIGHT_KEY: Key = KEY_E
const DEBUG_SET_LEVEL_1_KEY: Key = KEY_1
const DEBUG_SET_LEVEL_2_KEY: Key = KEY_2
const DEBUG_SET_LEVEL_3_KEY: Key = KEY_3
const DEBUG_CYCLE_MIXED_PRESET_KEY: Key = KEY_O
const DEBUG_STRESS_ACTION_NAME: StringName = &"debug_cycle_stress"
const DEBUG_STRESS_KEY: Key = KEY_COMMA
const DEBUG_PARITY_ACTION_NAME: StringName = &"debug_run_parity"
const DEBUG_PARITY_KEY: Key = KEY_PERIOD
const DEBUG_TOGGLE_METRICS_ACTION_NAME: StringName = &"debug_toggle_thermal_metrics"
const DEBUG_TOGGLE_METRICS_KEY: Key = KEY_SLASH
const DEBUG_TOGGLE_AIRFLOW_GIZMOS_ACTION_NAME: StringName = &"debug_toggle_airflow_gizmos"
const DEBUG_TOGGLE_AIRFLOW_GIZMOS_KEY: Key = KEY_G
const STRESS_PRESETS: Array[int] = [3, 25, 50, 75]
const MIXED_PRESETS: Array[int] = [20, 75, 200]
const SERVER_LEVEL_1_SCENE := preload("res://scenes/server/server_level_1.tscn")
const SERVER_LEVEL_2_SCENE := preload("res://scenes/server/server_level_2.tscn")
const SERVER_LEVEL_3_SCENE := preload("res://scenes/server/server_level_3.tscn")
const COOLING_LEVEL_1_SCENE_PATH: String = "res://scenes/cooler/cooling_level_1.tscn"
const COOLING_LEVEL_2_SCENE_PATH: String = "res://scenes/cooler/cooling_level_2.tscn"
const COOLING_LEVEL_3_SCENE_PATH: String = "res://scenes/cooler/cooling_level_3.tscn"
const PERF_LOW_WINDOW_SECONDS: float = 10.0
const PERF_LOW_MAX_SAMPLES: int = 900
const STRESS_SERVER_HEAT_MULTIPLIER: float = 3.5  # Exaggerate heat for better visibility in testing
const PLACEMENT_ROTATION_STEP: float = PI * 0.5
const PREVIEW_VALID_COLOR: Color = Color(0.55, 1.0, 0.55, 0.6)
const PREVIEW_INVALID_COLOR: Color = Color(1.0, 0.45, 0.45, 0.6)

func _ready() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)
	ensure_debug_actions()
	setup_perf_label()
	setup_airflow_gizmo_layer()
	clear_persisted_placed_structures_if_needed()
	load_debug_placed_structures()
	print_testing_help()

func _process(delta: float) -> void:
	update_placement_preview()
	update_cursor_probe_readout()
	perf_elapsed += delta
	perf_frames += 1

	var frame_ms_value: float = delta * 1000.0
	if frame_ms_value > perf_frame_time_threshold_ms:
		perf_slow_frames += 1
		if perf_log_each_slow_frame or perf_log_detailed_slow_frames:
			var summary := "[SlowFrame] ms=%.2f threshold=%.1f" % [frame_ms_value, perf_frame_time_threshold_ms]
			if perf_log_detailed_slow_frames and thermal_system != null and thermal_system.has_method("get_frame_cost_snapshot"):
				var snapshot: Dictionary = thermal_system.call("get_frame_cost_snapshot")
				summary += " | thermal(sim=%.2f upload=%.2f overlay=%.2f refresh=%.2f steps=%d processed=%d ratio=%.2f)" % [
					float(snapshot.get("sim_ms", 0.0)),
					float(snapshot.get("upload_ms", 0.0)),
					float(snapshot.get("overlay_ms", 0.0)),
					float(snapshot.get("source_refresh_ms", 0.0)),
					int(snapshot.get("sim_steps", 0)),
					int(snapshot.get("processed_per_step", 0)),
					float(snapshot.get("processing_ratio", 0.0))
				]
			print(summary)

	var inst_fps: float = 1.0 / max(delta, 0.0001)
	perf_recent_fps_samples.append(inst_fps)
	perf_second_frame_ms_samples.append(delta * 1000.0)
	trim_perf_low_samples()

	if perf_elapsed >= 1.0:
		var avg_fps: float = float(perf_frames) / max(perf_elapsed, 0.001)
		var frame_ms: float = 1000.0 / max(avg_fps, 0.001)
		var one_percent_low: float = compute_one_percent_low_fps()
		var p99_ms: float = compute_percentile_ms(perf_second_frame_ms_samples, 99.0)
		var max_ms: float = compute_max_ms(perf_second_frame_ms_samples)
		var summary: String = "FPS: %s | 1%% low: %s | ms: %s | p99_ms: %s | max_ms: %s | heat_vision: %s | heat_sources: %d | stress: %d" % [
			String.num(avg_fps, 1),
			String.num(one_percent_low, 1),
			String.num(frame_ms, 2),
			String.num(p99_ms, 2),
			String.num(max_ms, 2),
			"ON" if is_heat_vision_enabled() else "OFF",
			count_heat_sources(),
			debug_stress_servers.size()
		]
		var source_type_counts: Dictionary = count_heat_sources_by_type()
		summary += " | placed(s/c): %d/%d | place_ok: %d | place_blocked: %d | rot: %ddeg | placing: %s" % [
			int(source_type_counts.get("server", 0)),
			int(source_type_counts.get("cooler", 0)),
			placement_successes,
			placement_blocked_overlaps,
			int(round(rad_to_deg(placement_rotation_radians))),
			"ON" if placement_active else "OFF"
		]
		summary += " | level: %d" % [placement_level]

		var slow_pct: float = (100.0 * float(perf_slow_frames)) / max(float(perf_frames), 1.0)
		summary += " | slow_frames: %d (%.1f%%)" % [perf_slow_frames, slow_pct]

		if perf_label != null:
			perf_label.text = summary

		print("[Perf] ", summary)
		perf_elapsed = 0.0
		perf_frames = 0
		perf_slow_frames = 0
		perf_second_frame_ms_samples.clear()

	if draw_airflow_debug_gizmos:
		refresh_airflow_gizmo_overlay()
	else:
		clear_airflow_gizmo_overlay()

func trim_perf_low_samples() -> void:
	var estimated_window_samples: int = int(ceil(PERF_LOW_WINDOW_SECONDS * 120.0))
	var max_samples: int = min(max(estimated_window_samples, 120), PERF_LOW_MAX_SAMPLES)
	if perf_recent_fps_samples.size() <= max_samples:
		return

	var drop_count: int = perf_recent_fps_samples.size() - max_samples
	perf_recent_fps_samples = perf_recent_fps_samples.slice(drop_count, perf_recent_fps_samples.size())

func compute_one_percent_low_fps() -> float:
	if perf_recent_fps_samples.is_empty():
		return 0.0

	var sorted_samples: PackedFloat32Array = perf_recent_fps_samples.duplicate()
	sorted_samples.sort()
	var index: int = int(floor(float(sorted_samples.size() - 1) * 0.01))
	index = clamp(index, 0, sorted_samples.size() - 1)
	return sorted_samples[index]

func compute_percentile_ms(samples: PackedFloat32Array, percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: PackedFloat32Array = samples.duplicate()
	sorted_samples.sort()
	var t: float = clamp(percentile / 100.0, 0.0, 1.0)
	var index: int = int(floor(float(sorted_samples.size() - 1) * t))
	index = clamp(index, 0, sorted_samples.size() - 1)
	return sorted_samples[index]

func compute_max_ms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var max_value: float = 0.0
	for sample in samples:
		max_value = max(max_value, sample)
	return max_value

func is_heat_vision_enabled() -> bool:
	if thermal_system == null:
		return false
	var enabled_variant: Variant = thermal_system.get("heat_view_enabled")
	if enabled_variant == null:
		return false
	return bool(enabled_variant)

func _unhandled_input(event: InputEvent) -> void:
	if placement_active and event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			try_confirm_preview_placement()
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement_mode()
			return

	if event.is_action_pressed(DEBUG_SPAWN_ACTION_NAME):
		begin_server_placement_mode()
	elif event.is_action_pressed(DEBUG_SPAWN_COOLER_ACTION_NAME):
		begin_cooler_placement_mode()
	elif event.is_action_pressed(DEBUG_REMOVE_ACTION_NAME):
		remove_last_debug_server()
	elif event.is_action_pressed(DEBUG_ROTATE_LEFT_ACTION_NAME):
		rotate_placement(-1)
	elif event.is_action_pressed(DEBUG_ROTATE_RIGHT_ACTION_NAME):
		rotate_placement(1)
	elif event.is_action_pressed(DEBUG_STRESS_ACTION_NAME):
		cycle_stress_preset()
	elif event.is_action_pressed(DEBUG_PARITY_ACTION_NAME):
		run_parity_probe()
	elif event.is_action_pressed(DEBUG_TOGGLE_METRICS_ACTION_NAME):
		toggle_thermal_metrics()
	elif event.is_action_pressed(DEBUG_TOGGLE_AIRFLOW_GIZMOS_ACTION_NAME):
		toggle_airflow_debug_gizmos()
	elif event.is_action_pressed(DEBUG_SET_LEVEL_1_ACTION_NAME):
		set_placement_level(1)
	elif event.is_action_pressed(DEBUG_SET_LEVEL_2_ACTION_NAME):
		set_placement_level(2)
	elif event.is_action_pressed(DEBUG_SET_LEVEL_3_ACTION_NAME):
		set_placement_level(3)
	elif event.is_action_pressed(DEBUG_CYCLE_MIXED_PRESET_ACTION_NAME):
		cycle_mixed_preset()

func ensure_debug_actions() -> void:
	ensure_action_with_key(DEBUG_SPAWN_ACTION_NAME, DEBUG_SPAWN_KEY)
	ensure_action_with_key(DEBUG_SPAWN_COOLER_ACTION_NAME, DEBUG_SPAWN_COOLER_KEY)
	ensure_action_with_key(DEBUG_REMOVE_ACTION_NAME, DEBUG_REMOVE_KEY)
	ensure_action_with_key(DEBUG_ROTATE_LEFT_ACTION_NAME, DEBUG_ROTATE_LEFT_KEY)
	ensure_action_with_key(DEBUG_ROTATE_RIGHT_ACTION_NAME, DEBUG_ROTATE_RIGHT_KEY)
	ensure_action_with_key(DEBUG_STRESS_ACTION_NAME, DEBUG_STRESS_KEY)
	ensure_action_with_key(DEBUG_PARITY_ACTION_NAME, DEBUG_PARITY_KEY)
	ensure_action_with_key(DEBUG_TOGGLE_METRICS_ACTION_NAME, DEBUG_TOGGLE_METRICS_KEY)
	ensure_action_with_key(DEBUG_TOGGLE_AIRFLOW_GIZMOS_ACTION_NAME, DEBUG_TOGGLE_AIRFLOW_GIZMOS_KEY)
	ensure_action_with_key(DEBUG_SET_LEVEL_1_ACTION_NAME, DEBUG_SET_LEVEL_1_KEY)
	ensure_action_with_key(DEBUG_SET_LEVEL_2_ACTION_NAME, DEBUG_SET_LEVEL_2_KEY)
	ensure_action_with_key(DEBUG_SET_LEVEL_3_ACTION_NAME, DEBUG_SET_LEVEL_3_KEY)
	ensure_action_with_key(DEBUG_CYCLE_MIXED_PRESET_ACTION_NAME, DEBUG_CYCLE_MIXED_PRESET_KEY)

func setup_perf_label() -> void:
	var hud_root := get_node_or_null("CanvasLayer/Control") as Control
	if hud_root == null:
		return

	perf_label = Label.new()
	perf_label.name = "PerfLabel"
	perf_label.text = "FPS: --"
	perf_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	perf_label.offset_left = 16.0
	perf_label.offset_top = 18.0
	perf_label.offset_right = -16.0
	perf_label.offset_bottom = 46.0
	perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(perf_label)

	probe_label = Label.new()
	probe_label.name = "ProbeLabel"
	probe_label.text = "Probe: --"
	probe_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	probe_label.offset_left = 16.0
	probe_label.offset_top = 50.0
	probe_label.offset_right = 640.0
	probe_label.offset_bottom = 78.0
	probe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	probe_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(probe_label)

func update_cursor_probe_readout() -> void:
	if probe_label == null:
		return

	if not show_cursor_probe_readout:
		probe_label.text = "Probe: disabled"
		return

	if thermal_system == null or not thermal_system.has_method("get_probe_at_world_position"):
		probe_label.text = "Probe: thermal probe unavailable"
		return

	var world_pos: Vector2 = get_global_mouse_position()
	var probe_variant: Variant = thermal_system.call("get_probe_at_world_position", world_pos)
	if not (probe_variant is Dictionary):
		probe_label.text = "Probe: no data"
		return

	var probe: Dictionary = probe_variant
	var heat_value: float = float(probe.get("heat", 0.0))
	var temperature_celsius: float = float(probe.get("temperature_celsius", heat_value))
	if not probe.has("temperature_celsius") and thermal_system.has_method("heat_to_celsius"):
		temperature_celsius = float(thermal_system.call("heat_to_celsius", heat_value))
	var airflow_strength: float = float(probe.get("airflow_strength", 0.0))
	var airflow_angle_degrees: float = float(probe.get("airflow_angle_degrees", 0.0))
	var airflow_vector: Vector2 = probe.get("airflow", Vector2.ZERO)
	var cell_pos: Vector2 = probe.get("cell_position", Vector2.ZERO)
	var direction_text: String = "--"
	if airflow_strength > 0.00001:
		direction_text = "%.1f deg" % airflow_angle_degrees

	probe_label.text = "Probe cell(%.1f, %.1f) | temp: %.1f C | heat: %.2f | flow: %.5f cells/s | vec:(%.4f, %.4f) | dir: %s" % [
		cell_pos.x,
		cell_pos.y,
		temperature_celsius,
		heat_value,
		airflow_strength,
		airflow_vector.x,
		airflow_vector.y,
		direction_text
	]

func ensure_action_with_key(action_name: StringName, action_key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == action_key:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = action_key
	InputMap.action_add_event(action_name, key_event)

func get_save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")

func get_scene_save_key() -> String:
	if not scene_file_path.is_empty():
		return scene_file_path
	return str(get_path())

func get_section_save_key() -> String:
	if thermal_system != null and thermal_system.has_method("get_simulation_section_key"):
		return String(thermal_system.call("get_simulation_section_key"))
	return "default"

func clear_persisted_placed_structures_if_needed() -> void:
	if not clear_persisted_placed_structures_on_startup:
		return

	var save_manager := get_save_manager()
	if save_manager == null:
		return

	var scene_key: String = get_scene_save_key()
	var section_key: String = get_section_save_key()

	if save_manager.has_method("save_placed_structures"):
		var cleared: bool = bool(save_manager.call("save_placed_structures", scene_key, section_key, []))
		if cleared:
			print("[StressHarness] Cleared persisted placed structures for scene/section on startup")
		return

	if save_manager.has_method("clear_slot"):
		save_manager.call("clear_slot")
		print("[StressHarness] Cleared full save slot fallback because save_placed_structures API is unavailable")

func count_heat_sources() -> int:
	return get_tree().get_nodes_in_group("heat_sources").size()

func count_heat_sources_by_type() -> Dictionary:
	var counts: Dictionary = {
		"server": 0,
		"cooler": 0,
		"other": 0
	}

	for source in get_tree().get_nodes_in_group("heat_sources"):
		if not (source is Node):
			continue
		var node := source as Node
		if node.has_method("get_heat_source_type"):
			var type_name: String = String(node.call("get_heat_source_type"))
			if counts.has(type_name):
				counts[type_name] = int(counts[type_name]) + 1
			else:
				counts["other"] = int(counts["other"]) + 1
		else:
			counts["other"] = int(counts["other"]) + 1

	return counts

func print_testing_help() -> void:
	print("[StressHarness] Controls: N=server placement, B=cooler placement, 1/2/3=set level, LeftClick=confirm, RightClick=cancel, Q/E=rotate, M=remove last, ,=cycle stress servers (3/25/50/75), O=cycle mixed preset (20/75/200), .=run parity probe, /=toggle thermal metrics, G=toggle airflow gizmos")
	print("[StressHarness] Current baseline heat sources in scene: ", count_heat_sources())
	print("[StressHarness] Stress presets are additive over existing map sources; only harness-spawned stress servers are cleared each cycle.")

func set_placement_level(level: int) -> void:
	placement_level = clamp(level, 1, 3)
	if placement_active:
		if placement_preview_type.begins_with("server"):
			begin_server_placement_mode()
		elif placement_preview_type.begins_with("cooling"):
			begin_cooler_placement_mode()
	print("[Placement] Level set to ", placement_level)

func get_server_scene_for_level(level: int) -> PackedScene:
	match clamp(level, 1, 3):
		1:
			return SERVER_LEVEL_1_SCENE
		2:
			return SERVER_LEVEL_2_SCENE
		_:
			return SERVER_LEVEL_3_SCENE

func get_server_scene_path_for_level(level: int) -> String:
	return "res://scenes/server/server_level_%d.tscn" % clamp(level, 1, 3)

func get_cooler_scene_path_for_level(level: int) -> String:
	return "res://scenes/cooler/cooling_level_%d.tscn" % clamp(level, 1, 3)

func begin_server_placement_mode() -> void:
	var level: int = clamp(placement_level, 1, 3)
	begin_placement_mode(get_server_scene_for_level(level), "server_level_%d" % level, get_server_scene_path_for_level(level))

func begin_cooler_placement_mode() -> void:
	var level: int = clamp(placement_level, 1, 3)
	var scene_path: String = get_cooler_scene_path_for_level(level)
	begin_placement_mode(load(scene_path) as PackedScene, "cooling_level_%d" % level, scene_path)

func setup_airflow_gizmo_layer() -> void:
	if airflow_gizmo_layer != null and is_instance_valid(airflow_gizmo_layer):
		return

	airflow_gizmo_layer = Node2D.new()
	airflow_gizmo_layer.name = "AirflowGizmoLayer"
	airflow_gizmo_layer.z_as_relative = false
	airflow_gizmo_layer.z_index = 4096
	airflow_gizmo_layer.set_as_top_level(true)
	add_child(airflow_gizmo_layer)

func clear_airflow_gizmo_overlay() -> void:
	if airflow_gizmo_layer == null or not is_instance_valid(airflow_gizmo_layer):
		return

	for child in airflow_gizmo_layer.get_children():
		child.queue_free()

func refresh_airflow_gizmo_overlay() -> void:
	if airflow_gizmo_layer == null or not is_instance_valid(airflow_gizmo_layer):
		return

	clear_airflow_gizmo_overlay()

	for source_variant in get_tree().get_nodes_in_group("heat_sources"):
		if not (source_variant is Node2D):
			continue

		var source := source_variant as Node2D
		if source == null or not is_instance_valid(source):
			continue

		if not source.has_method("get_back_direction") or not source.has_method("get_intake_direction"):
			continue

		var marker := Node2D.new()
		marker.position = source.global_position
		airflow_gizmo_layer.add_child(marker)

		var back_dir: Vector2 = (source.call("get_back_direction") as Vector2).normalized()
		var source_type: String = ""
		if source.has_method("get_heat_source_type"):
			source_type = String(source.call("get_heat_source_type"))

		if source_type == "cooler":
			marker.add_child(build_arrow_node(back_dir, Color(0.25, 0.85, 1.0, 0.95), airflow_debug_arrow_length))
		else:
			marker.add_child(build_arrow_node(back_dir, Color(1.0, 0.45, 0.1, 0.95), airflow_debug_arrow_length))

func build_arrow_node(direction: Vector2, color: Color, length: float) -> Node2D:
	var root := Node2D.new()
	if direction.length() < 0.001:
		return root

	var dir: Vector2 = direction.normalized()
	var end: Vector2 = dir * length
	var head_size: float = max(6.0, airflow_debug_arrow_width * 3.0)
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var left: Vector2 = end - (dir * head_size) + (normal * (head_size * 0.6))
	var right: Vector2 = end - (dir * head_size) - (normal * (head_size * 0.6))

	var line := Line2D.new()
	line.default_color = color
	line.width = airflow_debug_arrow_width
	line.points = PackedVector2Array([Vector2.ZERO, end])
	line.antialiased = true
	root.add_child(line)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([end, left, right])
	head.color = color
	root.add_child(head)

	return root

func toggle_airflow_debug_gizmos() -> void:
	draw_airflow_debug_gizmos = not draw_airflow_debug_gizmos
	if draw_airflow_debug_gizmos:
		refresh_airflow_gizmo_overlay()
	else:
		clear_airflow_gizmo_overlay()
	print("[StressHarness] Airflow gizmos ", "ON" if draw_airflow_debug_gizmos else "OFF")

func begin_placement_mode(scene: PackedScene, structure_type: String, scene_path: String) -> void:
	if scene == null:
		print("[Placement] Failed to begin placement mode. Missing scene for type=", structure_type)
		return

	placement_preview_scene = scene
	placement_preview_type = structure_type
	placement_preview_scene_path = scene_path
	placement_active = true
	rebuild_placement_preview_visual()
	update_placement_preview()
	print("[Placement] Mode active for ", structure_type, ". LeftClick place, RightClick cancel")

func try_confirm_preview_placement() -> void:
	if not placement_active or placement_preview_scene == null:
		return

	placement_attempts += 1
	var world_position: Vector2 = get_global_mouse_position()
	var result := spawn_structure_at_position(placement_preview_scene, placement_preview_type, placement_preview_scene_path, world_position, placement_rotation_radians, true, true)
	if result == null:
		placement_blocked_overlaps += 1
		placement_preview_valid = false
		apply_preview_tint(false)
		return

	placement_successes += 1
	if placement_preview_type.begins_with("server"):
		placed_type_counts["server"] = int(placed_type_counts.get("server", 0)) + 1
	elif placement_preview_type.begins_with("cooling"):
		placed_type_counts["cooler"] = int(placed_type_counts.get("cooler", 0)) + 1

func cancel_placement_mode() -> void:
	placement_active = false
	placement_preview_scene = null
	placement_preview_type = ""
	placement_preview_scene_path = ""
	placement_preview_valid = false
	if placement_preview_node != null and is_instance_valid(placement_preview_node):
		placement_preview_node.queue_free()
	placement_preview_node = null

func update_placement_preview() -> void:
	if not placement_active:
		return
	if placement_preview_node == null or not is_instance_valid(placement_preview_node):
		rebuild_placement_preview_visual()
		if placement_preview_node == null:
			return

	placement_preview_node.position = get_global_mouse_position()
	placement_preview_node.rotation = placement_rotation_radians
	placement_preview_valid = can_place_scene(placement_preview_scene, placement_preview_node.position, placement_preview_node.rotation)
	apply_preview_tint(placement_preview_valid)

func rebuild_placement_preview_visual() -> void:
	if placement_preview_node != null and is_instance_valid(placement_preview_node):
		placement_preview_node.queue_free()

	placement_preview_node = Node2D.new()
	placement_preview_node.name = "PlacementPreview"
	placement_preview_node.z_index = 200
	add_child(placement_preview_node)

	if placement_preview_scene == null:
		return

	var probe := placement_preview_scene.instantiate() as Node2D
	if probe == null:
		return

	var source_sprite := find_first_sprite(probe)
	if source_sprite != null:
		var preview_sprite := Sprite2D.new()
		preview_sprite.texture = source_sprite.texture
		preview_sprite.position = source_sprite.position
		preview_sprite.offset = source_sprite.offset
		preview_sprite.centered = source_sprite.centered
		preview_sprite.scale = source_sprite.scale
		placement_preview_node.add_child(preview_sprite)

	probe.free()

func find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite := find_first_sprite(child)
		if sprite != null:
			return sprite
	return null

func apply_preview_tint(is_valid: bool) -> void:
	if placement_preview_node == null or not is_instance_valid(placement_preview_node):
		return

	var tint: Color = PREVIEW_VALID_COLOR if is_valid else PREVIEW_INVALID_COLOR
	for child in placement_preview_node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).modulate = tint

func spawn_structure_at_position(scene: PackedScene, structure_type: String, scene_path: String, world_position: Vector2, rotation_radians: float, persist_structure: bool, validate_overlap: bool) -> Node2D:
	if scene == null:
		return null

	if validate_overlap and not can_place_scene(scene, world_position, rotation_radians):
		print("[Placement] Blocked overlap for type=", structure_type, " at ", world_position)
		return null

	var spawned := scene.instantiate() as Node2D
	if spawned == null:
		return null

	spawned.position = world_position
	spawned.rotation = rotation_radians
	add_child(spawned)

	if persist_structure:
		debug_spawned_servers.append(spawned)
		var save_manager := get_save_manager()
		if save_manager != null and save_manager.has_method("add_placed_structure"):
			var structure_id: String = String(save_manager.call(
				"add_placed_structure",
				get_scene_save_key(),
				get_section_save_key(),
				{
					"type": structure_type,
					"scene_path": scene_path,
					"position": spawned.position,
					"rotation": spawned.rotation,
					"scale": spawned.scale
				}
			))
			if not structure_id.is_empty():
				spawned.set_meta("placed_structure_id", structure_id)
	else:
		# Stress server: exaggerate heat for better visibility in testing.
		if spawned.has_method("set"):
			var base_heat_value: Variant = spawned.get("base_heat")
			if base_heat_value is float:
				spawned.set("base_heat", float(base_heat_value) * STRESS_SERVER_HEAT_MULTIPLIER)
			var heat_per_tps_value: Variant = spawned.get("heat_per_tps")
			if heat_per_tps_value is float:
				spawned.set("heat_per_tps", float(heat_per_tps_value) * STRESS_SERVER_HEAT_MULTIPLIER)
		if spawned.has_method("recalculate_heat"):
			spawned.call("recalculate_heat")
		debug_stress_servers.append(spawned)

	return spawned

func can_place_scene(scene: PackedScene, world_position: Vector2, rotation_radians: float) -> bool:
	if scene == null:
		return false

	var probe := scene.instantiate() as Node2D
	if probe == null:
		return false

	var can_place: bool = can_place_probe(probe, world_position, rotation_radians)
	probe.free()
	return can_place

func can_place_probe(probe: Node2D, world_position: Vector2, rotation_radians: float) -> bool:
	var collision_area := probe.get_node_or_null("CollisionArea") as Area2D
	if collision_area == null:
		return true

	var collision_shape := collision_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = collision_area.collision_mask

	var object_transform := Transform2D(rotation_radians, world_position)
	var area_transform := collision_area.transform
	var shape_transform := collision_shape.transform
	query.transform = object_transform * area_transform * shape_transform

	var hits: Array = get_world_2d().direct_space_state.intersect_shape(query)
	for hit in hits:
		var collider_variant: Variant = hit.get("collider")
		if collider_variant is Node:
			var collider := collider_variant as Node
			if is_or_has_heat_source_ancestor(collider):
				return false

	return true

func rotate_placement(step_direction: int) -> void:
	placement_rotation_radians = fposmod(placement_rotation_radians + (PLACEMENT_ROTATION_STEP * float(step_direction)), TAU)
	if placement_active:
		update_placement_preview()
	print("[Placement] Rotation set to ", int(round(rad_to_deg(placement_rotation_radians))), " degrees")

func is_or_has_heat_source_ancestor(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current.is_in_group("heat_sources"):
			return true
		current = current.get_parent()
	return false

func remove_last_debug_server() -> void:
	if debug_spawned_servers.is_empty():
		return

	var structure: Node2D = debug_spawned_servers.pop_back() as Node2D
	if structure == null or not is_instance_valid(structure):
		return

	var structure_id: String = String(structure.get_meta("placed_structure_id", ""))
	var save_manager := get_save_manager()
	if not structure_id.is_empty() and save_manager != null and save_manager.has_method("remove_placed_structure"):
		save_manager.call("remove_placed_structure", get_scene_save_key(), get_section_save_key(), structure_id)

	if structure.has_method("get_heat_source_type"):
		var source_type: String = String(structure.call("get_heat_source_type"))
		if source_type == "server":
			placed_type_counts["server"] = max(int(placed_type_counts.get("server", 0)) - 1, 0)
		elif source_type == "cooler":
			placed_type_counts["cooler"] = max(int(placed_type_counts.get("cooler", 0)) - 1, 0)

	structure.queue_free()

func clear_stress_servers() -> void:
	for node in debug_stress_servers:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	debug_stress_servers.clear()

func cycle_stress_preset() -> void:
	clear_stress_servers()
	var target_count: int = STRESS_PRESETS[stress_preset_index]
	stress_preset_index = (stress_preset_index + 1) % STRESS_PRESETS.size()

	var cols: int = int(ceil(sqrt(float(target_count))))
	var spacing: float = 120.0
	var center: Vector2 = get_global_mouse_position()

	for i in range(target_count):
		var row: int = int(floor(float(i) / float(cols)))
		var col: int = i % cols
		var offset := Vector2((float(col) - (float(cols - 1) * 0.5)) * spacing, (float(row) - (float(cols - 1) * 0.5)) * spacing)
		spawn_structure_at_position(
			SERVER_LEVEL_1_SCENE,
			"server_level_1",
			"res://scenes/server/server_level_1.tscn",
			center + offset,
			0.0,
			false,
			false
		)

	print(
		"[StressHarness] Spawned ", target_count,
		" stress servers at ", center,
		". Active stress servers: ", debug_stress_servers.size(),
		". Total heat sources now: ", count_heat_sources()
	)

func cycle_mixed_preset() -> void:
	clear_stress_servers()
	var target_count: int = MIXED_PRESETS[stress_preset_index % MIXED_PRESETS.size()]
	stress_preset_index = (stress_preset_index + 1) % max(STRESS_PRESETS.size(), MIXED_PRESETS.size())

	var cols: int = int(ceil(sqrt(float(target_count))))
	var spacing: float = 138.0
	var center: Vector2 = get_global_mouse_position()

	for i in range(target_count):
		var row: int = int(floor(float(i) / float(cols)))
		var col: int = i % cols
		var offset := Vector2((float(col) - (float(cols - 1) * 0.5)) * spacing, (float(row) - (float(cols - 1) * 0.5)) * spacing)
		var spawn_position: Vector2 = center + offset

		var level: int = (i % 3) + 1
		var is_cooler: bool = (i % 5) == 0
		var scene: PackedScene = null
		var scene_path: String = ""
		var type_name: String = ""
		if is_cooler:
			scene_path = get_cooler_scene_path_for_level(level)
			scene = load(scene_path) as PackedScene
			type_name = "cooling_level_%d" % level
		else:
			scene = get_server_scene_for_level(level)
			scene_path = get_server_scene_path_for_level(level)
			type_name = "server_level_%d" % level

		if scene == null:
			continue

		spawn_structure_at_position(
			scene,
			type_name,
			scene_path,
			spawn_position,
			(float(i % 4) * PLACEMENT_ROTATION_STEP),
			false,
			false
		)

	print(
		"[StressHarness] Spawned mixed preset count=", target_count,
		" around ", center,
		". Stress nodes: ", debug_stress_servers.size(),
		". Total heat sources now: ", count_heat_sources()
	)

func run_parity_probe() -> void:
	if thermal_system == null:
		return
	if not thermal_system.has_method("trigger_parity_probe"):
		return

	var duration_seconds: float = 5.0
	var duration_variant: Variant = thermal_system.get("parity_probe_seconds")
	if duration_variant != null:
		duration_seconds = float(duration_variant)

	print("[StressHarness] Starting parity probe... this may take a few seconds on heavy maps.")
	thermal_system.call("trigger_parity_probe", duration_seconds)

func toggle_thermal_metrics() -> void:
	if thermal_system == null:
		return

	var current_enabled_variant: Variant = thermal_system.get("enable_thermal_debug_metrics")
	var current_enabled: bool = false
	if current_enabled_variant != null:
		current_enabled = bool(current_enabled_variant)

	var next_enabled: bool = not current_enabled
	thermal_system.set("enable_thermal_debug_metrics", next_enabled)
	print("[StressHarness] ThermalMetrics logging ", "ON" if next_enabled else "OFF")

func load_debug_placed_structures() -> void:
	var save_manager := get_save_manager()
	if save_manager == null or not save_manager.has_method("load_placed_structures"):
		return

	var entries: Variant = save_manager.call("load_placed_structures", get_scene_save_key(), get_section_save_key())
	if not (entries is Array):
		return

	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var scene_path: String = String(entry.get("scene_path", ""))
		if scene_path.is_empty():
			continue

		var packed_scene: PackedScene = load(scene_path)
		if packed_scene == null:
			continue

		var spawned := packed_scene.instantiate() as Node2D
		if spawned == null:
			continue

		spawned.position = entry.get("position", Vector2.ZERO)
		spawned.rotation = float(entry.get("rotation", 0.0))
		spawned.scale = entry.get("scale", Vector2.ONE)
		var structure_id: String = String(entry.get("id", ""))
		if not structure_id.is_empty():
			spawned.set_meta("placed_structure_id", structure_id)

		add_child(spawned)
		debug_spawned_servers.append(spawned)

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
	match action_name:
		"Turn Off":
			return load("res://assets/UI/icons/turn_off.svg")
		"Turn On":
			return load("res://assets/UI/icons/turn_on.svg")
		"Reboot":
			return load("res://assets/UI/icons/reboot.svg")
		"Inspect":
			return load("res://assets/UI/icons/inspect.svg")
		_:
			return null