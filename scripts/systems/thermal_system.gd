extends Node

const HEATMAP_WIDTH: int = 160
const HEATMAP_HEIGHT: int = 90
const AMBIENT_HEAT: float = 0.0

@onready var heat_overlay: ColorRect = $HeatVisionCanvas/HeatVisionOverlay
@onready var world_tint: CanvasModulate = $WorldTint

@export var diffusion_rate: float = 4.5
@export var dissipation_rate: float = 0.95
@export var emission_scale: float = 0.12
@export var side_emission_ratio: float = 0.1
@export var back_emission_power: float = 3.2
@export var max_visual_heat: float = 45.0
@export var visual_gain: float = 2.6
@export var max_cell_heat: float = 220.0
@export var simulation_origin: Vector2 = Vector2.ZERO
@export var simulation_size: Vector2 = Vector2(1920.0, 1280.0)
@export var simulation_size_from_viewport: bool = true
@export var simulation_steps_per_second: float = 20.0
@export var texture_updates_per_second: float = 20.0
@export var max_sim_steps_per_frame: int = 2
@export var toggle_key: Key = KEY_H

var heat_view_enabled: bool = false
var viewport_size: Vector2 = Vector2.ZERO
var heat_current: PackedFloat32Array = PackedFloat32Array()
var heat_next: PackedFloat32Array = PackedFloat32Array()
var heat_image: Image
var heat_texture: ImageTexture
var simulation_accumulator: float = 0.0
var texture_accumulator: float = 0.0

func _ready() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	if simulation_size_from_viewport:
		simulation_size = viewport_size
	setup_simulation_bounds_from_map()
	initialize_heat_field()
	set_heat_view_enabled(false)
	simulate_heat_step(1.0 / 60.0)
	upload_heat_texture()
	update_heat_overlay()

func _process(delta: float) -> void:
	var current_viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if current_viewport_size != viewport_size:
		viewport_size = current_viewport_size
		if simulation_size_from_viewport:
			simulation_size = viewport_size

	var sim_step: float = 1.0 / max(simulation_steps_per_second, 1.0)
	simulation_accumulator += delta
	var steps_taken: int = 0
	while simulation_accumulator >= sim_step and steps_taken < max_sim_steps_per_frame:
		simulate_heat_step(sim_step)
		simulation_accumulator -= sim_step
		steps_taken += 1

	if simulation_accumulator > sim_step * 4.0:
		simulation_accumulator = sim_step

	if heat_view_enabled:
		var texture_step: float = 1.0 / max(texture_updates_per_second, 1.0)
		texture_accumulator += delta
		if texture_accumulator >= texture_step or (steps_taken > 0 and texture_accumulator >= texture_step * 0.5):
			upload_heat_texture()
			update_heat_overlay()
			texture_accumulator = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		set_heat_view_enabled(not heat_view_enabled)

func set_heat_view_enabled(enabled: bool) -> void:
	heat_view_enabled = enabled
	heat_overlay.visible = enabled
	world_tint.color = Color(0.55, 0.55, 0.55, 1.0) if enabled else Color(1.0, 1.0, 1.0, 1.0)

	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter("heat_view_enabled", enabled)
	if heat_texture != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)

	if enabled:
		upload_heat_texture()
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

	for i in total_cells:
		heat_current[i] = AMBIENT_HEAT
		heat_next[i] = AMBIENT_HEAT

	heat_image = Image.create(HEATMAP_WIDTH, HEATMAP_HEIGHT, false, Image.FORMAT_RGB8)
	heat_texture = ImageTexture.create_from_image(heat_image)

	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)

func simulate_heat_step(step: float) -> void:
	inject_source_heat(step)
	diffuse_and_dissipate(step)

func inject_source_heat(delta: float) -> void:
	if simulation_size.x <= 0.0 or simulation_size.y <= 0.0:
		return

	var cell_size := Vector2(simulation_size.x / float(HEATMAP_WIDTH), simulation_size.y / float(HEATMAP_HEIGHT))

	for node in get_tree().get_nodes_in_group("heat_sources"):
		if not (node is Node2D):
			continue
		if not node.has_method("get_heat_value"):
			continue
		if not node.has_method("get_heat_radius"):
			continue

		var source := node as Node2D
		var source_pos := source.global_position - simulation_origin
		var source_heat: float = max(float(node.get_heat_value()), 0.0)
		if source_heat <= 0.0:
			continue

		var radius_pixels: float = max(float(node.get_heat_radius()), max(cell_size.x, cell_size.y))
		var radius_x := int(ceil(radius_pixels / cell_size.x))
		var radius_y := int(ceil(radius_pixels / cell_size.y))
		var source_cell_x := int(clamp(floor(source_pos.x / cell_size.x), 0.0, float(HEATMAP_WIDTH - 1)))
		var source_cell_y := int(clamp(floor(source_pos.y / cell_size.y), 0.0, float(HEATMAP_HEIGHT - 1)))
		var back_dir := Vector2.RIGHT
		if node.has_method("get_back_direction"):
			back_dir = node.get_back_direction().normalized()

		for y in range(max(0, source_cell_y - radius_y), min(HEATMAP_HEIGHT, source_cell_y + radius_y + 1)):
			for x in range(max(0, source_cell_x - radius_x), min(HEATMAP_WIDTH, source_cell_x + radius_x + 1)):
				var cell_center := Vector2((x + 0.5) * cell_size.x, (y + 0.5) * cell_size.y)
				var to_cell := cell_center - source_pos
				var distance_to_cell := to_cell.length()
				if distance_to_cell > radius_pixels:
					continue

				var direction := Vector2.ZERO
				if distance_to_cell > 0.001:
					direction = to_cell / distance_to_cell

				var alignment: float = max(back_dir.dot(direction), 0.0)
				var directional_weight: float = side_emission_ratio + ((1.0 - side_emission_ratio) * pow(alignment, back_emission_power))
				var radial_falloff: float = 1.0 - (distance_to_cell / radius_pixels)
				radial_falloff *= radial_falloff

				var emitted_heat: float = source_heat * emission_scale * delta * radial_falloff * directional_weight
				var next_heat: float = heat_current[grid_index(x, y)] + emitted_heat
				heat_current[grid_index(x, y)] = min(next_heat, max_cell_heat)

func diffuse_and_dissipate(delta: float) -> void:
	for y in HEATMAP_HEIGHT:
		for x in HEATMAP_WIDTH:
			var index := grid_index(x, y)
			var center := heat_current[index]
			var left := heat_current[grid_index(max(x - 1, 0), y)]
			var right := heat_current[grid_index(min(x + 1, HEATMAP_WIDTH - 1), y)]
			var up := heat_current[grid_index(x, max(y - 1, 0))]
			var down := heat_current[grid_index(x, min(y + 1, HEATMAP_HEIGHT - 1))]
			var laplacian := (left + right + up + down) - (4.0 * center)

			var diffused: float = center + (diffusion_rate * laplacian * delta)
			var cooled: float = diffused - ((diffused - AMBIENT_HEAT) * dissipation_rate * delta)
			heat_next[index] = clamp(cooled, AMBIENT_HEAT, max_cell_heat)

	var swap_buffer := heat_current
	heat_current = heat_next
	heat_next = swap_buffer

func upload_heat_texture() -> void:
	if heat_image == null or heat_texture == null:
		return

	for y in HEATMAP_HEIGHT:
		for x in HEATMAP_WIDTH:
			var index := grid_index(x, y)
			var heat_ratio: float = heat_current[index] / max(max_visual_heat, 0.001)
			var boosted_heat: float = pow(heat_ratio * visual_gain, 0.8)
			var hot_normalized: float = clamp(boosted_heat, 0.0, 1.0)
			heat_image.set_pixel(x, y, Color(hot_normalized, 0.0, 0.0, 1.0))

	heat_texture.update(heat_image)

func update_heat_overlay() -> void:
	var shader_material := heat_overlay.material as ShaderMaterial
	if shader_material == null:
		return

	viewport_size = get_viewport().get_visible_rect().size
	var view_top_left_world: Vector2 = get_view_top_left_world()

	shader_material.set_shader_parameter("heat_view_enabled", heat_view_enabled)
	shader_material.set_shader_parameter("heat_texel_size", Vector2(1.0 / float(HEATMAP_WIDTH), 1.0 / float(HEATMAP_HEIGHT)))
	shader_material.set_shader_parameter("viewport_size", viewport_size)
	shader_material.set_shader_parameter("view_world_top_left", view_top_left_world)
	shader_material.set_shader_parameter("simulation_origin", simulation_origin)
	shader_material.set_shader_parameter("simulation_size", simulation_size)
	if heat_texture != null:
		shader_material.set_shader_parameter("heat_texture", heat_texture)

func grid_index(x: int, y: int) -> int:
	return x + (y * HEATMAP_WIDTH)

func get_view_top_left_world() -> Vector2:
	var inverse_canvas: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return inverse_canvas * Vector2.ZERO

func setup_simulation_bounds_from_map() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var floor_node: Node = parent_node.get_node_or_null("CheckerboardFloor")
	if floor_node == null:
		return

	var tile_size_variant: Variant = floor_node.get("tile_size")
	var tiles_x_variant: Variant = floor_node.get("tiles_x")
	var tiles_y_variant: Variant = floor_node.get("tiles_y")
	if tile_size_variant == null or tiles_x_variant == null or tiles_y_variant == null:
		return

	var tile_size: float = float(tile_size_variant)
	var tiles_x: float = float(tiles_x_variant)
	var tiles_y: float = float(tiles_y_variant)
	simulation_origin = floor_node.global_position
	if not simulation_size_from_viewport:
		simulation_size = Vector2(tile_size * tiles_x, tile_size * tiles_y)
