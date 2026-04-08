extends Node

@export var default_track_key: String = "Cyberpunk"

const SETTINGS_CONFIG_PATH := "user://settings.cfg"

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
	add_child(player)

	var saved_track := load_saved_bgm_track()

	if tracks.has(saved_track):
		play_track(saved_track)
	else:
		play_track(default_track_key)

func play_track(track_name: String) -> void:
	if not tracks.has(track_name):
		return

	if current_track == track_name and player.playing:
		return

	current_track = track_name
	player.stop()
	player.stream = tracks[track_name]
	player.play()

func set_track(track_name: String) -> void:
	play_track(track_name)

func get_current_track() -> String:
	return current_track

func load_saved_bgm_track() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_CONFIG_PATH) != OK:
		return default_track_key
	return String(cfg.get_value("audio", "bgm_track", default_track_key))