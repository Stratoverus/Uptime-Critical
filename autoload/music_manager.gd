extends Node

@export var default_track_key: String = "Cyberpunk"

var tracks := {
	"Sci-Fi": preload("res://music/rockot-futuristic-sci-fi-268233.mp3"),
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

	play_track(default_track_key)

func play_track(track_name: String) -> void:
	if not tracks.has(track_name):
		return

	if current_track == track_name and player.playing:
		return

	current_track = track_name
	player.stop()
	player.stream = tracks[track_name]
	_ensure_stream_loops(player.stream)
	player.play()

func set_track(track_name: String) -> void:
	play_track(track_name)

func get_current_track() -> String:
	return current_track

func _ensure_stream_loops(stream: AudioStream) -> void:
	if stream == null:
		return

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD