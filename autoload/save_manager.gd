extends Node

const SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const DEFAULT_SLOT: String = "slot_1"

var active_slot: String = DEFAULT_SLOT
var slot_data: Dictionary = {}

func _ready() -> void:
	load_slot(active_slot)

func get_slot_path(slot_name: String) -> String:
	return "%s/%s.save" % [SAVE_DIR, slot_name]

func load_slot(slot_name: String = DEFAULT_SLOT) -> bool:
	active_slot = slot_name
	slot_data = {
		"version": SAVE_VERSION,
		"created_unix": Time.get_unix_time_from_system(),
		"updated_unix": Time.get_unix_time_from_system(),
		"thermal_maps": {},
		"thermal_sections": {},
		"placed_structures": {}
	}

	var save_path: String = get_slot_path(slot_name)
	if not FileAccess.file_exists(save_path):
		return save_slot(slot_name)

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: Failed to open save file for reading: %s" % save_path)
		return false

	var loaded: Variant = file.get_var()
	file.close()

	if loaded is Dictionary:
		slot_data = loaded
		if not slot_data.has("thermal_maps"):
			slot_data["thermal_maps"] = {}
		if not slot_data.has("thermal_sections"):
			slot_data["thermal_sections"] = {}
		if not slot_data.has("placed_structures"):
			slot_data["placed_structures"] = {}
		return true

	push_warning("SaveManager: Save file format invalid; starting fresh slot.")
	return save_slot(slot_name)

func save_slot(slot_name: String = "") -> bool:
	if slot_name.is_empty():
		slot_name = active_slot
	active_slot = slot_name

	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		push_warning("SaveManager: Failed to create save directory: %s" % SAVE_DIR)
		return false

	slot_data["version"] = SAVE_VERSION
	slot_data["updated_unix"] = Time.get_unix_time_from_system()
	if not slot_data.has("thermal_maps"):
		slot_data["thermal_maps"] = {}
	if not slot_data.has("thermal_sections"):
		slot_data["thermal_sections"] = {}
	if not slot_data.has("placed_structures"):
		slot_data["placed_structures"] = {}

	var save_path: String = get_slot_path(slot_name)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: Failed to open save file for writing: %s" % save_path)
		return false

	file.store_var(slot_data)
	file.close()
	return true

func clear_slot(slot_name: String = "") -> bool:
	if slot_name.is_empty():
		slot_name = active_slot

	slot_data = {
		"version": SAVE_VERSION,
		"created_unix": Time.get_unix_time_from_system(),
		"updated_unix": Time.get_unix_time_from_system(),
		"thermal_maps": {},
		"thermal_sections": {},
		"placed_structures": {}
	}
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
	return save_slot(active_slot)

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
	return save_slot(active_slot)

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
		return save_slot(active_slot)
	return true
