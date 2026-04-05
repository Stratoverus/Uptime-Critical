extends Node

const SAVE_VERSION: int = 2
const SAVE_DIR: String = "user://saves"
const DEFAULT_SLOT: String = "slot_1"
const SAVE_FORMAT_VERSION: int = 1
const SAVE_PASSWORD_PEPPER: String = "uptime_critical_slot_cipher_v1"
const SAVE_SIGNATURE_PEPPER: String = "uptime_critical_slot_sig_v1"

var active_slot: String = DEFAULT_SLOT
var slot_data: Dictionary = {}
var slot_dirty: bool = false
var autosave_on_mutation: bool = false

func _make_default_slot_data() -> Dictionary:
	var now_unix := Time.get_unix_time_from_system()
	return {
		"version": SAVE_VERSION,
		"save_label": "",
		"created_unix": now_unix,
		"updated_unix": now_unix,
		"thermal_maps": {},
		"thermal_sections": {},
		"placed_structures": {},
		"game_state": {},
		"world_state": {}
	}

func _normalize_slot_data(candidate: Dictionary) -> Dictionary:
	var normalized: Dictionary = _make_default_slot_data()
	for key in candidate.keys():
		normalized[key] = candidate[key]

	if not (normalized.get("thermal_maps", {}) is Dictionary):
		normalized["thermal_maps"] = {}
	if not (normalized.get("thermal_sections", {}) is Dictionary):
		normalized["thermal_sections"] = {}
	if not (normalized.get("placed_structures", {}) is Dictionary):
		normalized["placed_structures"] = {}
	if not (normalized.get("game_state", {}) is Dictionary):
		normalized["game_state"] = {}
	if not (normalized.get("world_state", {}) is Dictionary):
		normalized["world_state"] = {}
	if not normalized.has("save_label"):
		normalized["save_label"] = ""

	var label_variant: Variant = normalized.get("save_label", "")
	if label_variant == null:
		normalized["save_label"] = ""
	else:
		normalized["save_label"] = String(label_variant)

	return normalized

func _slot_name_to_default_label(slot_name: String) -> String:
	if slot_name.is_empty():
		return "Save"
	var prettified := slot_name.replace("_", " ").strip_edges()
	if prettified.is_empty():
		return slot_name
	return prettified.capitalize()

func _extract_slot_name_from_file(file_name: String) -> String:
	if not file_name.ends_with(".save"):
		return ""
	return file_name.substr(0, file_name.length() - 5)

func _sort_slot_entries_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0))

func _get_save_password() -> String:
	var app_name := String(ProjectSettings.get_setting("application/config/name", "uptime_critical"))
	return "%s::%s" % [app_name, SAVE_PASSWORD_PEPPER]

func _compute_slot_signature(payload_slot_data: Dictionary) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	var canonical_json: String = JSON.stringify(payload_slot_data)
	hasher.update((canonical_json + SAVE_SIGNATURE_PEPPER).to_utf8_buffer())
	return hasher.finish().hex_encode()

func _write_encrypted_payload(slot_name: String, payload: Dictionary) -> bool:
	var save_path: String = get_slot_path(slot_name)
	var file := FileAccess.open_encrypted_with_pass(save_path, FileAccess.WRITE, _get_save_password())
	if file == null:
		push_warning("SaveManager: Failed to open encrypted save file for writing: %s" % save_path)
		return false

	file.store_string(JSON.stringify(payload))
	file.close()
	return true

func _load_encrypted_payload(save_path: String) -> Dictionary:
	if not _is_encrypted_save_file(save_path):
		return {}

	var file := FileAccess.open_encrypted_with_pass(save_path, FileAccess.READ, _get_save_password())
	if file == null:
		return {}

	var payload_text: String = file.get_as_text()
	file.close()

	if payload_text.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(payload_text)
	if not (parsed is Dictionary):
		return {}

	var payload := parsed as Dictionary
	var payload_slot_data: Variant = payload.get("slot", null)
	var payload_signature: String = String(payload.get("signature", ""))
	if not (payload_slot_data is Dictionary):
		return {}

	# Recovery mode: keep encrypted payload readable even if signature format changed.
	if payload_signature.is_empty():
		return payload_slot_data as Dictionary

	var expected_signature: String = _compute_slot_signature(payload_slot_data as Dictionary)
	if payload_signature != expected_signature:
		return payload_slot_data as Dictionary

	return payload_slot_data as Dictionary

func _is_encrypted_save_file(save_path: String) -> bool:
	var probe := FileAccess.open(save_path, FileAccess.READ)
	if probe == null:
		return false

	if probe.get_length() < 4:
		probe.close()
		return false

	var magic: PackedByteArray = probe.get_buffer(4)
	probe.close()
	return magic.size() == 4 and magic[0] == 0x47 and magic[1] == 0x44 and magic[2] == 0x45 and magic[3] == 0x43

func _load_legacy_payload(save_path: String) -> Dictionary:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}

	var loaded_text: String = file.get_as_text()
	file.close()
	if loaded_text.is_empty():
		return {}

	if loaded_text.begins_with("GDEC"):
		return {}

	if not loaded_text.begins_with("{"):
		return {}

	var parsed: Variant = JSON.parse_string(loaded_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _ready() -> void:
	if slot_exists(active_slot):
		load_slot(active_slot)
	else:
		slot_data = _make_default_slot_data()
		slot_dirty = false

func _exit_tree() -> void:
	# Do not create a brand-new save file just because the app is closing.
	# Only persist on shutdown if this slot already has a backing file.
	if not slot_exists(active_slot):
		return
	save_checkpoint()

func get_slot_path(slot_name: String) -> String:
	return "%s/%s.save" % [SAVE_DIR, slot_name]

func get_active_slot_name() -> String:
	return active_slot

func slot_exists(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false
	return FileAccess.file_exists(get_slot_path(slot_name))

func delete_save_file(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false

	var save_path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(save_path):
		return false

	var abs_path: String = ProjectSettings.globalize_path(save_path)
	var err: Error = DirAccess.remove_absolute(abs_path)
	if err != OK:
		return false

	if active_slot == slot_name:
		var remaining_slots: Array = list_slots()
		if remaining_slots.is_empty():
			active_slot = DEFAULT_SLOT
			slot_data = _make_default_slot_data()
			slot_dirty = false
		else:
			var first_entry: Dictionary = remaining_slots[0] as Dictionary
			active_slot = String(first_entry.get("slot_name", DEFAULT_SLOT))
			load_slot(active_slot)

	return true

func get_active_slot_label() -> String:
	var label := String(slot_data.get("save_label", "")).strip_edges()
	if label.is_empty():
		return _slot_name_to_default_label(active_slot)
	return label

func set_active_slot_label(label: String) -> bool:
	if slot_data.is_empty():
		slot_data = _make_default_slot_data()
	slot_data["save_label"] = label.strip_edges()
	return commit_mutation()

func sanitize_slot_name(raw_name: String) -> String:
	var value := raw_name.strip_edges().to_lower()
	if value.is_empty():
		return ""

	var cleaned := ""
	for i in range(value.length()):
		var character := value[i]
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_":
			cleaned += character
		elif character == " " or character == "-":
			cleaned += "_"

	while cleaned.find("__") != -1:
		cleaned = cleaned.replace("__", "_")

	cleaned = cleaned.trim_prefix("_").trim_suffix("_")
	return cleaned

func create_new_slot(raw_name: String = "", display_label: String = "") -> String:
	var slot_name := sanitize_slot_name(raw_name)
	if slot_name.is_empty():
		slot_name = "slot_%s" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")

	active_slot = slot_name
	slot_data = _make_default_slot_data()
	var label := display_label.strip_edges()
	if label.is_empty():
		label = _slot_name_to_default_label(slot_name)
	slot_data["save_label"] = label

	if save_slot(slot_name):
		return slot_name
	return ""

func start_new_runtime_slot(raw_name: String = "", display_label: String = "") -> String:
	var slot_name := sanitize_slot_name(raw_name)
	if slot_name.is_empty():
		slot_name = "slot_%s" % Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")

	active_slot = slot_name
	slot_data = _make_default_slot_data()
	var label := display_label.strip_edges()
	if label.is_empty():
		label = _slot_name_to_default_label(slot_name)
	slot_data["save_label"] = label
	slot_dirty = false
	return slot_name

func list_slots() -> Array:
	var slots: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return slots

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or not file_name.ends_with(".save"):
			continue

		var slot_name := _extract_slot_name_from_file(file_name)
		if slot_name.is_empty():
			continue

		var save_path := "%s/%s" % [SAVE_DIR, file_name]
		var loaded_slot_data := _load_encrypted_payload(save_path)
		if loaded_slot_data.is_empty():
			loaded_slot_data = _load_legacy_payload(save_path)
		if loaded_slot_data.is_empty():
			continue

		var normalized := _normalize_slot_data(loaded_slot_data)
		var game_state: Variant = normalized.get("game_state", {})
		if not (game_state is Dictionary):
			game_state = {}

		var display_label: String = String(normalized.get("save_label", "")).strip_edges()
		if display_label.is_empty():
			display_label = _slot_name_to_default_label(slot_name)

		slots.append({
			"slot_name": slot_name,
			"display_label": display_label,
			"created_unix": int(normalized.get("created_unix", 0)),
			"updated_unix": int(normalized.get("updated_unix", 0)),
			"day": int((game_state as Dictionary).get("current_day", 0)),
			"money": float((game_state as Dictionary).get("revenue", 0.0)),
			"map_scene": String((game_state as Dictionary).get("current_map_scene_path", ""))
		})

	dir.list_dir_end()
	slots.sort_custom(Callable(self, "_sort_slot_entries_desc"))
	return slots

func load_slot(slot_name: String = DEFAULT_SLOT) -> bool:
	active_slot = slot_name
	slot_dirty = false
	slot_data = _make_default_slot_data()

	var save_path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(save_path):
		return true

	var encrypted_payload_slot_data: Dictionary = _load_encrypted_payload(save_path)
	if not encrypted_payload_slot_data.is_empty():
		slot_data = _normalize_slot_data(encrypted_payload_slot_data)
		slot_dirty = false
		return true

	var legacy_slot_data: Dictionary = _load_legacy_payload(save_path)
	if not legacy_slot_data.is_empty():
		slot_data = _normalize_slot_data(legacy_slot_data)
		slot_dirty = false
		# Migrate immediately to encrypted format after successful legacy read.
		save_slot(slot_name)
		return true

	# Invalid or unsupported slot file contents: start fresh in memory without auto-creating a file.
	return true

func save_slot(slot_name: String = "") -> bool:
	if slot_name.is_empty():
		slot_name = active_slot
	active_slot = slot_name

	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		push_warning("SaveManager: Failed to create save directory: %s" % SAVE_DIR)
		return false

	slot_data = _normalize_slot_data(slot_data)
	slot_data["version"] = SAVE_VERSION
	slot_data["updated_unix"] = Time.get_unix_time_from_system()

	var payload := {
		"format_version": SAVE_FORMAT_VERSION,
		"slot": slot_data,
		"signature": _compute_slot_signature(slot_data)
	}

	if not _write_encrypted_payload(slot_name, payload):
		return false

	slot_dirty = false
	return true

func flush_pending_changes() -> bool:
	if not slot_dirty:
		return true
	return save_slot(active_slot)

func save_checkpoint() -> bool:
	capture_runtime_state_for_checkpoint()
	return flush_pending_changes()

func capture_runtime_state_for_checkpoint() -> void:
	if slot_data.is_empty():
		slot_data = _make_default_slot_data()

	var captured_any := false
	var tree := get_tree()
	if tree == null:
		return

	for node_variant in tree.get_nodes_in_group("thermal_system"):
		if node_variant is Node:
			var thermal_node := node_variant as Node
			if thermal_node.has_method("save_simulation_state_to_manager"):
				thermal_node.call("save_simulation_state_to_manager")
				captured_any = true

	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null and game_manager.has_method("export_runtime_state"):
		slot_data["game_state"] = game_manager.call("export_runtime_state")
		captured_any = true

	var world_state: Dictionary = {}
	var world_state_value: Variant = slot_data.get("world_state", {})
	if world_state_value is Dictionary:
		world_state = world_state_value

	for node_variant in tree.get_nodes_in_group("world_save_state"):
		if not (node_variant is Node):
			continue
		var world_node := node_variant as Node
		if not world_node.has_method("export_world_state"):
			continue

		var state_key: String = ""
		if world_node.has_method("get_world_state_key"):
			state_key = String(world_node.call("get_world_state_key"))
		if state_key.is_empty():
			state_key = String(world_node.get_path())

		world_state[state_key] = world_node.call("export_world_state")
		captured_any = true

	slot_data["world_state"] = world_state
	if captured_any:
		slot_dirty = true

func set_autosave_on_mutation(enabled: bool) -> void:
	autosave_on_mutation = enabled

func commit_mutation() -> bool:
	slot_dirty = true
	if autosave_on_mutation:
		return save_slot(active_slot)
	return true

func mark_runtime_dirty() -> void:
	slot_dirty = true

func has_unsaved_changes() -> bool:
	return slot_dirty

func request_manual_save() -> bool:
	return save_checkpoint()

func request_manual_save_to_slot(slot_name: String, display_label: String = "") -> bool:
	if slot_name.is_empty():
		return false

	if slot_exists(slot_name):
		if not load_slot(slot_name):
			return false
	else:
		if create_new_slot(slot_name, display_label).is_empty():
			return false

	if not display_label.strip_edges().is_empty():
		set_active_slot_label(display_label)

	return request_manual_save()

func load_game_state() -> Dictionary:
	if slot_data.is_empty():
		return {}
	var game_state: Variant = slot_data.get("game_state", {})
	if game_state is Dictionary:
		return (game_state as Dictionary).duplicate(true)
	return {}

func save_game_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	if slot_data.is_empty():
		slot_data = _make_default_slot_data()
	slot_data["game_state"] = state.duplicate(true)
	return commit_mutation()

func load_world_state(world_key: String) -> Dictionary:
	if world_key.is_empty() or slot_data.is_empty():
		return {}
	var world_state: Variant = slot_data.get("world_state", {})
	if not (world_state is Dictionary):
		return {}
	if not (world_state as Dictionary).has(world_key):
		return {}
	var entry: Variant = (world_state as Dictionary).get(world_key)
	if entry is Dictionary:
		return (entry as Dictionary).duplicate(true)
	return {}

func save_world_state(world_key: String, state: Dictionary) -> bool:
	if world_key.is_empty() or state.is_empty():
		return false
	if slot_data.is_empty():
		slot_data = _make_default_slot_data()

	var world_state: Dictionary = {}
	var world_state_value: Variant = slot_data.get("world_state", {})
	if world_state_value is Dictionary:
		world_state = world_state_value
	world_state[world_key] = state.duplicate(true)
	slot_data["world_state"] = world_state
	return commit_mutation()

func clear_slot(slot_name: String = "") -> bool:
	if slot_name.is_empty():
		slot_name = active_slot

	slot_data = {
		"version": SAVE_VERSION,
		"created_unix": Time.get_unix_time_from_system(),
		"updated_unix": Time.get_unix_time_from_system(),
		"thermal_maps": {},
		"thermal_sections": {},
		"placed_structures": {},
		"game_state": {},
		"world_state": {}
	}
	slot_dirty = true
	return save_slot(slot_name)

func load_placed_structures(scene_key: String, section_key: String = "default") -> Array:
	if scene_key.is_empty():
		return []
	if section_key.is_empty():
		section_key = "default"
	if not slot_data.has("placed_structures"):
		return []

	var placed_structures: Variant = slot_data["placed_structures"]
	if not (placed_structures is Dictionary):
		return []
	if not placed_structures.has(scene_key):
		return []

	var scene_sections: Variant = placed_structures[scene_key]
	if not (scene_sections is Dictionary):
		return []
	if not scene_sections.has(section_key):
		return []

	var entries: Variant = scene_sections[section_key]
	if entries is Array:
		return entries.duplicate(true)
	return []

func save_placed_structures(scene_key: String, section_key: String, entries: Array) -> bool:
	if scene_key.is_empty() or section_key.is_empty():
		return false
	if not slot_data.has("placed_structures"):
		slot_data["placed_structures"] = {}

	var placed_structures := slot_data["placed_structures"] as Dictionary
	var scene_sections: Dictionary = {}
	if placed_structures.has(scene_key):
		var existing_scene_sections: Variant = placed_structures[scene_key]
		if existing_scene_sections is Dictionary:
			scene_sections = existing_scene_sections

	scene_sections[section_key] = entries.duplicate(true)
	placed_structures[scene_key] = scene_sections
	slot_data["placed_structures"] = placed_structures
	return commit_mutation()

func add_placed_structure(scene_key: String, section_key: String, entry: Dictionary) -> String:
	if scene_key.is_empty() or section_key.is_empty() or entry.is_empty():
		return ""

	var entries: Array = load_placed_structures(scene_key, section_key)
	var structure_entry: Dictionary = entry.duplicate(true)
	var structure_id: String = String(structure_entry.get("id", ""))
	if structure_id.is_empty():
		structure_id = "%d_%d" % [Time.get_unix_time_from_system(), randi()]
		structure_entry["id"] = structure_id

	entries.append(structure_entry)
	if not save_placed_structures(scene_key, section_key, entries):
		return ""

	return structure_id

func remove_placed_structure(scene_key: String, section_key: String, structure_id: String) -> bool:
	if scene_key.is_empty() or section_key.is_empty() or structure_id.is_empty():
		return false

	var entries: Array = load_placed_structures(scene_key, section_key)
	var filtered_entries: Array = []
	var removed: bool = false
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("id", "")) == structure_id:
			removed = true
			continue
		filtered_entries.append(entry)

	if not removed:
		return false

	return save_placed_structures(scene_key, section_key, filtered_entries)

func load_thermal_section_state(scene_key: String, section_key: String = "default") -> Dictionary:
	if scene_key.is_empty():
		return {}
	if section_key.is_empty():
		section_key = "default"

	if slot_data.has("thermal_sections"):
		var thermal_sections: Variant = slot_data["thermal_sections"]
		if thermal_sections is Dictionary and thermal_sections.has(scene_key):
			var scene_sections: Variant = thermal_sections[scene_key]
			if scene_sections is Dictionary and scene_sections.has(section_key):
				var section_state: Variant = scene_sections[section_key]
				if section_state is Dictionary:
					return section_state

	# Backward compatibility with older scene-only map saves.
	if section_key == "default":
		return load_thermal_state(scene_key)

	return {}

func clear_thermal_section_state(scene_key: String, section_key: String = "default") -> bool:
	if scene_key.is_empty():
		return false
	if section_key.is_empty():
		section_key = "default"

	var changed: bool = false

	if slot_data.has("thermal_sections"):
		var thermal_sections: Variant = slot_data["thermal_sections"]
		if thermal_sections is Dictionary and thermal_sections.has(scene_key):
			var scene_sections: Variant = thermal_sections[scene_key]
			if scene_sections is Dictionary and scene_sections.has(section_key):
				scene_sections.erase(section_key)
				changed = true
				if scene_sections.is_empty():
					thermal_sections.erase(scene_key)
				else:
					thermal_sections[scene_key] = scene_sections
				slot_data["thermal_sections"] = thermal_sections

	if section_key == "default" and slot_data.has("thermal_maps"):
		var thermal_maps: Variant = slot_data["thermal_maps"]
		if thermal_maps is Dictionary and thermal_maps.has(scene_key):
			thermal_maps.erase(scene_key)
			slot_data["thermal_maps"] = thermal_maps
			changed = true

	if changed:
		return commit_mutation()

	return true

func save_thermal_section_state(scene_key: String, section_key: String, state: Dictionary) -> bool:
	if scene_key.is_empty() or section_key.is_empty() or state.is_empty():
		return false

	if not slot_data.has("thermal_sections"):
		slot_data["thermal_sections"] = {}

	var thermal_sections := slot_data["thermal_sections"] as Dictionary
	var scene_sections: Dictionary = {}
	if thermal_sections.has(scene_key):
		var existing_scene_sections: Variant = thermal_sections[scene_key]
		if existing_scene_sections is Dictionary:
			scene_sections = existing_scene_sections

	scene_sections[section_key] = state
	thermal_sections[scene_key] = scene_sections
	slot_data["thermal_sections"] = thermal_sections
	return commit_mutation()

func load_thermal_state(scene_key: String) -> Dictionary:
	if scene_key.is_empty():
		return {}
	if not slot_data.has("thermal_maps"):
		return {}

	var thermal_maps: Variant = slot_data["thermal_maps"]
	if not (thermal_maps is Dictionary):
		return {}

	if not thermal_maps.has(scene_key):
		return {}

	var state: Variant = thermal_maps[scene_key]
	if state is Dictionary:
		return state
	return {}

func save_thermal_state(scene_key: String, state: Dictionary) -> bool:
	if scene_key.is_empty() or state.is_empty():
		return false

	if not slot_data.has("thermal_maps"):
		slot_data["thermal_maps"] = {}

	var thermal_maps := slot_data["thermal_maps"] as Dictionary
	thermal_maps[scene_key] = state
	slot_data["thermal_maps"] = thermal_maps
	# Keep legacy and new default section in sync.
	if not save_thermal_section_state(scene_key, "default", state):
		return commit_mutation()
	return true
