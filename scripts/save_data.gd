## Persists the learner's state to user:// (IndexedDB-backed in the Web export,
## so it survives a page reload) the same way ml-ladder uses localStorage.
class_name SaveData
extends RefCounted

const PATH := "user://godot_ladder_save.json"

static func default_state() -> Dictionary:
	return {
		"level": 1, "top": 1, "box": {}, "due": [], "n": 0,
		"stats": {"ans": 0, "right": 0, "idk": 0}, "done": false,
		"code": {}, "drafts": {}, "mode": "quiz", "view": "list",
	}

static func load_state() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return default_state()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return default_state()
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("level"):
		return default_state()
	var state: Dictionary = default_state()
	state.merge(parsed, true)
	return state

static func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()
