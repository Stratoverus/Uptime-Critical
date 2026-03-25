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
var perf_recent_fps_samples: PackedFloat32Array = PackedFloat32Array()
var perf_second_frame_ms_samples: PackedFloat32Array = PackedFloat32Array()
var perf_slow_frames: int = 0
var perf_frame_time_threshold_ms: float = 15.0
var perf_log_each_slow_frame: bool = false
var perf_log_detailed_slow_frames: bool = true

const DEBUG_SPAWN_ACTION_NAME: StringName = &"debug_spawn_server"
const DEBUG_REMOVE_ACTION_NAME: StringName = &"debug_remove_server"
const DEBUG_SPAWN_KEY: Key = KEY_N
const DEBUG_REMOVE_KEY: Key = KEY_M
const DEBUG_STRESS_ACTION_NAME: StringName = &"debug_cycle_stress"
const DEBUG_STRESS_KEY: Key = KEY_COMMA
const DEBUG_PARITY_ACTION_NAME: StringName = &"debug_run_parity"
const DEBUG_PARITY_KEY: Key = KEY_PERIOD
const DEBUG_TOGGLE_METRICS_ACTION_NAME: StringName = &"debug_toggle_thermal_metrics"
const DEBUG_TOGGLE_METRICS_KEY: Key = KEY_SLASH
const STRESS_PRESETS: Array[int] = [3, 25, 50, 75]
const SERVER_LEVEL_1_SCENE := preload("res://scenes/server/server_level_1.tscn")
const PERF_LOW_WINDOW_SECONDS: float = 10.0
const PERF_LOW_MAX_SAMPLES: int = 900
const STRESS_SERVER_HEAT_MULTIPLIER: float = 3.5  # Exaggerate heat for better visibility in testing

func _ready() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		node.interaction_requested.connect(_on_interaction_requested)

	radial_menu.item_selected.connect(_on_menu_item_selected)
	ensure_debug_actions()
	setup_perf_label()
	load_debug_placed_structures()
	print_testing_help()

func _process(delta: float) -> void:
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

		var slow_pct: float = (100.0 * float(perf_slow_frames)) / max(float(perf_frames), 1.0)
		summary += " | slow_frames: %d (%.1f%%)" % [perf_slow_frames, slow_pct]

		if perf_label != null:
			perf_label.text = summary

		print("[Perf] ", summary)
		perf_elapsed = 0.0
		perf_frames = 0
		perf_slow_frames = 0
		perf_second_frame_ms_samples.clear()

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
	if event.is_action_pressed(DEBUG_SPAWN_ACTION_NAME):
		spawn_debug_server_at_mouse()
	elif event.is_action_pressed(DEBUG_REMOVE_ACTION_NAME):
		remove_last_debug_server()
	elif event.is_action_pressed(DEBUG_STRESS_ACTION_NAME):
		cycle_stress_preset()
	elif event.is_action_pressed(DEBUG_PARITY_ACTION_NAME):
		run_parity_probe()
	elif event.is_action_pressed(DEBUG_TOGGLE_METRICS_ACTION_NAME):
		toggle_thermal_metrics()

func ensure_debug_actions() -> void:
	ensure_action_with_key(DEBUG_SPAWN_ACTION_NAME, DEBUG_SPAWN_KEY)
	ensure_action_with_key(DEBUG_REMOVE_ACTION_NAME, DEBUG_REMOVE_KEY)
	ensure_action_with_key(DEBUG_STRESS_ACTION_NAME, DEBUG_STRESS_KEY)
	ensure_action_with_key(DEBUG_PARITY_ACTION_NAME, DEBUG_PARITY_KEY)
	ensure_action_with_key(DEBUG_TOGGLE_METRICS_ACTION_NAME, DEBUG_TOGGLE_METRICS_KEY)

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

func count_heat_sources() -> int:
	return get_tree().get_nodes_in_group("heat_sources").size()

func print_testing_help() -> void:
	print("[StressHarness] Controls: N=spawn one, M=remove one, ,=cycle stress preset (3/25/50/75), .=run parity probe, /=toggle thermal metrics")
	print("[StressHarness] Current baseline heat sources in scene: ", count_heat_sources())
	print("[StressHarness] Stress presets are additive over existing map sources; only harness-spawned stress servers are cleared each cycle.")

func spawn_debug_server_at_mouse() -> void:
	if SERVER_LEVEL_1_SCENE == null:
		return

	var spawned := SERVER_LEVEL_1_SCENE.instantiate() as Node2D
	if spawned == null:
		return

	spawned.position = get_global_mouse_position()
	add_child(spawned)
	debug_spawned_servers.append(spawned)

	var save_manager := get_save_manager()
	if save_manager != null and save_manager.has_method("add_placed_structure"):
		var structure_id: String = String(save_manager.call(
			"add_placed_structure",
			get_scene_save_key(),
			get_section_save_key(),
			{
				"type": "server_level_1",
				"scene_path": "res://scenes/server/server_level_1.tscn",
				"position": spawned.position,
				"rotation": spawned.rotation,
				"scale": spawned.scale
			}
		))
		if not structure_id.is_empty():
			spawned.set_meta("placed_structure_id", structure_id)

func spawn_debug_server_at_position(world_position: Vector2, persist_structure: bool) -> void:
	if SERVER_LEVEL_1_SCENE == null:
		return

	var spawned := SERVER_LEVEL_1_SCENE.instantiate() as Node2D
	if spawned == null:
		return

	spawned.position = world_position
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
					"type": "server_level_1",
					"scene_path": "res://scenes/server/server_level_1.tscn",
					"position": spawned.position,
					"rotation": spawned.rotation,
					"scale": spawned.scale
				}
			))
			if not structure_id.is_empty():
				spawned.set_meta("placed_structure_id", structure_id)
	else:
		# Stress server: exaggerate heat for better visibility in testing
		spawned.base_heat *= STRESS_SERVER_HEAT_MULTIPLIER
		spawned.heat_per_tps *= STRESS_SERVER_HEAT_MULTIPLIER
		if spawned.has_method("recalculate_heat"):
			spawned.recalculate_heat()
		debug_stress_servers.append(spawned)

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
		spawn_debug_server_at_position(center + offset, false)

	print(
		"[StressHarness] Spawned ", target_count,
		" stress servers at ", center,
		". Active stress servers: ", debug_stress_servers.size(),
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