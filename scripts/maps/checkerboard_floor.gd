@tool
extends Node2D

@export var tile_size: int = 64:
	set(value):
		tile_size = max(value, 8)
		queue_redraw()

@export var tiles_x: int = 30:
	set(value):
		tiles_x = max(value, 2)
		queue_redraw()

@export var tiles_y: int = 20:
	set(value):
		tiles_y = max(value, 2)
		queue_redraw()

@export var light_color: Color = Color("d8d2b8"):
	set(value):
		light_color = value
		queue_redraw()

@export var dark_color: Color = Color("b0a789"):
	set(value):
		dark_color = value
		queue_redraw()

func _draw() -> void:
	var origin := Vector2.ZERO

	for y in tiles_y:
		for x in tiles_x:
			var color := light_color if (x + y) % 2 == 0 else dark_color
			var position := origin + Vector2(x * tile_size, y * tile_size)
			draw_rect(Rect2(position, Vector2(tile_size, tile_size)), color, true)
