extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_continue_button_pressed() -> void:
	print("Continue pressed - Save system not implemented yet!")

func _on_new_game_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/maps/testMap/testMap.tscn")

func _on_settings_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/UI/Settings/SettingsMenu.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()
