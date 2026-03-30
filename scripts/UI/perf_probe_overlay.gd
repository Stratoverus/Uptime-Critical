extends CanvasLayer

@export var toggle_action_name: StringName = &"toggle_perf_probe_overlay"
@export var toggle_key: Key = KEY_F2
@export var start_visible: bool = false
@export var show_probe_readout: bool = true

@onready var perf_label: Label = $Control/PerfLabel
@onready var probe_label: Label = $Control/ProbeLabel

var thermal_system: Node = null
var perf_elapsed: float = 0.0
var perf_frames: int = 0
var perf_recent_fps_samples: PackedFloat32Array = PackedFloat32Array()
var perf_second_frame_ms_samples: PackedFloat32Array = PackedFloat32Array()

const PERF_LOW_WINDOW_SECONDS: float = 10.0
const PERF_LOW_MAX_SAMPLES: int = 900

func _ready() -> void:
	ensure_action_with_key(toggle_action_name, toggle_key)
	set_overlay_visible(start_visible)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action_name):
		set_overlay_visible(not visible)

func _process(delta: float) -> void:
	if not visible:
		return

	if thermal_system == null or not is_instance_valid(thermal_system):
		thermal_system = get_tree().get_first_node_in_group("thermal_system")

	update_performance_summary(delta)
	update_probe_readout()

func set_overlay_visible(overlay_visible: bool) -> void:
	visible = overlay_visible
	if not overlay_visible:
		perf_elapsed = 0.0
		perf_frames = 0
		perf_recent_fps_samples.clear()
		perf_second_frame_ms_samples.clear()

func update_performance_summary(delta: float) -> void:
	perf_elapsed += delta
	perf_frames += 1

	var inst_fps: float = 1.0 / max(delta, 0.0001)
	perf_recent_fps_samples.append(inst_fps)
	perf_second_frame_ms_samples.append(delta * 1000.0)
	trim_perf_low_samples()

	if perf_elapsed < 1.0:
		return

	var avg_fps: float = float(perf_frames) / max(perf_elapsed, 0.001)
	var frame_ms: float = 1000.0 / max(avg_fps, 0.001)
	var one_percent_low: float = compute_one_percent_low_fps()
	var p99_ms: float = compute_percentile_ms(perf_second_frame_ms_samples, 99.0)
	var max_ms: float = compute_max_ms(perf_second_frame_ms_samples)
	var summary: String = "FPS: %s | 1%% low: %s | ms: %s | p99_ms: %s | max_ms: %s | heat_vision: %s | heat_sources: %d" % [
		String.num(avg_fps, 1),
		String.num(one_percent_low, 1),
		String.num(frame_ms, 2),
		String.num(p99_ms, 2),
		String.num(max_ms, 2),
		"ON" if is_heat_vision_enabled() else "OFF",
		count_heat_sources()
	]
	perf_label.text = summary

	perf_elapsed = 0.0
	perf_frames = 0
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

func update_probe_readout() -> void:
	if not show_probe_readout:
		probe_label.text = "Probe: disabled"
		return

	if thermal_system == null or not is_instance_valid(thermal_system) or not thermal_system.has_method("get_probe_at_world_position"):
		probe_label.text = "Probe: thermal probe unavailable"
		return

	var world_pos: Vector2 = get_viewport().get_mouse_position()
	var current_scene := get_tree().current_scene
	if current_scene is Node2D:
		world_pos = (current_scene as Node2D).get_global_mouse_position()
	elif get_viewport().get_camera_2d() != null:
		world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
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

func is_heat_vision_enabled() -> bool:
	if thermal_system == null or not is_instance_valid(thermal_system):
		return false
	var enabled_variant: Variant = thermal_system.get("heat_view_enabled")
	if enabled_variant == null:
		return false
	return bool(enabled_variant)

func count_heat_sources() -> int:
	return get_tree().get_nodes_in_group("heat_sources").size()

func ensure_action_with_key(action_name: StringName, action_key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == action_key:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = action_key
	InputMap.action_add_event(action_name, key_event)
