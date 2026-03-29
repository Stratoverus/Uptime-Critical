extends Node

const HEATMAP_WIDTH: int = 100
const HEATMAP_HEIGHT: int = 56
const AMBIENT_HEAT: float = 0.0
const BASE_FIXED_SIM_TIMESTEP: float = 1.0 / 30.0  # Base deterministic timestep at 30 Hz

@onready var heat_overlay: ColorRect = $HeatVisionCanvas/HeatVisionOverlay
@onready var world_tint: CanvasModulate = $WorldTint

@export var diffusion_rate: float = 4.5
@export var dissipation_rate: float = 0.95
@export var emission_scale: float = 0.12
@export var cooling_capacity_scale: float = 3.2
@export var side_emission_ratio: float = 0.1
@export var back_emission_power: float = 3.2
@export var airflow_decay_per_second: float = 2.4
@export var max_airflow_cells_per_second: float = 3.0
@export var airflow_directional_cone_power: float = 8.0
@export_range(0.0, 1.0, 0.01) var airflow_directional_cutoff: float = 0.35
@export var airflow_exhaust_strength: float = 1.0
@export var airflow_intake_strength: float = 0.55
@export var advection_strength: float = 1.0
@export var heat_spread_multiplier: float = 1.2
@export var airflow_response_multiplier: float = 1.15
@export var enable_activity_regions: bool = true
@export var active_region_guard_cells: int = 6
@export var min_active_region_guard_cells: int = 2
@export var source_count_for_min_guard_cells: int = 160
@export var global_stabilization_interval_seconds: float = 0.75
@export var enable_airflow_overlay: bool = true
@export var use_shader_airflow_overlay: bool = false
@export var airflow_overlay_strength: float = 0.82
@export var airflow_overlay_visual_gain: float = 4.2
@export var airflow_overlay_line_scale: float = 66.0
@export var airflow_overlay_scroll_speed: float = 1.55
@export var airflow_visual_min_scroll_speed: float = 0.8
@export var airflow_visual_max_scroll_speed: float = 1.45
@export var airflow_visual_speed_curve: float = 0.55
@export var airflow_streamline_density: float = 2.2
@export_range(0.02, 0.95, 0.01) var airflow_streamline_thickness: float = 0.46
@export_range(0.0, 1.0, 0.01) var airflow_streamline_jitter: float = 0.05
@export_range(1, 12, 1) var airflow_streamline_samples: int = 6
@export var airflow_streamline_span_cells: float = 1.8
@export var airflow_streamline_dash_repeat: float = 5.2
@export_range(0.08, 0.92, 0.01) var airflow_streamline_dash_duty: float = 0.30
@export var ambient_temperature_celsius: float = 20.0
@export var max_visual_heat: float = 45.0  # Game units (represents ~50°C)
@export var max_visual_heat_celsius: float = 50.0  # What 45 game units represents in Celsius
@export var visual_gain: float = 2.6
@export var max_cell_heat: float = 220.0  # Game units (represents ~60°C)
@export var min_cell_heat: float = -220.0  # Game units
@export var simulation_section_id: StringName = &"default"
@export var clear_saved_thermal_state_on_startup: bool = false
@export var simulation_origin: Vector2 = Vector2.ZERO
@export var simulation_size: Vector2 = Vector2(1920.0, 1280.0)
@export var simulation_size_from_viewport: bool = true
@export var simulation_steps_per_second: float = 20.0
@export var adaptive_simulation_rate: bool = false
@export var high_load_source_threshold: int = 60
@export var high_load_simulation_hz: float = 30.0
@export var texture_updates_per_second: float = 12.0
@export var min_texture_updates_per_second: float = 7.0
@export var adaptive_texture_updates: bool = true
@export var upload_skip_sim_ms_threshold: float = 30.0
@export var airflow_upload_rate_scale_at_max_sources: float = 0.9
@export var source_count_for_min_texture_rate: int = 100
@export var max_sources_processed_per_step: int = 18
@export var min_sources_processed_per_step: int = 8
@export var min_sources_processed_per_step_heat_view: int = 14
@export var enable_time_budgeted_source_processing: bool = true
@export var source_processing_time_budget_ms: float = 2.25
@export var max_source_batch_processing_scale: float = 8.0
@export_range(0.0, 1.0, 0.01) var airflow_batch_compensation: float = 0.35
@export var full_source_processing_cap_for_visuals: int = 12
@export var max_sim_steps_per_frame: int = 1
@export var source_count_for_global_interval_scale: int = 50
@export var global_interval_scale_at_max_sources: float = 2.0
@export var toggle_key: Key = KEY_H
@export var toggle_action_name: StringName = &"toggle_heat_vision"
@export var save_action_name: StringName = &"save_game"
@export var load_action_name: StringName = &"load_game"
@export var save_key: Key = KEY_U
@export var load_key: Key = KEY_I
@export var parity_probe_action_name: StringName = &"run_parity_probe"
@export var parity_probe_key: Key = KEY_P
@export var parity_probe_seconds: float = 1.0
@export var parity_probe_max_steps: int = 40
@export var parity_probe_yield_every_steps: int = 2
@export var heat_source_group: StringName = &"heat_sources"
@export var map_bounds_node_path: NodePath
@export var map_bounds_tile_size_property: StringName = &"tile_size"
@export var map_bounds_tiles_x_property: StringName = &"tiles_x"
@export var map_bounds_tiles_y_property: StringName = &"tiles_y"
@export var enable_thermal_debug_metrics: bool = false
@export var debug_metrics_interval_seconds: float = 1.0
@export_range(0.0, 1.0, 0.01) var airflow_visual_smoothing: float = 0.3
@export_range(0.0, 1.0, 0.01) var airflow_visual_smoothing_min: float = 0.16
@export var airflow_visual_max_delta_per_upload: float = 0.35
@export var stagger_overlay_uploads: bool = true

var heat_view_enabled: bool = false
var viewport_size: Vector2 = Vector2.ZERO
var heat_current: PackedFloat32Array = PackedFloat32Array()
var heat_next: PackedFloat32Array = PackedFloat32Array()
var airflow_x: PackedFloat32Array = PackedFloat32Array()
var airflow_y: PackedFloat32Array = PackedFloat32Array()
var airflow_visual_x: PackedFloat32Array = PackedFloat32Array()
var airflow_visual_y: PackedFloat32Array = PackedFloat32Array()
var heat_image: Image
var heat_texture: ImageTexture
var heat_pixel_data: PackedByteArray = PackedByteArray()
var airflow_image: Image
var airflow_texture: ImageTexture
var airflow_pixel_data: PackedByteArray = PackedByteArray()
var airflow_prev_image: Image
var airflow_prev_texture: ImageTexture
var airflow_prev_pixel_data: PackedByteArray = PackedByteArray()
var simulation_accumulator: float = 0.0
var texture_accumulator: float = 0.0
var current_texture_step: float = 1.0 / 14.0
var heat_sources_dirty: bool = true
var heat_sources_cache: Array[Dictionary] = []
var heat_source_index_by_id: Dictionary = {}
var metrics_elapsed: float = 0.0
var metric_simulation_steps: int = 0
var metric_frames_elapsed: int = 0
var metric_texture_uploads: int = 0
var metric_source_cache_rebuilds: int = 0
var metric_inject_usec: int = 0
var metric_diffuse_usec: int = 0
var metric_texture_usec: int = 0
var metric_overlay_usec: int = 0
var metric_cache_rebuild_usec: int = 0
var metric_advect_usec: int = 0
var metric_global_steps: int = 0
var metric_active_cells_accum: int = 0
var metric_sources_processed: int = 0
var metric_processed_per_step_last: int = 0
var metric_budget_limited_steps: int = 0
var frame_sim_usec: int = 0
var frame_upload_usec: int = 0
var frame_overlay_usec: int = 0
var frame_source_refresh_usec: int = 0
var frame_sim_steps: int = 0
var injection_kernel_cache: Dictionary = {}
var directional_power_lut: PackedFloat32Array = PackedFloat32Array()
var directional_power_lut_size: int = 256
var active_region_valid: bool = false
var active_region_min_x: int = 0
var active_region_min_y: int = 0
var active_region_max_x: int = 0
var active_region_max_y: int = 0
var global_stabilization_accumulator: float = 0.0
var source_batch_cursor: int = 0
var source_processing_ratio_last: float = 1.0
var thermal_signal_present: bool = false
var thermal_signal_scan_accumulator: float = 0.0
var stagger_upload_heat_next: bool = true

const THERMAL_SIGNAL_SCAN_INTERVAL_SECONDS: float = 0.35
const THERMAL_HEAT_SIGNAL_THRESHOLD: float = 0.01
const THERMAL_FLOW_SIGNAL_THRESHOLD: float = 0.02

func _ready() -> void:
	add_to_group("thermal_system")
	ensure_input_actions()
	var tree := get_tree()
	tree.node_added.connect(_on_tree_node_added)
	tree.node_removed.connect(_on_tree_node_removed)
	viewport_size = get_viewport().get_visible_rect().size
	if simulation_size_from_viewport:
		simulation_size = viewport_size
	setup_simulation_bounds_from_map()
	initialize_heat_field()
	if clear_saved_thermal_state_on_startup:
		clear_saved_simulation_state_in_manager()
	var loaded_from_save: bool = try_load_simulation_state()
	set_heat_view_enabled(false)
	if not loaded_from_save:
		simulate_heat_step(1.0 / 60.0)
		upload_overlay_textures()
		update_heat_overlay()

func _exit_tree() -> void:
	var tree := get_tree()
	if tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	if tree.node_removed.is_connected(_on_tree_node_removed):
		tree.node_removed.disconnect(_on_tree_node_removed)

# Convert game heat units to Celsius for display/comparison
func heat_to_celsius(heat_value: float) -> float:
	# Scale: 0 game units = ambient_temperature, max_visual_heat game units = max_visual_heat_celsius
	# For values beyond max_visual_heat, continue scaling proportionally
	var celsius_per_unit: float = (max_visual_heat_celsius - ambient_temperature_celsius) / max_visual_heat
	return ambient_temperature_celsius + (heat_value * celsius_per_unit)

# Convert Celsius to game heat units
func celsius_to_heat(celsius: float) -> float:
	var celsius_per_unit: float = (max_visual_heat_celsius - ambient_temperature_celsius) / max_visual_heat
	return (celsius - ambient_temperature_celsius) / celsius_per_unit

# Get Fahrenheit for reference (optional)
func celsius_to_fahrenheit(celsius: float) -> float:
	return (celsius * 9.0 / 5.0) + 32.0

func get_save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")

func get_simulation_scene_key() -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null and not current_scene.scene_file_path.is_empty():
		return current_scene.scene_file_path
	return str(get_path())

func get_simulation_section_key() -> String:
	if not simulation_section_id.is_empty():
		return String(simulation_section_id)
	return "default"

func try_load_simulation_state() -> bool:
	var save_manager := get_save_manager()
	if save_manager == null:
		return false

	var scene_key: String = get_simulation_scene_key()
	var section_key: String = get_simulation_section_key()
	var loaded_state: Variant = {}
	if save_manager.has_method("load_thermal_section_state"):
		loaded_state = save_manager.call("load_thermal_section_state", scene_key, section_key)
	elif save_manager.has_method("load_thermal_state"):
		loaded_state = save_manager.call("load_thermal_state", scene_key)
	else:
		return false

	if not (loaded_state is Dictionary):
		return false
	if (loaded_state as Dictionary).is_empty():
		return false

	return import_simulation_state(loaded_state)

func save_simulation_state_to_manager() -> void:
	var save_manager := get_save_manager()
	if save_manager == null:
		return

	var scene_key: String = get_simulation_scene_key()
	var section_key: String = get_simulation_section_key()
	if save_manager.has_method("save_thermal_section_state"):
		save_manager.call("save_thermal_section_state", scene_key, section_key, export_simulation_state())
	elif save_manager.has_method("save_thermal_state"):
		save_manager.call("save_thermal_state", scene_key, export_simulation_state())

func clear_saved_simulation_state_in_manager() -> void:
	var save_manager := get_save_manager()
	if save_manager == null:
		return

	var scene_key: String = get_simulation_scene_key()
	var section_key: String = get_simulation_section_key()
	if save_manager.has_method("clear_thermal_section_state"):
		save_manager.call("clear_thermal_section_state", scene_key, section_key)
	elif section_key == "default" and save_manager.has_method("save_thermal_state"):
		save_manager.call("save_thermal_state", scene_key, {})

func notify_structure_placed(structure: Node) -> void:
	if structure == null or not is_instance_valid(structure):
		return

	if structure.is_in_group(heat_source_group):
		if not append_heat_source_to_cache(structure):
			heat_sources_dirty = true
		mark_active_region_from_node(structure)

func notify_structure_removed(structure: Node) -> void:
	if structure == null:
		return

	if structure.is_in_group(heat_source_group):
		if not remove_heat_source_from_cache(structure):
			heat_sources_dirty = true
		# Conservative choice for now: global stabilization catches removal artifacts quickly.
		global_stabilization_accumulator = max(global_stabilization_interval_seconds, 0.05)

func mark_active_region_from_node(structure: Node) -> void:
	if not (structure is Node2D):
		return
	if simulation_size.x <= 0.0 or simulation_size.y <= 0.0:
		return

	var node_2d := structure as Node2D
	var cell_size := Vector2(simulation_size.x / float(HEATMAP_WIDTH), simulation_size.y / float(HEATMAP_HEIGHT))
	var inv_cell_x: float = 1.0 / max(cell_size.x, 0.001)
	var inv_cell_y: float = 1.0 / max(cell_size.y, 0.001)

	var source_pos := node_2d.global_position - simulation_origin
	var source_cell_x := int(clamp(floor(source_pos.x * inv_cell_x), 0.0, float(HEATMAP_WIDTH - 1)))
	var source_cell_y := int(clamp(floor(source_pos.y * inv_cell_y), 0.0, float(HEATMAP_HEIGHT - 1)))

	var radius_pixels: float = max(cell_size.x, cell_size.y)
	if structure.has_method("get_heat_radius"):
		radius_pixels = max(float(structure.call("get_heat_radius")), radius_pixels)

	var radius_x := int(ceil(radius_pixels * inv_cell_x))
	var radius_y := int(ceil(radius_pixels * inv_cell_y))
	mark_active_region(source_cell_x - radius_x, source_cell_y - radius_y, source_cell_x + radius_x, source_cell_y + radius_y)

func _process(delta: float) -> void:
	frame_sim_usec = 0
	frame_upload_usec = 0
	frame_overlay_usec = 0
	frame_source_refresh_usec = 0
	frame_sim_steps = 0

	var current_viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if current_viewport_size != viewport_size:
		viewport_size = current_viewport_size
		if simulation_size_from_viewport:
			simulation_size = viewport_size

	# Fixed timestep: accumulate delta and run as many fixed steps as fit.
	# This ensures simulation runs at a consistent 30 Hz regardless of framerate.
	simulation_accumulator += delta
	var steps_taken: int = 0
	var sim_step: float = get_current_sim_timestep()
	while simulation_accumulator >= sim_step and steps_taken < max_sim_steps_per_frame:
		var sim_start_usec: int = Time.get_ticks_usec()
		simulate_heat_step(sim_step)
		frame_sim_usec += Time.get_ticks_usec() - sim_start_usec
		frame_sim_steps += 1
		simulation_accumulator -= sim_step
		steps_taken += 1

	# Prevent accumulator from growing unbounded (e.g., after a lag spike or pause).
	if simulation_accumulator > sim_step * 4.0:
		simulation_accumulator = sim_step

	if heat_sources_dirty:
		refresh_heat_source_cache()

	thermal_signal_scan_accumulator += delta
	if heat_sources_cache.size() > 0:
		thermal_signal_present = true
	elif thermal_signal_scan_accumulator >= THERMAL_SIGNAL_SCAN_INTERVAL_SECONDS:
		thermal_signal_present = compute_thermal_signal_present()
		thermal_signal_scan_accumulator = 0.0

	if heat_view_enabled:
		if not thermal_signal_present:
			# No texture upload needed while there's no meaningful heat/flow data.
			texture_accumulator = 0.0
		else:
			var effective_texture_rate: float = texture_updates_per_second
			if adaptive_texture_updates and source_count_for_min_texture_rate > 0:
				var source_ratio: float = clamp(float(heat_sources_cache.size()) / float(source_count_for_min_texture_rate), 0.0, 1.0)
				effective_texture_rate = lerp(texture_updates_per_second, min_texture_updates_per_second, source_ratio)
				var upload_scale: float = clamp(airflow_upload_rate_scale_at_max_sources, 0.4, 1.0)
				effective_texture_rate *= lerp(1.0, upload_scale, source_ratio)
				effective_texture_rate = max(effective_texture_rate, min_texture_updates_per_second)

			var texture_step: float = 1.0 / max(effective_texture_rate, 1.0)
			current_texture_step = texture_step
			texture_accumulator += delta
			# Use a strict cadence to avoid bursty uploads that create frame-time spikes.
			if texture_accumulator >= texture_step:
				var frame_sim_ms: float = float(frame_sim_usec) / 1000.0
				var should_upload_now: bool = true
				if frame_sim_steps > 0 and frame_sim_ms > max(upload_skip_sim_ms_threshold, 0.0) and texture_accumulator < texture_step * 1.2:
					# Skip only genuinely heavy sim frames to avoid sim+upload overlap spikes.
					should_upload_now = false

				if should_upload_now:
					var texture_start_usec: int = Time.get_ticks_usec()
					if stagger_overlay_uploads:
						upload_overlay_textures_staggered()
					else:
						upload_overlay_textures()
					var texture_elapsed_usec: int = Time.get_ticks_usec() - texture_start_usec
					frame_upload_usec += texture_elapsed_usec
					if enable_thermal_debug_metrics:
						metric_texture_usec += texture_elapsed_usec
						metric_texture_uploads += 1
					texture_accumulator = max(texture_accumulator - texture_step, 0.0)

		# Keep overlay mapping in sync with camera/player movement every frame.
		var overlay_start_usec: int = Time.get_ticks_usec()
		update_heat_overlay()
		var overlay_elapsed_usec: int = Time.get_ticks_usec() - overlay_start_usec
		frame_overlay_usec += overlay_elapsed_usec
		if enable_thermal_debug_metrics:
			metric_overlay_usec += overlay_elapsed_usec

	if enable_thermal_debug_metrics:
		metrics_elapsed += delta
		metric_frames_elapsed += 1
		if metrics_elapsed >= max(debug_metrics_interval_seconds, 0.1):
			flush_debug_metrics()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action_name):
		set_heat_view_enabled(not heat_view_enabled)
	elif event.is_action_pressed(save_action_name):
		save_simulation_state_to_manager()
		var save_manager := get_save_manager()
		if save_manager != null:
			if save_manager.has_method("save_checkpoint"):
				save_manager.call("save_checkpoint")
			elif save_manager.has_method("flush_pending_changes"):
				save_manager.call("flush_pending_changes")
			elif save_manager.has_method("save_slot"):
				save_manager.call("save_slot")
		print("[ThermalSystem] Saved thermal state for ", get_simulation_scene_key())
	elif event.is_action_pressed(load_action_name):
		var save_manager := get_save_manager()
		if save_manager != null and save_manager.has_method("load_slot"):
			save_manager.call("load_slot")
		if try_load_simulation_state():
			print("[ThermalSystem] Loaded thermal state for ", get_simulation_scene_key())
		else:
			print("[ThermalSystem] No thermal save state found for ", get_simulation_scene_key())
	elif event.is_action_pressed(parity_probe_action_name):
		trigger_parity_probe(parity_probe_seconds)

func get_current_sim_timestep() -> float:
	if adaptive_simulation_rate and high_load_source_threshold > 0 and heat_sources_cache.size() >= high_load_source_threshold:
		return 1.0 / max(high_load_simulation_hz, 1.0)
	return BASE_FIXED_SIM_TIMESTEP

func ensure_input_actions() -> void:
	ensure_action_with_key(toggle_action_name, toggle_key)
	ensure_action_with_key(save_action_name, save_key)
	ensure_action_with_key(load_action_name, load_key)
	ensure_action_with_key(parity_probe_action_name, parity_probe_key)

func ensure_action_with_key(action_name: StringName, action_key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == action_key:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = action_key
	InputMap.action_add_event(action_name, key_event)

func set_heat_view_enabled(enabled: bool) -> void:
	heat_view_enabled = enabled
	heat_overlay.visible = enabled
	world_tint.color = Color(0.55, 0.55, 0.55, 1.0) if enabled else Color(1.0, 1.0, 1.0, 1.0)

	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter("heat_view_enabled", enabled)
	shader_material.set_shader_parameter("thermal_signal_present", thermal_signal_present)
	shader_material.set_shader_parameter("airflow_overlay_enabled", enable_airflow_overlay and use_shader_airflow_overlay)
	shader_material.set_shader_parameter("airflow_overlay_strength", airflow_overlay_strength)
	shader_material.set_shader_parameter("airflow_overlay_visual_gain", airflow_overlay_visual_gain)
	shader_material.set_shader_parameter("airflow_line_scale", airflow_overlay_line_scale)
	shader_material.set_shader_parameter("airflow_scroll_speed", airflow_overlay_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_min_scroll_speed", airflow_visual_min_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_max_scroll_speed", airflow_visual_max_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_speed_curve", airflow_visual_speed_curve)
	shader_material.set_shader_parameter("airflow_streamline_density", airflow_streamline_density)
	shader_material.set_shader_parameter("airflow_streamline_thickness", airflow_streamline_thickness)
	shader_material.set_shader_parameter("airflow_streamline_jitter", airflow_streamline_jitter)
	shader_material.set_shader_parameter("airflow_streamline_samples", airflow_streamline_samples)
	shader_material.set_shader_parameter("airflow_streamline_span_cells", airflow_streamline_span_cells)
	shader_material.set_shader_parameter("airflow_streamline_dash_repeat", airflow_streamline_dash_repeat)
	shader_material.set_shader_parameter("airflow_streamline_dash_duty", airflow_streamline_dash_duty)
	if heat_texture != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)
	if airflow_texture != null:
		shader_material.set_shader_parameter("airflow_texture", airflow_texture)

	if enabled:
		thermal_signal_present = compute_thermal_signal_present() or heat_sources_cache.size() > 0
		upload_overlay_textures()
		update_heat_overlay()
		texture_accumulator = 0.0

	if not enabled:
		texture_accumulator = 0.0

func initialize_heat_field() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	if simulation_size_from_viewport:
		simulation_size = viewport_size
	var total_cells := HEATMAP_WIDTH * HEATMAP_HEIGHT
	heat_current.resize(total_cells)
	heat_next.resize(total_cells)
	airflow_x.resize(total_cells)
	airflow_y.resize(total_cells)
	airflow_visual_x.resize(total_cells)
	airflow_visual_y.resize(total_cells)

	for i in total_cells:
		heat_current[i] = AMBIENT_HEAT
		heat_next[i] = AMBIENT_HEAT
		airflow_x[i] = 0.0
		airflow_y[i] = 0.0
		airflow_visual_x[i] = 0.0
		airflow_visual_y[i] = 0.0

	heat_image = Image.create(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8)
	heat_texture = ImageTexture.create_from_image(heat_image)
	heat_pixel_data.resize(HEATMAP_WIDTH * HEATMAP_HEIGHT * 3)
	airflow_image = Image.create(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8)
	airflow_texture = ImageTexture.create_from_image(airflow_image)
	airflow_pixel_data.resize(HEATMAP_WIDTH * HEATMAP_HEIGHT * 3)
	airflow_prev_image = Image.create(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8)
	airflow_prev_texture = ImageTexture.create_from_image(airflow_prev_image)
	airflow_prev_pixel_data.resize(HEATMAP_WIDTH * HEATMAP_HEIGHT * 3)
	heat_sources_dirty = true
	heat_source_index_by_id.clear()
	source_batch_cursor = 0
	injection_kernel_cache.clear()
	build_directional_power_lut()

	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)
		shader_material.set_shader_parameter("airflow_texture", airflow_texture)
		shader_material.set_shader_parameter("airflow_texture_prev", airflow_prev_texture)

func build_directional_power_lut() -> void:
	directional_power_lut.resize(directional_power_lut_size + 1)
	for i in range(directional_power_lut_size + 1):
		var t: float = float(i) / float(directional_power_lut_size)
		directional_power_lut[i] = pow(t, back_emission_power)

func sample_directional_power(value: float) -> float:
	var clamped: float = clamp(value, 0.0, 1.0)
	var scaled: float = clamped * float(directional_power_lut_size)
	var index: int = int(floor(scaled))
	if index >= directional_power_lut_size:
		return directional_power_lut[directional_power_lut_size]
	var frac: float = scaled - float(index)
	return lerp(directional_power_lut[index], directional_power_lut[index + 1], frac)

func get_injection_kernel(radius_x: int, radius_y: int) -> Dictionary:
	radius_x = max(radius_x, 1)
	radius_y = max(radius_y, 1)
	var key: String = str(radius_x, ":", radius_y)
	if injection_kernel_cache.has(key):
		return injection_kernel_cache[key]

	var offset_x: PackedInt32Array = PackedInt32Array()
	var offset_y: PackedInt32Array = PackedInt32Array()
	var radial_falloff: PackedFloat32Array = PackedFloat32Array()
	var dir_x: PackedFloat32Array = PackedFloat32Array()
	var dir_y: PackedFloat32Array = PackedFloat32Array()

	for dy in range(-radius_y, radius_y + 1):
		for dx in range(-radius_x, radius_x + 1):
			var norm_x: float = float(dx) / float(radius_x)
			var norm_y: float = float(dy) / float(radius_y)
			var dist_sq: float = (norm_x * norm_x) + (norm_y * norm_y)
			if dist_sq > 1.0:
				continue

			var dist: float = sqrt(dist_sq)
			var falloff: float = 1.0 - dist
			falloff *= falloff

			var nx: float = 0.0
			var ny: float = 0.0
			if dist > 0.0001:
				nx = norm_x / dist
				ny = norm_y / dist

			offset_x.append(dx)
			offset_y.append(dy)
			radial_falloff.append(falloff)
			dir_x.append(nx)
			dir_y.append(ny)

	var kernel := {
		"offset_x": offset_x,
		"offset_y": offset_y,
		"radial_falloff": radial_falloff,
		"dir_x": dir_x,
		"dir_y": dir_y
	}
	injection_kernel_cache[key] = kernel
	return kernel

func simulate_heat_step(step: float) -> void:
	if should_skip_simulation_step_when_idle():
		return

	begin_active_region_tracking()
	global_stabilization_accumulator += step

	if enable_thermal_debug_metrics:
		var inject_start_usec: int = Time.get_ticks_usec()
		inject_source_heat(step)
		metric_inject_usec += Time.get_ticks_usec() - inject_start_usec

		var use_global_pass: bool = should_run_global_step()
		if use_global_pass:
			metric_global_steps += 1
			global_stabilization_accumulator = 0.0
		var sim_bounds: Dictionary = get_simulation_bounds(use_global_pass)
		metric_active_cells_accum += int(sim_bounds["cell_count"])

		var advect_start_usec: int = Time.get_ticks_usec()
		advect_heat(step, sim_bounds)
		metric_advect_usec += Time.get_ticks_usec() - advect_start_usec

		var diffuse_start_usec: int = Time.get_ticks_usec()
		diffuse_and_dissipate(step, sim_bounds)
		metric_diffuse_usec += Time.get_ticks_usec() - diffuse_start_usec
		decay_airflow(step, sim_bounds)
		metric_simulation_steps += 1
	else:
		inject_source_heat(step)
		var use_global_pass: bool = should_run_global_step()
		if use_global_pass:
			global_stabilization_accumulator = 0.0
		var sim_bounds: Dictionary = get_simulation_bounds(use_global_pass)
		advect_heat(step, sim_bounds)
		diffuse_and_dissipate(step, sim_bounds)
		decay_airflow(step, sim_bounds)

func should_skip_simulation_step_when_idle() -> bool:
	if heat_sources_dirty:
		refresh_heat_source_cache()

	if not heat_sources_cache.is_empty():
		return false

	# If no sources exist and no residual thermal signal remains, skip costly grid passes.
	if thermal_signal_present:
		return false

	return true

func _on_tree_node_added(node: Node) -> void:
	if node.is_in_group(heat_source_group):
		if not append_heat_source_to_cache(node):
			heat_sources_dirty = true
		mark_active_region_from_node(node)

func _on_tree_node_removed(node: Node) -> void:
	if node.is_in_group(heat_source_group):
		if not remove_heat_source_from_cache(node):
			heat_sources_dirty = true
		global_stabilization_accumulator = max(global_stabilization_interval_seconds, 0.05)

func is_node_valid_heat_source(node: Node) -> bool:
	if not (node is Node2D):
		return false
	if not node.has_method("get_heat_value"):
		return false
	if not node.has_method("get_heat_radius"):
		return false
	return true

func cache_contains_heat_source(source: Node2D) -> bool:
	var source_id: int = source.get_instance_id()
	if not heat_source_index_by_id.has(source_id):
		return false
	var source_index: int = int(heat_source_index_by_id[source_id])
	if source_index < 0 or source_index >= heat_sources_cache.size():
		heat_source_index_by_id.erase(source_id)
		return false
	var cached_node: Variant = heat_sources_cache[source_index].get("node", null)
	if cached_node != source:
		heat_source_index_by_id.erase(source_id)
		return false
	return true

func append_heat_source_to_cache(node: Node) -> bool:
	if not is_node_valid_heat_source(node):
		return false

	var source := node as Node2D
	if cache_contains_heat_source(source):
		return true

	heat_sources_cache.append({
		"node": source,
		"thermal_source": source as ThermalSource,
		"has_back_direction": source.has_method("get_back_direction"),
		"has_intake_direction": source.has_method("get_intake_direction"),
		"has_airflow_rate": source.has_method("get_airflow_rate"),
		"has_cooling_capacity": source.has_method("get_cooling_capacity")
	})
	heat_source_index_by_id[source.get_instance_id()] = heat_sources_cache.size() - 1
	return true

func remove_heat_source_from_cache(node: Node) -> bool:
	if not (node is Node2D):
		return false

	var source := node as Node2D
	var source_id: int = source.get_instance_id()
	if not heat_source_index_by_id.has(source_id):
		return false

	var remove_index: int = int(heat_source_index_by_id[source_id])
	var last_index: int = heat_sources_cache.size() - 1
	if remove_index < 0 or remove_index > last_index:
		heat_source_index_by_id.erase(source_id)
		return false

	if remove_index != last_index:
		var moved_info: Dictionary = heat_sources_cache[last_index]
		heat_sources_cache[remove_index] = moved_info
		var moved_node: Variant = moved_info.get("node", null)
		if moved_node is Node2D and is_instance_valid(moved_node):
			heat_source_index_by_id[moved_node.get_instance_id()] = remove_index

	heat_sources_cache.remove_at(last_index)
	heat_source_index_by_id.erase(source_id)

	if heat_sources_cache.is_empty():
		source_batch_cursor = 0
	else:
		if remove_index < source_batch_cursor:
			source_batch_cursor -= 1
		if source_batch_cursor >= heat_sources_cache.size():
			source_batch_cursor = 0

	return true

func remove_heat_source_from_cache_index(remove_index: int) -> bool:
	var last_index: int = heat_sources_cache.size() - 1
	if remove_index < 0 or remove_index > last_index:
		return false

	var remove_info: Dictionary = heat_sources_cache[remove_index]
	var remove_node: Variant = remove_info.get("node", null)
	if remove_node is Node2D:
		heat_source_index_by_id.erase(remove_node.get_instance_id())

	if remove_index != last_index:
		var moved_info: Dictionary = heat_sources_cache[last_index]
		heat_sources_cache[remove_index] = moved_info
		var moved_node: Variant = moved_info.get("node", null)
		if moved_node is Node2D and is_instance_valid(moved_node):
			heat_source_index_by_id[moved_node.get_instance_id()] = remove_index

	heat_sources_cache.remove_at(last_index)

	if heat_sources_cache.is_empty():
		source_batch_cursor = 0
	else:
		if remove_index < source_batch_cursor:
			source_batch_cursor -= 1
		if source_batch_cursor >= heat_sources_cache.size():
			source_batch_cursor = 0

	return true

func refresh_heat_source_cache() -> void:
	var start_usec: int = Time.get_ticks_usec()

	heat_sources_cache.clear()
	heat_source_index_by_id.clear()
	for node in get_tree().get_nodes_in_group(heat_source_group):
		append_heat_source_to_cache(node)
	if source_batch_cursor >= heat_sources_cache.size():
		source_batch_cursor = 0

	heat_sources_dirty = false
	var refresh_elapsed_usec: int = Time.get_ticks_usec() - start_usec
	frame_source_refresh_usec += refresh_elapsed_usec
	if enable_thermal_debug_metrics:
		metric_source_cache_rebuilds += 1
		metric_cache_rebuild_usec += refresh_elapsed_usec

func flush_debug_metrics() -> void:
	var interval: float = max(metrics_elapsed, 0.001)
	var inject_ms: float = float(metric_inject_usec) / 1000.0
	var diffuse_ms: float = float(metric_diffuse_usec) / 1000.0
	var texture_ms: float = float(metric_texture_usec) / 1000.0
	var overlay_ms: float = float(metric_overlay_usec) / 1000.0
	var cache_ms: float = float(metric_cache_rebuild_usec) / 1000.0
	var advect_ms: float = float(metric_advect_usec) / 1000.0
	var avg_upload_ms: float = 0.0
	if metric_texture_uploads > 0:
		avg_upload_ms = texture_ms / float(metric_texture_uploads)
	var avg_cells: float = 0.0
	if metric_simulation_steps > 0:
		avg_cells = float(metric_active_cells_accum) / float(metric_simulation_steps)

	print(
		"[ThermalMetrics] interval=", String.num(interval, 2), "s",
		" heat_view=", heat_view_enabled,
		" thermal_signal=", thermal_signal_present,
		" sim_hz_target=", String.num(1.0 / max(get_current_sim_timestep(), 0.0001), 1),
		" upload_hz_target=", String.num(1.0 / max(current_texture_step, 0.0001), 1),
		" sources=", heat_sources_cache.size(),
		" processed_sources=", metric_sources_processed,
		" processed_per_step=", metric_processed_per_step_last,
		" sim_steps=", metric_simulation_steps,
		" frames=", metric_frames_elapsed,
		" global_steps=", metric_global_steps,
		" avg_cells=", String.num(avg_cells, 1),
		" uploads=", metric_texture_uploads,
		" cache_rebuilds=", metric_source_cache_rebuilds,
		" budget_limited_steps=", metric_budget_limited_steps,
		" inject_ms=", String.num(inject_ms, 3),
		" advect_ms=", String.num(advect_ms, 3),
		" diffuse_ms=", String.num(diffuse_ms, 3),
		" upload_ms=", String.num(texture_ms, 3),
		" avg_upload_ms=", String.num(avg_upload_ms, 3),
		" overlay_ms=", String.num(overlay_ms, 3),
		" cache_ms=", String.num(cache_ms, 3)
	)

	metrics_elapsed = 0.0
	metric_simulation_steps = 0
	metric_frames_elapsed = 0
	metric_texture_uploads = 0
	metric_source_cache_rebuilds = 0
	metric_inject_usec = 0
	metric_diffuse_usec = 0
	metric_texture_usec = 0
	metric_overlay_usec = 0
	metric_cache_rebuild_usec = 0
	metric_advect_usec = 0
	metric_global_steps = 0
	metric_active_cells_accum = 0
	metric_sources_processed = 0
	metric_processed_per_step_last = 0
	metric_budget_limited_steps = 0

func begin_active_region_tracking() -> void:
	active_region_valid = false
	active_region_min_x = HEATMAP_WIDTH - 1
	active_region_min_y = HEATMAP_HEIGHT - 1
	active_region_max_x = 0
	active_region_max_y = 0

func mark_active_region(x_min: int, y_min: int, x_max: int, y_max: int) -> void:
	if x_max < x_min or y_max < y_min:
		return

	x_min = clamp(x_min, 0, HEATMAP_WIDTH - 1)
	y_min = clamp(y_min, 0, HEATMAP_HEIGHT - 1)
	x_max = clamp(x_max, 0, HEATMAP_WIDTH - 1)
	y_max = clamp(y_max, 0, HEATMAP_HEIGHT - 1)

	if not active_region_valid:
		active_region_valid = true
		active_region_min_x = x_min
		active_region_min_y = y_min
		active_region_max_x = x_max
		active_region_max_y = y_max
		return

	active_region_min_x = min(active_region_min_x, x_min)
	active_region_min_y = min(active_region_min_y, y_min)
	active_region_max_x = max(active_region_max_x, x_max)
	active_region_max_y = max(active_region_max_y, y_max)

func should_run_global_step() -> bool:
	if not enable_activity_regions:
		return true
	var effective_interval: float = max(global_stabilization_interval_seconds, 0.05)
	if source_count_for_global_interval_scale > 0 and global_interval_scale_at_max_sources > 1.0:
		var source_ratio: float = clamp(float(heat_sources_cache.size()) / float(source_count_for_global_interval_scale), 0.0, 1.0)
		effective_interval *= lerp(1.0, global_interval_scale_at_max_sources, source_ratio)
	if global_stabilization_accumulator >= effective_interval:
		return true
	return not active_region_valid

func get_simulation_bounds(global_pass: bool) -> Dictionary:
	if global_pass or not enable_activity_regions or not active_region_valid:
		return {
			"x_min": 0,
			"y_min": 0,
			"x_max": HEATMAP_WIDTH,
			"y_max": HEATMAP_HEIGHT,
			"cell_count": HEATMAP_WIDTH * HEATMAP_HEIGHT
		}

	var guard: int = max(active_region_guard_cells, 0)
	if source_count_for_min_guard_cells > 0 and active_region_guard_cells > min_active_region_guard_cells:
		var guard_ratio: float = clamp(float(heat_sources_cache.size()) / float(source_count_for_min_guard_cells), 0.0, 1.0)
		guard = int(round(lerp(float(active_region_guard_cells), float(min_active_region_guard_cells), guard_ratio)))
		guard = max(guard, min_active_region_guard_cells)
	var x_min: int = max(active_region_min_x - guard, 0)
	var y_min: int = max(active_region_min_y - guard, 0)
	var x_max: int = min(active_region_max_x + guard + 1, HEATMAP_WIDTH)
	var y_max: int = min(active_region_max_y + guard + 1, HEATMAP_HEIGHT)
	var width: int = max(x_max - x_min, 1)
	var height: int = max(y_max - y_min, 1)

	return {
		"x_min": x_min,
		"y_min": y_min,
		"x_max": x_max,
		"y_max": y_max,
		"cell_count": width * height
	}

func inject_source_heat(delta: float) -> void:
	if simulation_size.x <= 0.0 or simulation_size.y <= 0.0:
		return
	if heat_sources_dirty:
		refresh_heat_source_cache()
	if heat_sources_cache.is_empty():
		return

	var cached_source_count: int = heat_sources_cache.size()
	var source_count_to_process: int = cached_source_count
	var adaptive_min_sources: int = max(min_sources_processed_per_step, 1)
	var adaptive_max_sources: int = max(max_sources_processed_per_step, adaptive_min_sources)
	if source_count_for_min_texture_rate > 0:
		var source_ratio: float = clamp(float(cached_source_count) / float(source_count_for_min_texture_rate), 0.0, 1.0)
		source_count_to_process = int(round(lerp(float(adaptive_max_sources), float(adaptive_min_sources), source_ratio)))
		source_count_to_process = clamp(source_count_to_process, adaptive_min_sources, adaptive_max_sources)
	if max_sources_processed_per_step > 0:
		source_count_to_process = min(source_count_to_process, cached_source_count)

	# For moderate source counts, process all sources while heat vision is on.
	# This avoids chunked source batching artifacts that make airflow lines look jittery.
	if heat_view_enabled and full_source_processing_cap_for_visuals > 0 and cached_source_count <= full_source_processing_cap_for_visuals:
		source_count_to_process = cached_source_count
	elif heat_view_enabled and min_sources_processed_per_step_heat_view > 0:
		source_count_to_process = max(source_count_to_process, min(min_sources_processed_per_step_heat_view, cached_source_count))

	if source_count_to_process <= 0:
		return

	if source_batch_cursor >= cached_source_count:
		source_batch_cursor = 0

	var processing_scale: float = float(cached_source_count) / float(source_count_to_process)
	processing_scale = clamp(processing_scale, 1.0, max(max_source_batch_processing_scale, 1.0))
	var airflow_processing_scale: float = lerp(1.0, processing_scale, clamp(airflow_batch_compensation, 0.0, 1.0))
	var processed_count: int = 0
	var budget_limited: bool = false
	var budget_start_usec: int = Time.get_ticks_usec()
	var budget_usec: int = int(max(source_processing_time_budget_ms, 0.0) * 1000.0)

	var cell_size := Vector2(simulation_size.x / float(HEATMAP_WIDTH), simulation_size.y / float(HEATMAP_HEIGHT))
	var inv_cell_x: float = 1.0 / max(cell_size.x, 0.001)
	var inv_cell_y: float = 1.0 / max(cell_size.y, 0.001)
	var min_cell_radius: float = max(cell_size.x, cell_size.y)
	var heat_scale: float = max(heat_spread_multiplier, 0.05)
	var airflow_scale: float = max(airflow_response_multiplier, 0.05)
	var emission_step_scale: float = emission_scale * delta * processing_scale * heat_scale
	var directional_span: float = 1.0 - side_emission_ratio
	var max_flow: float = max(max_airflow_cells_per_second, 0.01)
	var flow_min: float = -max_flow
	var back_power_span: float = directional_span
	var airflow_cone_power: float = max(airflow_directional_cone_power, 1.0)
	var airflow_cutoff: float = clamp(airflow_directional_cutoff, 0.0, 0.95)
	var exhaust_strength: float = max(airflow_exhaust_strength, 0.0)
	var intake_strength: float = max(airflow_intake_strength, 0.0)

	for offset in source_count_to_process:
		if enable_time_budgeted_source_processing and budget_usec > 0 and processed_count > 0:
			if (Time.get_ticks_usec() - budget_start_usec) >= budget_usec:
				budget_limited = true
				break

		var source_index: int = (source_batch_cursor + processed_count) % cached_source_count
		var source_info: Dictionary = heat_sources_cache[source_index]
		var source: Node2D = source_info["node"]
		if source == null or not is_instance_valid(source):
			remove_heat_source_from_cache_index(source_index)
			cached_source_count = heat_sources_cache.size()
			source_count_to_process = min(source_count_to_process, cached_source_count)
			if cached_source_count <= 0 or source_count_to_process <= 0:
				break
			continue

		var source_pos := source.global_position - simulation_origin
		var source_heat: float = 0.0
		var source_airflow_rate: float = 0.0
		var intake_dir := Vector2.LEFT
		var cooling_capacity: float = 0.0
		var radius_pixels: float = min_cell_radius
		var back_dir := Vector2.RIGHT

		var typed_source: ThermalSource = source_info.get("thermal_source", null)
		if typed_source != null and is_instance_valid(typed_source):
			source_heat = typed_source.get_heat_value()
			source_airflow_rate = typed_source.get_airflow_rate()
			intake_dir = typed_source.get_intake_direction().normalized()
			cooling_capacity = typed_source.get_cooling_capacity()
			radius_pixels = max(typed_source.get_heat_radius(), min_cell_radius)
			back_dir = typed_source.get_back_direction().normalized()
		else:
			source_heat = float(source.call("get_heat_value"))
			if source_info["has_airflow_rate"]:
				source_airflow_rate = max(float(source.call("get_airflow_rate")), 0.0)
			if source_info["has_intake_direction"]:
				intake_dir = (source.call("get_intake_direction") as Vector2).normalized()
			if source_info["has_cooling_capacity"]:
				cooling_capacity = max(float(source.call("get_cooling_capacity")), 0.0)
			radius_pixels = max(float(source.call("get_heat_radius")), min_cell_radius)
			if source_info["has_back_direction"]:
				back_dir = (source.call("get_back_direction") as Vector2).normalized()

		if absf(source_heat) <= 0.001 and source_airflow_rate <= 0.001 and cooling_capacity <= 0.001:
			processed_count += 1
			continue

		var radius_x := int(ceil(radius_pixels * inv_cell_x))
		var radius_y := int(ceil(radius_pixels * inv_cell_y))
		radius_x = max(radius_x, 1)
		radius_y = max(radius_y, 1)
		var source_cell_x := int(clamp(floor(source_pos.x * inv_cell_x), 0.0, float(HEATMAP_WIDTH - 1)))
		var source_cell_y := int(clamp(floor(source_pos.y * inv_cell_y), 0.0, float(HEATMAP_HEIGHT - 1)))
		if back_dir.length() < 0.001:
			back_dir = Vector2.RIGHT
		if intake_dir.length() < 0.001:
			intake_dir = -back_dir
		var back_x: float = back_dir.x
		var back_y: float = back_dir.y
		var intake_x: float = intake_dir.x
		var intake_y: float = intake_dir.y

		var airflow_vec_cells := Vector2(back_dir.x * source_airflow_rate * inv_cell_x, back_dir.y * source_airflow_rate * inv_cell_y)
		var intake_vec_cells := Vector2(intake_dir.x * source_airflow_rate * inv_cell_x, intake_dir.y * source_airflow_rate * inv_cell_y)
		airflow_vec_cells = airflow_vec_cells.clamp(Vector2(-max_flow, -max_flow), Vector2(max_flow, max_flow))
		intake_vec_cells = intake_vec_cells.clamp(Vector2(-max_flow, -max_flow), Vector2(max_flow, max_flow))

		var cooling_term: float = 0.0
		if cooling_capacity > 0.0:
			var intake_heat_sample: float = sample_heat_at_world(source_pos + (intake_dir * (radius_pixels * 0.5)), inv_cell_x, inv_cell_y)
			# Cooling should intensify when intake air is hotter, not colder.
			var cooling_boost: float = 1.0 + clamp(intake_heat_sample / max(max_visual_heat, 0.001), 0.0, 0.6)
			# Keep cooling in the same unit scale as heat emission so neither side overwhelms the simulation.
			cooling_term = cooling_capacity * emission_step_scale * cooling_boost * max(cooling_capacity_scale, 0.0)

		var kernel: Dictionary = get_injection_kernel(radius_x, radius_y)
		var kernel_offset_x: PackedInt32Array = kernel["offset_x"]
		var kernel_offset_y: PackedInt32Array = kernel["offset_y"]
		var kernel_falloff: PackedFloat32Array = kernel["radial_falloff"]
		var kernel_dir_x: PackedFloat32Array = kernel["dir_x"]
		var kernel_dir_y: PackedFloat32Array = kernel["dir_y"]

		var emission_strength: float = source_heat * emission_step_scale
		var y_min: int = max(0, source_cell_y - radius_y)
		var y_max: int = min(HEATMAP_HEIGHT, source_cell_y + radius_y + 1)
		var x_min: int = max(0, source_cell_x - radius_x)
		var x_max: int = min(HEATMAP_WIDTH, source_cell_x + radius_x + 1)
		mark_active_region(x_min, y_min, x_max - 1, y_max - 1)

		var net_emission: float = emission_strength - cooling_term
		for k in range(kernel_offset_x.size()):
			var x: int = source_cell_x + kernel_offset_x[k]
			var y: int = source_cell_y + kernel_offset_y[k]
			if x < 0 or x >= HEATMAP_WIDTH or y < 0 or y >= HEATMAP_HEIGHT:
				continue

			var index: int = x + (y * HEATMAP_WIDTH)
			var nx: float = kernel_dir_x[k]
			var ny: float = kernel_dir_y[k]
			var alignment: float = max((back_x * nx) + (back_y * ny), 0.0)
			var intake_alignment: float = max(-((intake_x * nx) + (intake_y * ny)), 0.0)
			var directional_weight: float = side_emission_ratio + (back_power_span * sample_directional_power(alignment))
			var radial_falloff: float = kernel_falloff[k]

			var exhaust_mask: float = 0.0
			if alignment > airflow_cutoff:
				exhaust_mask = pow((alignment - airflow_cutoff) / max(1.0 - airflow_cutoff, 0.001), airflow_cone_power)

			var intake_mask: float = 0.0
			if intake_alignment > airflow_cutoff:
				intake_mask = pow((intake_alignment - airflow_cutoff) / max(1.0 - airflow_cutoff, 0.001), airflow_cone_power)

			var flow_delta_x: float = (airflow_vec_cells.x * exhaust_mask * exhaust_strength) - (intake_vec_cells.x * intake_mask * intake_strength)
			var flow_delta_y: float = (airflow_vec_cells.y * exhaust_mask * exhaust_strength) - (intake_vec_cells.y * intake_mask * intake_strength)
			var updated_flow_x: float = airflow_x[index] + (flow_delta_x * radial_falloff * airflow_processing_scale * airflow_scale)
			var updated_flow_y: float = airflow_y[index] + (flow_delta_y * radial_falloff * airflow_processing_scale * airflow_scale)
			airflow_x[index] = clamp(updated_flow_x, flow_min, max_flow)
			airflow_y[index] = clamp(updated_flow_y, flow_min, max_flow)

			var emitted_heat: float = net_emission * radial_falloff * directional_weight
			heat_current[index] = clamp(heat_current[index] + emitted_heat, min_cell_heat, max_cell_heat)

		processed_count += 1

	if processed_count <= 0:
		return

	metric_sources_processed += processed_count
	metric_processed_per_step_last = processed_count
	source_processing_ratio_last = float(processed_count) / float(max(cached_source_count, 1))
	if budget_limited:
		metric_budget_limited_steps += 1

	source_batch_cursor = (source_batch_cursor + processed_count) % cached_source_count

func advect_heat(delta: float, bounds: Dictionary) -> void:
	var advection_step: float = advection_strength * delta * max(heat_spread_multiplier, 0.05)
	if advection_step <= 0.0:
		return

	var x_min: int = int(bounds["x_min"])
	var y_min: int = int(bounds["y_min"])
	var x_max: int = int(bounds["x_max"])
	var y_max: int = int(bounds["y_max"])

	for y in range(y_min, y_max):
		for x in range(x_min, x_max):
			var index := grid_index(x, y)
			var source_x: float = clamp(float(x) - (airflow_x[index] * advection_step), 0.0, float(HEATMAP_WIDTH - 1))
			var source_y: float = clamp(float(y) - (airflow_y[index] * advection_step), 0.0, float(HEATMAP_HEIGHT - 1))
			heat_next[index] = sample_heat_bilinear(source_x, source_y)

	if x_min > 0 or y_min > 0 or x_max < HEATMAP_WIDTH or y_max < HEATMAP_HEIGHT:
		copy_heat_region_outside_bounds(x_min, y_min, x_max, y_max)

	var swap_buffer := heat_current
	heat_current = heat_next
	heat_next = swap_buffer

func sample_heat_bilinear(cell_x: float, cell_y: float) -> float:
	var x0: int = int(floor(cell_x))
	var y0: int = int(floor(cell_y))
	var x1: int = min(x0 + 1, HEATMAP_WIDTH - 1)
	var y1: int = min(y0 + 1, HEATMAP_HEIGHT - 1)
	var tx: float = cell_x - float(x0)
	var ty: float = cell_y - float(y0)

	var h00: float = heat_current[grid_index(x0, y0)]
	var h10: float = heat_current[grid_index(x1, y0)]
	var h01: float = heat_current[grid_index(x0, y1)]
	var h11: float = heat_current[grid_index(x1, y1)]

	var top: float = lerp(h00, h10, tx)
	var bottom: float = lerp(h01, h11, tx)
	return lerp(top, bottom, ty)

func sample_heat_at_world(world_pos: Vector2, inv_cell_x: float, inv_cell_y: float) -> float:
	var cell_x: float = clamp(world_pos.x * inv_cell_x, 0.0, float(HEATMAP_WIDTH - 1))
	var cell_y: float = clamp(world_pos.y * inv_cell_y, 0.0, float(HEATMAP_HEIGHT - 1))
	return sample_heat_bilinear(cell_x, cell_y)

func sample_airflow_bilinear(cell_x: float, cell_y: float) -> Vector2:
	var x0: int = int(floor(cell_x))
	var y0: int = int(floor(cell_y))
	var x1: int = min(x0 + 1, HEATMAP_WIDTH - 1)
	var y1: int = min(y0 + 1, HEATMAP_HEIGHT - 1)
	var tx: float = cell_x - float(x0)
	var ty: float = cell_y - float(y0)

	var index00: int = grid_index(x0, y0)
	var index10: int = grid_index(x1, y0)
	var index01: int = grid_index(x0, y1)
	var index11: int = grid_index(x1, y1)

	var flow00 := Vector2(airflow_x[index00], airflow_y[index00])
	var flow10 := Vector2(airflow_x[index10], airflow_y[index10])
	var flow01 := Vector2(airflow_x[index01], airflow_y[index01])
	var flow11 := Vector2(airflow_x[index11], airflow_y[index11])

	var top: Vector2 = flow00.lerp(flow10, tx)
	var bottom: Vector2 = flow01.lerp(flow11, tx)
	return top.lerp(bottom, ty)

func world_to_heat_cell(world_position: Vector2) -> Vector2:
	var local_pos: Vector2 = world_position - simulation_origin
	var inv_cell_x: float = float(HEATMAP_WIDTH) / max(simulation_size.x, 0.001)
	var inv_cell_y: float = float(HEATMAP_HEIGHT) / max(simulation_size.y, 0.001)
	var cell_x: float = clamp(local_pos.x * inv_cell_x, 0.0, float(HEATMAP_WIDTH - 1))
	var cell_y: float = clamp(local_pos.y * inv_cell_y, 0.0, float(HEATMAP_HEIGHT - 1))
	return Vector2(cell_x, cell_y)

func get_probe_at_world_position(world_position: Vector2) -> Dictionary:
	var cell: Vector2 = world_to_heat_cell(world_position)
	var heat_value: float = sample_heat_bilinear(cell.x, cell.y)
	var airflow_center: Vector2 = sample_airflow_bilinear(cell.x, cell.y)
	var airflow_xp: Vector2 = sample_airflow_bilinear(min(cell.x + 1.0, float(HEATMAP_WIDTH - 1)), cell.y)
	var airflow_xn: Vector2 = sample_airflow_bilinear(max(cell.x - 1.0, 0.0), cell.y)
	var airflow_yp: Vector2 = sample_airflow_bilinear(cell.x, min(cell.y + 1.0, float(HEATMAP_HEIGHT - 1)))
	var airflow_yn: Vector2 = sample_airflow_bilinear(cell.x, max(cell.y - 1.0, 0.0))
	var airflow_vector: Vector2 = (
		(airflow_center * 0.4)
		+ (airflow_xp * 0.15)
		+ (airflow_xn * 0.15)
		+ (airflow_yp * 0.15)
		+ (airflow_yn * 0.15)
	)
	var strongest_neighbor_vector: Vector2 = airflow_vector
	var strongest_neighbor_strength: float = airflow_vector.length()
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx == 0 and dy == 0:
				continue
			var sample_x: float = clamp(cell.x + float(dx), 0.0, float(HEATMAP_WIDTH - 1))
			var sample_y: float = clamp(cell.y + float(dy), 0.0, float(HEATMAP_HEIGHT - 1))
			var neighbor_flow: Vector2 = sample_airflow_bilinear(sample_x, sample_y)
			var neighbor_strength: float = neighbor_flow.length()
			if neighbor_strength > strongest_neighbor_strength:
				strongest_neighbor_strength = neighbor_strength
				strongest_neighbor_vector = neighbor_flow

	if airflow_vector.length() < 0.00001 and strongest_neighbor_strength > 0.00001:
		airflow_vector = strongest_neighbor_vector
	var airflow_strength: float = airflow_vector.length()
	var airflow_angle_degrees: float = 0.0
	if airflow_strength > 0.000001:
		airflow_angle_degrees = rad_to_deg(airflow_vector.angle())
	var temperature_celsius: float = heat_to_celsius(heat_value)

	return {
		"world_position": world_position,
		"cell_position": cell,
		"heat": heat_value,
		"temperature_celsius": temperature_celsius,
		"airflow": airflow_vector,
		"airflow_direction": airflow_vector,
		"airflow_strength": airflow_strength,
		"airflow_angle_degrees": airflow_angle_degrees
	}

func decay_airflow(delta: float, bounds: Dictionary) -> void:
	var damping: float = exp(-max(airflow_decay_per_second, 0.0) * delta * max(airflow_response_multiplier, 0.05))
	if damping >= 0.9999:
		return

	var x_min: int = int(bounds["x_min"])
	var y_min: int = int(bounds["y_min"])
	var x_max: int = int(bounds["x_max"])
	var y_max: int = int(bounds["y_max"])

	for y in range(y_min, y_max):
		for x in range(x_min, x_max):
			var index := grid_index(x, y)
			airflow_x[index] *= damping
			airflow_y[index] *= damping

func diffuse_and_dissipate(delta: float, bounds: Dictionary) -> void:
	var heat_delta: float = delta * max(heat_spread_multiplier, 0.05)
	var x_min: int = int(bounds["x_min"])
	var y_min: int = int(bounds["y_min"])
	var x_max: int = int(bounds["x_max"])
	var y_max: int = int(bounds["y_max"])

	for y in range(y_min, y_max):
		for x in range(x_min, x_max):
			var index := grid_index(x, y)
			var center := heat_current[index]
			var left := heat_current[grid_index(max(x - 1, 0), y)]
			var right := heat_current[grid_index(min(x + 1, HEATMAP_WIDTH - 1), y)]
			var up := heat_current[grid_index(x, max(y - 1, 0))]
			var down := heat_current[grid_index(x, min(y + 1, HEATMAP_HEIGHT - 1))]
			var laplacian := (left + right + up + down) - (4.0 * center)

			var diffused: float = center + (diffusion_rate * laplacian * heat_delta)
			var cooled: float = diffused - ((diffused - AMBIENT_HEAT) * dissipation_rate * heat_delta)
			heat_next[index] = clamp(cooled, min_cell_heat, max_cell_heat)

	if x_min > 0 or y_min > 0 or x_max < HEATMAP_WIDTH or y_max < HEATMAP_HEIGHT:
		copy_heat_region_outside_bounds(x_min, y_min, x_max, y_max)

	var swap_buffer := heat_current
	heat_current = heat_next
	heat_next = swap_buffer

func copy_heat_region_outside_bounds(x_min: int, y_min: int, x_max: int, y_max: int) -> void:
	for y in HEATMAP_HEIGHT:
		for x in HEATMAP_WIDTH:
			if x >= x_min and x < x_max and y >= y_min and y < y_max:
				continue
			var index := grid_index(x, y)
			heat_next[index] = heat_current[index]

func export_simulation_state() -> Dictionary:
	return {
		"version": 1,
		"width": HEATMAP_WIDTH,
		"height": HEATMAP_HEIGHT,
		"simulation_origin": simulation_origin,
		"simulation_size": simulation_size,
		"heat_current": heat_current,
		"airflow_x": airflow_x,
		"airflow_y": airflow_y
	}

func import_simulation_state(state: Dictionary) -> bool:
	if int(state.get("width", -1)) != HEATMAP_WIDTH:
		return false
	if int(state.get("height", -1)) != HEATMAP_HEIGHT:
		return false

	var imported_heat: Variant = state.get("heat_current", null)
	var imported_airflow_x: Variant = state.get("airflow_x", null)
	var imported_airflow_y: Variant = state.get("airflow_y", null)
	if not (imported_heat is PackedFloat32Array):
		return false
	if not (imported_airflow_x is PackedFloat32Array):
		return false
	if not (imported_airflow_y is PackedFloat32Array):
		return false

	if imported_heat.size() != HEATMAP_WIDTH * HEATMAP_HEIGHT:
		return false
	if imported_airflow_x.size() != HEATMAP_WIDTH * HEATMAP_HEIGHT:
		return false
	if imported_airflow_y.size() != HEATMAP_WIDTH * HEATMAP_HEIGHT:
		return false

	heat_current = imported_heat.duplicate()
	heat_next = heat_current.duplicate()
	airflow_x = imported_airflow_x.duplicate()
	airflow_y = imported_airflow_y.duplicate()
	airflow_visual_x = airflow_x.duplicate()
	airflow_visual_y = airflow_y.duplicate()

	if state.has("simulation_origin"):
		simulation_origin = state["simulation_origin"]
	if state.has("simulation_size"):
		simulation_size = state["simulation_size"]

	upload_overlay_textures()
	update_heat_overlay()
	return true

func trigger_parity_probe(duration_seconds: float = 1.0) -> void:
	print("[ThermalParity] starting probe for ", String.num(duration_seconds, 2), "s")
	var result: Dictionary = await run_parity_probe_async(duration_seconds)
	print("[ThermalParity] completed: ", result)

func run_parity_probe(duration_seconds: float = 1.0) -> Dictionary:
	# Keep sync wrapper for compatibility with external callers.
	return await run_parity_probe_async(duration_seconds)

func run_parity_probe_async(duration_seconds: float = 1.0) -> Dictionary:
	var snapshot: Dictionary = export_simulation_state().duplicate(true)
	var original_enable_activity_regions: bool = enable_activity_regions
	var original_enable_metrics: bool = enable_thermal_debug_metrics
	var original_global_accumulator: float = global_stabilization_accumulator
	var original_simulation_accumulator: float = simulation_accumulator
	var original_texture_accumulator: float = texture_accumulator
	var original_heat_sources_dirty: bool = heat_sources_dirty

	var requested_steps: int = int(max(1.0, round(duration_seconds / max(BASE_FIXED_SIM_TIMESTEP, 0.0001))))
	var steps: int = min(requested_steps, max(parity_probe_max_steps, 1))
	var step_duration: float = BASE_FIXED_SIM_TIMESTEP
	var yield_every: int = max(parity_probe_yield_every_steps, 1)

	enable_thermal_debug_metrics = false
	global_stabilization_accumulator = 0.0
	for i in steps:
		simulate_heat_step(step_duration)
		if (i + 1) % yield_every == 0:
			await get_tree().process_frame

	var optimized_heat: PackedFloat32Array = heat_current.duplicate()
	var optimized_airflow_x: PackedFloat32Array = airflow_x.duplicate()
	var optimized_airflow_y: PackedFloat32Array = airflow_y.duplicate()

	import_simulation_state(snapshot)
	heat_sources_dirty = original_heat_sources_dirty
	global_stabilization_accumulator = 0.0
	enable_activity_regions = false
	for j in steps:
		simulate_heat_step(step_duration)
		if (j + 1) % yield_every == 0:
			await get_tree().process_frame

	var reference_heat: PackedFloat32Array = heat_current.duplicate()
	var reference_airflow_x: PackedFloat32Array = airflow_x.duplicate()
	var reference_airflow_y: PackedFloat32Array = airflow_y.duplicate()

	var heat_abs_sum: float = 0.0
	var heat_max_abs: float = 0.0
	var flow_abs_sum: float = 0.0
	var flow_max_abs: float = 0.0
	for index in optimized_heat.size():
		var heat_diff: float = absf(optimized_heat[index] - reference_heat[index])
		heat_abs_sum += heat_diff
		heat_max_abs = max(heat_max_abs, heat_diff)

		var opt_flow_mag: float = Vector2(optimized_airflow_x[index], optimized_airflow_y[index]).length()
		var ref_flow_mag: float = Vector2(reference_airflow_x[index], reference_airflow_y[index]).length()
		var flow_diff: float = absf(opt_flow_mag - ref_flow_mag)
		flow_abs_sum += flow_diff
		flow_max_abs = max(flow_max_abs, flow_diff)

	var total_cells: int = max(optimized_heat.size(), 1)
	var result: Dictionary = {
		"duration_seconds": duration_seconds,
		"steps": steps,
		"heat_mean_abs_error": heat_abs_sum / float(total_cells),
		"heat_max_abs_error": heat_max_abs,
		"airflow_mean_abs_error": flow_abs_sum / float(total_cells),
		"airflow_max_abs_error": flow_max_abs
	}

	import_simulation_state(snapshot)
	heat_sources_dirty = original_heat_sources_dirty
	enable_activity_regions = original_enable_activity_regions
	enable_thermal_debug_metrics = original_enable_metrics
	global_stabilization_accumulator = original_global_accumulator
	simulation_accumulator = original_simulation_accumulator
	texture_accumulator = original_texture_accumulator

	print(
		"[ThermalParity] duration=", String.num(duration_seconds, 2), "s",
		" steps=", steps,
		" heat_mae=", String.num(float(result["heat_mean_abs_error"]), 5),
		" heat_max=", String.num(float(result["heat_max_abs_error"]), 5),
		" flow_mae=", String.num(float(result["airflow_mean_abs_error"]), 5),
		" flow_max=", String.num(float(result["airflow_max_abs_error"]), 5)
	)

	return result

func upload_overlay_textures() -> void:
	if not thermal_signal_present:
		return
	upload_heat_texture()
	upload_airflow_texture()

func upload_overlay_textures_staggered() -> void:
	if not thermal_signal_present:
		return

	if stagger_upload_heat_next:
		upload_heat_texture()
	else:
		upload_airflow_texture()
	stagger_upload_heat_next = not stagger_upload_heat_next

func upload_heat_texture() -> void:
	if heat_image == null or heat_texture == null:
		return

	var byte_index: int = 0
	for y in HEATMAP_HEIGHT:
		for x in HEATMAP_WIDTH:
			var index := grid_index(x, y)
			var cell_heat: float = heat_current[index]
			var hot_ratio: float = max(cell_heat, 0.0) / max(max_visual_heat, 0.001)
			var cold_ratio: float = max(-cell_heat, 0.0) / max(max_visual_heat, 0.001)
			var hot_byte: int = int(clamp(pow(hot_ratio * visual_gain, 0.8), 0.0, 1.0) * 255.0)
			var cold_byte: int = int(clamp(pow(cold_ratio * visual_gain, 0.8), 0.0, 1.0) * 255.0)
			heat_pixel_data[byte_index] = hot_byte
			heat_pixel_data[byte_index + 1] = cold_byte
			heat_pixel_data[byte_index + 2] = 0
			byte_index += 3

	heat_image.set_data(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8, heat_pixel_data)
	heat_texture.update(heat_image)

func upload_airflow_texture() -> void:
	if airflow_image == null or airflow_texture == null:
		return
	if airflow_prev_image == null or airflow_prev_texture == null:
		return

	if airflow_prev_pixel_data.size() == airflow_pixel_data.size() and airflow_pixel_data.size() > 0:
		airflow_prev_pixel_data = airflow_pixel_data.duplicate()

	var flow_range: float = max(max_airflow_cells_per_second, 0.001)
	var overlay_visual_gain: float = max(airflow_overlay_visual_gain, 0.001)
	var visual_range: float = max(flow_range / overlay_visual_gain, 0.001)
	var visual_smoothing_max: float = clamp(airflow_visual_smoothing, 0.0, 1.0)
	var visual_smoothing_min: float = clamp(airflow_visual_smoothing_min, 0.0, visual_smoothing_max)
	var processing_ratio: float = clamp(source_processing_ratio_last, 0.0, 1.0)
	var visual_smoothing: float = lerp(visual_smoothing_min, visual_smoothing_max, processing_ratio)
	var max_delta: float = max(airflow_visual_max_delta_per_upload, 0.0)
	var byte_index: int = 0
	for y in HEATMAP_HEIGHT:
		for x in HEATMAP_WIDTH:
			var index := grid_index(x, y)
			var target_x: float = airflow_x[index]
			var target_y: float = airflow_y[index]
			if max_delta > 0.0:
				target_x = airflow_visual_x[index] + clamp(target_x - airflow_visual_x[index], -max_delta, max_delta)
				target_y = airflow_visual_y[index] + clamp(target_y - airflow_visual_y[index], -max_delta, max_delta)
			airflow_visual_x[index] = lerp(airflow_visual_x[index], target_x, visual_smoothing)
			airflow_visual_y[index] = lerp(airflow_visual_y[index], target_y, visual_smoothing)
			var flow_x_normalized: float = clamp((airflow_visual_x[index] / visual_range) * 0.5 + 0.5, 0.0, 1.0)
			var flow_y_normalized: float = clamp((airflow_visual_y[index] / visual_range) * 0.5 + 0.5, 0.0, 1.0)
			var magnitude: float = clamp(Vector2(airflow_visual_x[index], airflow_visual_y[index]).length() / visual_range, 0.0, 1.0)
			airflow_pixel_data[byte_index] = int(flow_x_normalized * 255.0)
			airflow_pixel_data[byte_index + 1] = int(flow_y_normalized * 255.0)
			airflow_pixel_data[byte_index + 2] = int(magnitude * 255.0)
			byte_index += 3

	airflow_prev_image.set_data(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8, airflow_prev_pixel_data)
	airflow_prev_texture.update(airflow_prev_image)
	airflow_image.set_data(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8, airflow_pixel_data)
	airflow_texture.update(airflow_image)

func update_heat_overlay() -> void:
	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material == null:
		return

	viewport_size = get_viewport().get_visible_rect().size
	var view_top_left_world: Vector2 = get_view_top_left_world()

	shader_material.set_shader_parameter("heat_view_enabled", heat_view_enabled)
	shader_material.set_shader_parameter("thermal_signal_present", thermal_signal_present)
	shader_material.set_shader_parameter("heat_texel_size", Vector2(1.0 / float(HEATMAP_WIDTH), 1.0 / float(HEATMAP_HEIGHT)))
	shader_material.set_shader_parameter("heat_grid_size", Vector2(float(HEATMAP_WIDTH), float(HEATMAP_HEIGHT)))
	shader_material.set_shader_parameter("viewport_size", viewport_size)
	shader_material.set_shader_parameter("view_world_top_left", view_top_left_world)
	shader_material.set_shader_parameter("simulation_origin", simulation_origin)
	shader_material.set_shader_parameter("simulation_size", simulation_size)
	shader_material.set_shader_parameter("airflow_overlay_enabled", enable_airflow_overlay and use_shader_airflow_overlay)
	shader_material.set_shader_parameter("airflow_overlay_strength", airflow_overlay_strength)
	shader_material.set_shader_parameter("airflow_overlay_visual_gain", airflow_overlay_visual_gain)
	shader_material.set_shader_parameter("airflow_line_scale", airflow_overlay_line_scale)
	shader_material.set_shader_parameter("airflow_scroll_speed", airflow_overlay_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_min_scroll_speed", airflow_visual_min_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_max_scroll_speed", airflow_visual_max_scroll_speed)
	shader_material.set_shader_parameter("airflow_visual_speed_curve", airflow_visual_speed_curve)
	shader_material.set_shader_parameter("airflow_streamline_density", airflow_streamline_density)
	shader_material.set_shader_parameter("airflow_streamline_thickness", airflow_streamline_thickness)
	shader_material.set_shader_parameter("airflow_streamline_jitter", airflow_streamline_jitter)
	shader_material.set_shader_parameter("airflow_streamline_samples", airflow_streamline_samples)
	shader_material.set_shader_parameter("airflow_streamline_span_cells", airflow_streamline_span_cells)
	shader_material.set_shader_parameter("airflow_streamline_dash_repeat", airflow_streamline_dash_repeat)
	shader_material.set_shader_parameter("airflow_streamline_dash_duty", airflow_streamline_dash_duty)
	var upload_blend: float = clamp(texture_accumulator / max(current_texture_step, 0.0001), 0.0, 1.0)
	shader_material.set_shader_parameter("airflow_texture_blend", upload_blend)
	if heat_texture != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)
	if airflow_texture != null:
		shader_material.set_shader_parameter("airflow_texture", airflow_texture)
	if airflow_prev_texture != null:
		shader_material.set_shader_parameter("airflow_texture_prev", airflow_prev_texture)

func get_frame_cost_snapshot() -> Dictionary:
	return {
		"sim_ms": float(frame_sim_usec) / 1000.0,
		"upload_ms": float(frame_upload_usec) / 1000.0,
		"overlay_ms": float(frame_overlay_usec) / 1000.0,
		"source_refresh_ms": float(frame_source_refresh_usec) / 1000.0,
		"sim_steps": frame_sim_steps,
		"processed_per_step": metric_processed_per_step_last,
		"processing_ratio": source_processing_ratio_last
	}

func cell_to_world(cell: Vector2) -> Vector2:
	var cell_size_x: float = simulation_size.x / float(HEATMAP_WIDTH)
	var cell_size_y: float = simulation_size.y / float(HEATMAP_HEIGHT)
	return Vector2(
		simulation_origin.x + ((cell.x + 0.5) * cell_size_x),
		simulation_origin.y + ((cell.y + 0.5) * cell_size_y)
	)

func _hash01(index: int, salt: float) -> float:
	var value: float = sin((float(index) * 12.9898) + salt) * 43758.5453
	return value - floor(value)

func grid_index(x: int, y: int) -> int:
	return x + (y * HEATMAP_WIDTH)

func get_view_top_left_world() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		var zoom: Vector2 = camera.zoom
		var zoom_safe := Vector2(max(zoom.x, 0.001), max(zoom.y, 0.001))
		return camera.get_screen_center_position() - ((viewport_size * 0.5) / zoom_safe)

	var inverse_canvas: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return inverse_canvas * Vector2.ZERO

func setup_simulation_bounds_from_map() -> void:
	var floor_node: Node = null
	if not map_bounds_node_path.is_empty():
		floor_node = get_node_or_null(map_bounds_node_path)

	if floor_node == null:
		var parent_node: Node = get_parent()
		if parent_node != null:
			floor_node = parent_node.get_node_or_null("CheckerboardFloor")

	if floor_node == null:
		return

	var tile_size_variant: Variant = floor_node.get(map_bounds_tile_size_property)
	var tiles_x_variant: Variant = floor_node.get(map_bounds_tiles_x_property)
	var tiles_y_variant: Variant = floor_node.get(map_bounds_tiles_y_property)
	if tile_size_variant == null or tiles_x_variant == null or tiles_y_variant == null:
		return

	var tile_size: float = float(tile_size_variant)
	var tiles_x: float = float(tiles_x_variant)
	var tiles_y: float = float(tiles_y_variant)
	simulation_origin = floor_node.global_position
	if not simulation_size_from_viewport:
		simulation_size = Vector2(tile_size * tiles_x, tile_size * tiles_y)

func compute_thermal_signal_present() -> bool:
	for i in range(heat_current.size()):
		if absf(heat_current[i]) > THERMAL_HEAT_SIGNAL_THRESHOLD:
			return true
		if absf(airflow_x[i]) > THERMAL_FLOW_SIGNAL_THRESHOLD or absf(airflow_y[i]) > THERMAL_FLOW_SIGNAL_THRESHOLD:
			return true
	return false
