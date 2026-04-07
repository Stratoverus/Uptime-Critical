extends Node

@export var default_track_key: String = "Cyberpunk"

var tracks := {
	"Cyberpunk": preload("res://music/vasilyatsevich-brain-implant-cyberpunk-sci-fi-trailer-action-intro-330416.mp3"),
	"Hyperdrive": preload("res://music/the_mountain-game-game-music-508018.mp3"),
	"Lo-Fi": preload("res://music/mondamusic-retro-arcade-game-music-491667.mp3")
}

var current_track: String = ""
var player: AudioStreamPlayer

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.autoplay = false
	add_child(player)

	var saved_track := ""
	if FileAccess.file_exists("user://settings.save"):
		var settings = load_settings()
		saved_track = settings.get("bgm_track", "")

	if saved_track != "" and tracks.has(saved_track):
		play_track(saved_track)
	else:
		play_track(default_track_key)

func play_track(track_name: String) -> void:
	if not tracks.has(track_name):
		return

	player.stop()
	current_track = track_name
	player.stream = tracks[track_name]
	player.play()

func set_track(track_name: String) -> void:
	play_track(track_name)

func get_current_track() -> String:
	return current_track

func load_settings() -> Dictionary:
	var file = FileAccess.open("user://settings.save", FileAccess.READ)
	if file == null:
		return {}

	var text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(text)
	if data is Dictionary:
		return data

	return {}
