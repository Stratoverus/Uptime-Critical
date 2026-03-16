extends CanvasLayer

# Variables go at the top!
@onready var animation_player = $AnimationPlayer

func _ready() -> void:
	# Ensure the transition starts invisible just in case you 
	# left the ColorRect black in the editor.
	# $ColorRect.modulate.a = 0 
	pass

func change_scene(target_path: String):
	# 1. Play the "fade to black" animation
	animation_player.play("fade_to_black")
	
	# 2. Wait for the animation to finish
	await animation_player.animation_finished
	
	# 3. Change the scene
	get_tree().change_scene_to_file(target_path)
	
	# 4. Play the animation backwards (fade in)
	animation_player.play_backwards("fade_to_black")