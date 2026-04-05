extends Node

@export var fallback_map_scene: PackedScene

const DEFAULT_PLAYER_SPAWNS := {
	"res://scenes/maps/serverMap/server_room.tscn": Vector2(960, 540),
	"res://scenes/maps/serverMap/server_room_2.tscn": Vector2(120, 325),
	"res://scenes/maps/serverMap/server_room_3.tscn": Vector2(360, 330),
	"res://scenes/maps/serverMap/server_room_4.tscn": Vector2(360, 330),
}

func _ready() -> void:
	var root := get_parent()
	if root == null:
		return

	var map_container := root.get_node_or_null("Map")
	if map_container == null:
		push_error("MapLoader: missing Map container node")
		return

	for child in map_container.get_children():
		child.queue_free()

	var scene_path := _resolve_map_scene_path()
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		if fallback_map_scene == null:
			push_error("MapLoader: failed to load map scene and no fallback provided")
			return
		packed_scene = fallback_map_scene
		scene_path = fallback_map_scene.resource_path

	var map_instance := packed_scene.instantiate()
	map_container.add_child(map_instance)
	_apply_player_spawn(root, scene_path)

func _resolve_map_scene_path() -> String:
	var requested_path := String(GameManager.current_map_scene_path).strip_edges()
	if requested_path != "":
		return requested_path
	if fallback_map_scene != null:
		return fallback_map_scene.resource_path
	return ""

func _apply_player_spawn(root: Node, scene_path: String) -> void:
	if not DEFAULT_PLAYER_SPAWNS.has(scene_path):
		return

	var player := root.get_node_or_null("Player") as Node2D
	if player == null:
		return

	player.position = DEFAULT_PLAYER_SPAWNS[scene_path]
