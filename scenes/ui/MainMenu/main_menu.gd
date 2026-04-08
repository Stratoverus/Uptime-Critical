extends Control

const MAP_ROOT_DIR := "res://scenes/maps"
const MAP_LEVEL_SCENE := "res://scenes/maps/serverMap/server_room_level.tscn"
const SETTINGS_CONFIG_PATH := "user://settings.cfg"
const SETTINGS_VERSION := 2

@onready var main_menu_buttons: VBoxContainer = $CenterContainer/VBoxContainer/VBoxContainer2
@onready var continue_button: Button = $CenterContainer/VBoxContainer/VBoxContainer2/ContinueButton
@onready var settings_panel: PanelContainer = $CenterContainer/VBoxContainer/SettingsPanel
@onready var fps_label: Label = $FpsLabel
@onready var map_select_popup: PopupPanel = $MapSelectPopup
@onready var map_list: VBoxContainer = $MapSelectPopup/MarginContainer/PopupVBox/MapScroll/MapList
@onready var master_slider: HSlider = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/MasterRow/MasterSlider
@onready var master_value_label: Label = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/MasterRow/MasterValue
@onready var music_slider: HSlider = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/MusicRow/MusicSlider
@onready var music_value_label: Label = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/MusicRow/MusicValue
@onready var sfx_slider: HSlider = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/SfxRow/SfxSlider
@onready var sfx_value_label: Label = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/SfxRow/SfxValue
@onready var fullscreen_toggle_button: Button = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/FullscreenRow/FullscreenToggleButton
@onready var vsync_toggle_button: Button = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/VsyncRow/VsyncToggleButton
@onready var fps_toggle_button: Button = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/FpsRow/FpsToggleButton
@onready var save_settings_button: Button = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/BottomButtons/SaveSettingsButton
@onready var settings_status_label: Label = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/SettingsStatusLabel
@onready var bgm_option_button: OptionButton = $CenterContainer/VBoxContainer/SettingsPanel/MarginContainer/SettingsVBox/BGMRow/BgmOptionButton

var bgm_tracks := {
	"Cyberpunk": preload("res://music/vasilyatsevich-brain-implant-cyberpunk-sci-fi-trailer-action-intro-330416.mp3"),
	"Hyperdrive": preload("res://music/the_mountain-game-game-music-508018.mp3"),
	"Lo-Fi": preload("res://music/mondamusic-retro-arcade-game-music-491667.mp3")
}
var available_maps: Array[Dictionary] = []
var settings_state: Dictionary = {
	"master_volume": 30.0,
	"music_volume": 30.0,
	"sfx_volume": 30.0,
	"fullscreen": true,
	"vsync": true,
	"show_fps": false,
}
var is_syncing_settings_ui: bool = false
var has_unsaved_settings: bool = false
var load_slot_popup: PopupPanel = null
var load_slot_list: VBoxContainer = null
var delete_save_confirm_dialog: ConfirmationDialog = null
var pending_delete_slot_name: String = ""
var pending_delete_display_label: String = ""
var pending_delete_keep_popup_open: bool = false
var pending_delete_slot_count_before: int = 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_connect_settings_signals()
	var loaded_existing_settings: bool = _load_settings()
	if not loaded_existing_settings:
		_save_settings()
	_sync_settings_ui_from_state()
	_apply_settings_runtime()
	await _refresh_map_selection_ui()
	_ensure_load_slot_popup()
	_ensure_delete_save_confirm_dialog()
	_refresh_continue_button_state()
	_populate_bgm_options()
	_select_option_by_text(bgm_option_button, settings_state["bgm_track"])
	_apply_music_track(settings_state["bgm_track"])
	bgm_option_button.item_selected.connect(_on_bgm_option_selected)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _on_continue_button_pressed() -> void:
	_refresh_continue_button_state()
	_show_continue_slot_popup()

func _on_new_game_button_pressed() -> void:
	if available_maps.is_empty():
		await _refresh_map_selection_ui()

	if available_maps.is_empty():
		push_warning("No map scenes matching server_room_<number>.tscn were found.")
		return

	map_select_popup.popup_centered()

func _on_close_map_popup_button_pressed() -> void:
	map_select_popup.hide()

func _on_settings_button_pressed() -> void:
	map_select_popup.hide()
	main_menu_buttons.visible = false
	settings_panel.visible = true
	if has_unsaved_settings:
		settings_status_label.visible = true
		settings_status_label.text = "Unsaved changes"
	else:
		settings_status_label.visible = false

func _on_settings_back_button_pressed() -> void:
	settings_panel.visible = false
	main_menu_buttons.visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _connect_settings_signals() -> void:
	master_slider.value_changed.connect(_on_master_slider_value_changed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	fullscreen_toggle_button.toggled.connect(_on_fullscreen_toggled)
	vsync_toggle_button.toggled.connect(_on_vsync_toggled)
	fps_toggle_button.toggled.connect(_on_show_fps_toggled)
	save_settings_button.pressed.connect(_on_save_settings_button_pressed)

func _load_settings() -> bool:
	var cfg := ConfigFile.new()
	var load_err: Error = cfg.load(SETTINGS_CONFIG_PATH)
	if load_err != OK:
		return false

	settings_state["master_volume"] = float(cfg.get_value("audio", "master_volume", settings_state["master_volume"]))
	settings_state["music_volume"] = float(cfg.get_value("audio", "music_volume", settings_state["music_volume"]))
	settings_state["sfx_volume"] = float(cfg.get_value("audio", "sfx_volume", settings_state["sfx_volume"]))
	settings_state["fullscreen"] = bool(cfg.get_value("display", "fullscreen", settings_state["fullscreen"]))
	settings_state["vsync"] = bool(cfg.get_value("display", "vsync", settings_state["vsync"]))
	settings_state["show_fps"] = bool(cfg.get_value("display", "show_fps", settings_state["show_fps"]))
	settings_state["bgm_track"] = cfg.get_value("audio", "bgm_track", "Default")

	var settings_version: int = int(cfg.get_value("meta", "settings_version", 0))
	if settings_version < SETTINGS_VERSION:
		# Migration: make VSync enabled by default for older settings files.
		settings_state["vsync"] = true
	return true

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "settings_version", SETTINGS_VERSION)
	cfg.set_value("audio", "master_volume", settings_state["master_volume"])
	cfg.set_value("audio", "music_volume", settings_state["music_volume"])
	cfg.set_value("audio", "sfx_volume", settings_state["sfx_volume"])
	cfg.set_value("display", "fullscreen", settings_state["fullscreen"])
	cfg.set_value("display", "vsync", settings_state["vsync"])
	cfg.set_value("display", "show_fps", settings_state["show_fps"])
	cfg.set_value("audio", "bgm_track", settings_state["bgm_track"])
	var save_err: Error = cfg.save(SETTINGS_CONFIG_PATH)
	if save_err != OK:
		push_warning("Failed to save settings to " + SETTINGS_CONFIG_PATH)
		settings_status_label.text = "Save failed"
		return

	has_unsaved_settings = false
	save_settings_button.disabled = true
	settings_status_label.visible = true
	settings_status_label.text = "Changes saved"

func _sync_settings_ui_from_state() -> void:
	is_syncing_settings_ui = true

	master_slider.value = clamp(float(settings_state["master_volume"]), 0.0, 100.0)
	music_slider.value = clamp(float(settings_state["music_volume"]), 0.0, 100.0)
	sfx_slider.value = clamp(float(settings_state["sfx_volume"]), 0.0, 100.0)
	_set_toggle_button_state(fullscreen_toggle_button, bool(settings_state["fullscreen"]))
	_set_toggle_button_state(vsync_toggle_button, bool(settings_state["vsync"]))
	_set_toggle_button_state(fps_toggle_button, bool(settings_state["show_fps"]))
	_update_volume_value_labels()
	has_unsaved_settings = false
	save_settings_button.disabled = true
	settings_status_label.visible = false

	is_syncing_settings_ui = false

func _apply_settings_runtime() -> void:
	_apply_audio_settings()
	_apply_display_settings()

func _apply_audio_settings() -> void:
	_apply_bus_volume_percent(&"Master", float(settings_state["master_volume"]))
	_apply_bus_volume_percent(&"Music", float(settings_state["music_volume"]))
	_apply_bus_volume_percent(&"SoundEffects", float(settings_state["sfx_volume"]))

func _apply_bus_volume_percent(bus_name: StringName, percent: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return

	var normalized: float = clamp(percent / 100.0, 0.0, 1.0)
	if normalized <= 0.0001:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		return

	AudioServer.set_bus_volume_db(bus_index, linear_to_db(normalized))

func _apply_display_settings() -> void:
	var fullscreen_enabled: bool = bool(settings_state["fullscreen"])
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var vsync_enabled: bool = bool(settings_state["vsync"])
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	fps_label.visible = bool(settings_state["show_fps"])

func _update_volume_value_labels() -> void:
	master_value_label.text = "%d%%" % int(round(master_slider.value))
	music_value_label.text = "%d%%" % int(round(music_slider.value))
	sfx_value_label.text = "%d%%" % int(round(sfx_slider.value))

func _on_master_slider_value_changed(value: float) -> void:
	if is_syncing_settings_ui:
		return
	settings_state["master_volume"] = value
	_update_volume_value_labels()
	_apply_audio_settings()
	_mark_settings_dirty()

func _on_music_slider_value_changed(value: float) -> void:
	if is_syncing_settings_ui:
		return
	settings_state["music_volume"] = value
	_update_volume_value_labels()
	_apply_audio_settings()
	_mark_settings_dirty()

func _on_sfx_slider_value_changed(value: float) -> void:
	if is_syncing_settings_ui:
		return
	settings_state["sfx_volume"] = value
	_update_volume_value_labels()
	_apply_audio_settings()
	_mark_settings_dirty()

func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if is_syncing_settings_ui:
		return
	var is_enabled: bool = not button_pressed
	settings_state["fullscreen"] = is_enabled
	_set_toggle_button_state(fullscreen_toggle_button, is_enabled)
	_apply_display_settings()
	_mark_settings_dirty()

func _on_vsync_toggled(button_pressed: bool) -> void:
	if is_syncing_settings_ui:
		return
	var is_enabled: bool = not button_pressed
	settings_state["vsync"] = is_enabled
	_set_toggle_button_state(vsync_toggle_button, is_enabled)
	_apply_display_settings()
	_mark_settings_dirty()

func _on_show_fps_toggled(button_pressed: bool) -> void:
	if is_syncing_settings_ui:
		return
	var is_enabled: bool = not button_pressed
	settings_state["show_fps"] = is_enabled
	_set_toggle_button_state(fps_toggle_button, is_enabled)
	_apply_display_settings()
	_mark_settings_dirty()

func _set_toggle_button_state(toggle_button: Button, is_enabled: bool) -> void:
	# Theme draws pressed as darker; invert visual press so enabled appears highlighted.
	toggle_button.button_pressed = not is_enabled
	toggle_button.text = "Enabled" if is_enabled else "Disabled"

func _mark_settings_dirty() -> void:
	has_unsaved_settings = true
	save_settings_button.disabled = false
	settings_status_label.visible = true
	settings_status_label.text = "Unsaved changes"

func _on_save_settings_button_pressed() -> void:
	_save_settings()

func _refresh_map_selection_ui() -> void:
	available_maps = _discover_available_maps()

	for child in map_list.get_children():
		child.queue_free()

	if available_maps.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No maps found in " + MAP_ROOT_DIR
		map_list.add_child(empty_label)
		return

	for map_data in available_maps:
		var map_number: int = map_data["number"]
		var map_path: String = map_data["path"]
		var button := Button.new()
		button.text = "Map %d" % map_number
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 300)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE

		var style_normal := StyleBoxFlat.new()
		style_normal.bg_color = Color(0.08, 0.10, 0.12, 0.95)
		style_normal.border_width_left = 2
		style_normal.border_width_top = 2
		style_normal.border_width_right = 2
		style_normal.border_width_bottom = 2
		style_normal.content_margin_left = 2.0
		style_normal.content_margin_top = 2.0
		style_normal.content_margin_right = 2.0
		style_normal.content_margin_bottom = 2.0
		style_normal.border_color = Color(0.20, 0.27, 0.30, 1.0)
		style_normal.corner_radius_top_left = 8
		style_normal.corner_radius_top_right = 8
		style_normal.corner_radius_bottom_right = 8
		style_normal.corner_radius_bottom_left = 8

		var style_hover := style_normal.duplicate() as StyleBoxFlat
		style_hover.border_color = Color(0.45, 0.83, 0.48, 1.0)
		style_hover.shadow_size = 10
		style_hover.shadow_color = Color(0.20, 0.80, 0.30, 0.55)

		button.add_theme_stylebox_override("normal", style_normal)
		button.add_theme_stylebox_override("hover", style_hover)
		button.add_theme_stylebox_override("focus", style_hover)
		button.add_theme_stylebox_override("pressed", style_hover)

		button.icon = await _create_map_preview_texture(map_path)
		button.pressed.connect(_on_map_selected.bind(map_path))
		map_list.add_child(button)

func _discover_available_maps() -> Array[Dictionary]:
	var map_entries: Array[Dictionary] = []
	var regex := RegEx.new()
	regex.compile("^server_room_(\\d+)\\.tscn$")

	_scan_maps_recursive(MAP_ROOT_DIR, regex, map_entries)
	map_entries.sort_custom(_sort_map_entries)
	return map_entries

func _scan_maps_recursive(dir_path: String, regex: RegEx, output: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry_name := dir.get_next()
		if entry_name == "":
			break
		if entry_name == "." or entry_name == "..":
			continue

		var full_path := "%s/%s" % [dir_path, entry_name]
		if dir.current_is_dir():
			_scan_maps_recursive(full_path, regex, output)
			continue

		var match := regex.search(entry_name)
		if match == null:
			continue

		output.append({
			"number": int(match.get_string(1)),
			"path": full_path,
		})

	dir.list_dir_end()

func _sort_map_entries(a: Dictionary, b: Dictionary) -> bool:
	return int(a["number"]) < int(b["number"])

func _on_map_selected(map_scene_path: String) -> void:
	if SaveManager != null and SaveManager.has_method("start_new_runtime_slot"):
		SaveManager.start_new_runtime_slot("", "New Game")
	elif SaveManager != null and SaveManager.has_method("create_new_slot"):
		SaveManager.create_new_slot("", "New Game")
	if GameManager != null and GameManager.has_method("reset_runtime_state"):
		GameManager.reset_runtime_state(map_scene_path)
	GameManager.current_map_scene_path = map_scene_path
	map_select_popup.hide()
	SceneTransition.change_scene(MAP_LEVEL_SCENE)

func _refresh_continue_button_state() -> void:
	if continue_button == null:
		return
	if SaveManager == null or not SaveManager.has_method("list_slots"):
		continue_button.disabled = true
		return

	var slots: Array = SaveManager.list_slots()
	continue_button.disabled = slots.is_empty()

func _ensure_load_slot_popup() -> void:
	if load_slot_popup != null and is_instance_valid(load_slot_popup):
		return

	load_slot_popup = PopupPanel.new()
	load_slot_popup.name = "LoadSlotPopup"
	load_slot_popup.size = Vector2i(760, 520)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	load_slot_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Select Save File"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	load_slot_list = VBoxContainer.new()
	load_slot_list.add_theme_constant_override("separation", 8)
	load_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(load_slot_list)

	var close_button := Button.new()
	close_button.text = "Back"
	close_button.pressed.connect(func() -> void:
		load_slot_popup.hide()
	)
	root.add_child(close_button)

	add_child(load_slot_popup)

func _show_continue_slot_popup() -> void:
	_ensure_load_slot_popup()
	_ensure_delete_save_confirm_dialog()
	_refresh_load_slot_popup()
	if load_slot_popup != null:
		load_slot_popup.popup_centered()

func _ensure_delete_save_confirm_dialog() -> void:
	if delete_save_confirm_dialog != null and is_instance_valid(delete_save_confirm_dialog):
		return

	delete_save_confirm_dialog = ConfirmationDialog.new()
	delete_save_confirm_dialog.title = "Delete Save File"
	delete_save_confirm_dialog.dialog_text = "Delete this save file permanently?"
	delete_save_confirm_dialog.size = Vector2(460, 170)
	delete_save_confirm_dialog.confirmed.connect(_on_menu_delete_confirmed)
	delete_save_confirm_dialog.canceled.connect(func() -> void:
		pending_delete_slot_name = ""
		pending_delete_display_label = ""
	)
	delete_save_confirm_dialog.get_ok_button().text = "Delete"
	add_child(delete_save_confirm_dialog)

func _refresh_load_slot_popup() -> void:
	if load_slot_list == null:
		return

	for child in load_slot_list.get_children():
		child.queue_free()

	if SaveManager == null or not SaveManager.has_method("list_slots"):
		return

	var slots: Array = SaveManager.list_slots()
	if slots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No save files found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		load_slot_list.add_child(empty_label)
		return

	for slot_variant in slots:
		if not (slot_variant is Dictionary):
			continue
		var slot_entry := slot_variant as Dictionary
		var slot_name: String = String(slot_entry.get("slot_name", ""))
		var display_label: String = String(slot_entry.get("display_label", slot_name))
		var updated_unix: int = int(slot_entry.get("updated_unix", 0))
		var day_value: int = int(slot_entry.get("day", 0))
		var money_value: float = float(slot_entry.get("money", 0.0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 56)

		var info_label := Label.new()
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var updated_text := ""
		if updated_unix > 0:
			updated_text = Time.get_datetime_string_from_unix_time(updated_unix, true)
		info_label.text = "%s | %s | Day %d | $%.2f" % [display_label, updated_text, day_value, money_value]
		row.add_child(info_label)

		var load_button := Button.new()
		load_button.text = "Load"
		load_button.custom_minimum_size = Vector2(86, 50)
		load_button.pressed.connect(func() -> void:
			_load_selected_slot(slot_name)
		)
		row.add_child(load_button)

		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.custom_minimum_size = Vector2(92, 50)
		delete_button.pressed.connect(func() -> void:
			_request_delete_save_file_from_menu(slot_name, display_label)
		)
		row.add_child(delete_button)

		load_slot_list.add_child(row)

func _request_delete_save_file_from_menu(slot_name: String, display_label: String) -> void:
	if delete_save_confirm_dialog == null:
		_ensure_delete_save_confirm_dialog()
	if delete_save_confirm_dialog == null:
		return

	pending_delete_slot_count_before = 0
	if SaveManager != null and SaveManager.has_method("list_slots"):
		pending_delete_slot_count_before = (SaveManager.list_slots() as Array).size()
	pending_delete_keep_popup_open = load_slot_popup != null and load_slot_popup.visible and pending_delete_slot_count_before > 1

	pending_delete_slot_name = slot_name
	pending_delete_display_label = display_label
	delete_save_confirm_dialog.dialog_text = "Delete save file \"%s\" permanently?" % display_label
	delete_save_confirm_dialog.popup_centered()

func _on_menu_delete_confirmed() -> void:
	var slot_name: String = pending_delete_slot_name
	var keep_popup_open: bool = pending_delete_keep_popup_open
	var slot_count_before: int = pending_delete_slot_count_before
	pending_delete_slot_name = ""
	pending_delete_display_label = ""
	pending_delete_keep_popup_open = false
	pending_delete_slot_count_before = 0
	if slot_name.is_empty():
		return

	if SaveManager == null or not SaveManager.has_method("delete_save_file"):
		return
	if not bool(SaveManager.delete_save_file(slot_name)):
		return

	if keep_popup_open and slot_count_before > 1:
		call_deferred("_reopen_continue_popup_after_delete")
	else:
		if load_slot_popup != null:
			load_slot_popup.hide()
	_refresh_continue_button_state()

func _reopen_continue_popup_after_delete() -> void:
	if SaveManager == null or not SaveManager.has_method("list_slots"):
		return
	var slots_after_delete: Array = SaveManager.list_slots()
	if slots_after_delete.is_empty():
		if load_slot_popup != null:
			load_slot_popup.hide()
		return
	_show_continue_slot_popup()

func _load_selected_slot(slot_name: String) -> void:
	if SaveManager == null or not SaveManager.has_method("load_slot"):
		return
	if not SaveManager.load_slot(slot_name):
		return

	if SaveManager.has_method("load_game_state") and GameManager != null and GameManager.has_method("import_runtime_state"):
		var game_state: Variant = SaveManager.load_game_state()
		if game_state is Dictionary and not (game_state as Dictionary).is_empty():
			GameManager.import_runtime_state(game_state)

	if load_slot_popup != null:
		load_slot_popup.hide()
	SceneTransition.change_scene(MAP_LEVEL_SCENE)

func _create_map_preview_texture(map_scene_path: String) -> Texture2D:
	var packed_scene := load(map_scene_path) as PackedScene
	if packed_scene == null:
		return _create_fallback_preview()

	var map_instance := packed_scene.instantiate() as Node2D
	if map_instance == null:
		return _create_fallback_preview()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 640)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var camera := Camera2D.new()
	camera.enabled = true
	viewport.add_child(map_instance)
	viewport.add_child(camera)
	add_child(viewport)

	var bounds: Rect2 = _compute_map_bounds(map_instance)
	var target_size: Vector2 = bounds.size
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		target_size = Vector2(8000, 4500)
		bounds = Rect2(-target_size * 0.5, target_size)

	var fit_w: float = target_size.x / float(viewport.size.x)
	var fit_h: float = target_size.y / float(viewport.size.y)
	var fit_scale: float = max(fit_w, fit_h)
	if fit_scale < 1.0:
		fit_scale = 1.0

	var longest_axis: float = max(target_size.x, target_size.y)
	var dynamic_margin: float = clamp(longest_axis / 6000.0, 1.08, 1.22)

	camera.position = bounds.get_center()
	var preview_zoom: float = 1.0 / (fit_scale * dynamic_margin)
	preview_zoom = clamp(preview_zoom, 0.03, 1.0)
	camera.zoom = Vector2(preview_zoom, preview_zoom)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		viewport.queue_free()
		return _create_fallback_preview()

	image.resize(672, 420, Image.INTERPOLATE_NEAREST)
	image.generate_mipmaps()
	var texture: Texture2D = ImageTexture.create_from_image(image)
	viewport.queue_free()
	return texture

func _compute_map_bounds(root: Node2D) -> Rect2:
	var min_corner: Vector2 = Vector2(INF, INF)
	var max_corner: Vector2 = Vector2(-INF, -INF)
	var has_bounds: bool = false

	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current == null:
			continue
		if current is TileMapLayer:
			var layer: TileMapLayer = current as TileMapLayer
			var layer_rect: Rect2 = _tile_rect_to_global_bounds(layer, layer.get_used_rect())
			if layer_rect.size != Vector2.ZERO:
				min_corner.x = min(min(min_corner.x, layer_rect.position.x), layer_rect.end.x)
				min_corner.y = min(min(min_corner.y, layer_rect.position.y), layer_rect.end.y)
				max_corner.x = max(max(max_corner.x, layer_rect.position.x), layer_rect.end.x)
				max_corner.y = max(max(max_corner.y, layer_rect.position.y), layer_rect.end.y)
				has_bounds = true

		if current is TileMap:
			var tile_map: TileMap = current as TileMap
			var map_rect: Rect2 = _tile_rect_to_global_bounds(tile_map, tile_map.get_used_rect())
			if map_rect.size != Vector2.ZERO:
				min_corner.x = min(min(min_corner.x, map_rect.position.x), map_rect.end.x)
				min_corner.y = min(min(min_corner.y, map_rect.position.y), map_rect.end.y)
				max_corner.x = max(max(max_corner.x, map_rect.position.x), map_rect.end.x)
				max_corner.y = max(max(max_corner.y, map_rect.position.y), map_rect.end.y)
				has_bounds = true

		for child: Node in current.get_children():
			stack.append(child)

	if not has_bounds:
		return Rect2()

	return Rect2(min_corner, max_corner - min_corner)

func _tile_rect_to_global_bounds(tile_node: Node2D, used_rect: Rect2i) -> Rect2:
	if used_rect.size == Vector2i.ZERO:
		return Rect2()

	var tile_size := Vector2(16.0, 16.0)
	if tile_node is TileMapLayer:
		var layer: TileMapLayer = tile_node as TileMapLayer
		if layer.tile_set != null:
			tile_size = layer.tile_set.tile_size
	elif tile_node is TileMap:
		var tile_map: TileMap = tile_node as TileMap
		if tile_map.tile_set != null:
			tile_size = tile_map.tile_set.tile_size

	var top_left_cell: Vector2i = used_rect.position
	var bottom_right_cell: Vector2i = used_rect.position + used_rect.size

	var top_left_local: Vector2 = tile_node.map_to_local(top_left_cell) - (tile_size * 0.5)
	var bottom_right_local: Vector2 = tile_node.map_to_local(bottom_right_cell) + (tile_size * 0.5)

	var top_left_global: Vector2 = tile_node.to_global(top_left_local)
	var bottom_right_global: Vector2 = tile_node.to_global(bottom_right_local)

	var rect_position := Vector2(min(top_left_global.x, bottom_right_global.x), min(top_left_global.y, bottom_right_global.y))
	var rect_size := Vector2(abs(bottom_right_global.x - top_left_global.x), abs(bottom_right_global.y - top_left_global.y))
	return Rect2(rect_position, rect_size)

func _create_fallback_preview() -> Texture2D:
	var image := Image.create(96, 60, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.10, 0.12, 0.14, 1.0))

	for y in range(0, 60, 6):
		for x in range(0, 96, 6):
			if int((x + y) / 6.0) % 2 == 0:
				image.fill_rect(Rect2i(x, y, 6, 6), Color(0.16, 0.19, 0.22, 1.0))

	return ImageTexture.create_from_image(image)

func _populate_bgm_options() -> void:
	bgm_option_button.clear()
	for track_name in bgm_tracks.keys():
		bgm_option_button.add_item(track_name)

func _apply_music_track(track_name: String) -> void:
	if not bgm_tracks.has(track_name):
		return

	MusicManager.set_track(track_name)

func _on_bgm_option_selected(index: int) -> void:
	var track_name = bgm_option_button.get_item_text(index)
	settings_state["bgm_track"] = track_name
	_apply_music_track(track_name)

func _select_option_by_text(option_button: OptionButton, text: String) -> void:
	for i in range(option_button.get_item_count()):
		if option_button.get_item_text(i) == text:
			option_button.select(i)
			return
