extends RefCounted

const SAVE_PATH := "user://zombie_progression.cfg"
const SLOT_COUNT := 10
const FLESH := "tough_flesh"
const BRUTE := "brute"
const HUNGER := "call_of_hunger"
const NODES := {
	FLESH: {
		"title": "Крепкая плоть", "costs": [8, 16, 28, 45, 65], "requires": {},
		"unlock": "initial_unlocked", "hp_per_level": 0.05,
	},
	BRUTE: {
		"title": "Громила", "costs": [25], "requires": {FLESH: 2},
		"unlock": "initial_unlocked", "chance": 0.10, "health": 2.0, "speed": 0.65,
		"damage": 1.5, "interval": 2.0, "splash": 0.4, "radius": 1.5,
		"knockback": 0.5, "infection": 0.02,
	},
	HUNGER: {
		"title": "Зов голода", "costs": [10, 20, 35, 55, 80], "requires": {},
		"unlock": "initial_unlocked", "optional": true,
		"icon": preload("res://assets/ui/call_of_hunger_emblem.tres"),
		"effects": [
			{"speed": 0.25, "duration": 10.0, "radius": 3.0, "uses": 1},
			{"speed": 0.27, "duration": 11.0, "radius": 3.3, "uses": 2},
			{"speed": 0.29, "duration": 12.0, "radius": 3.6, "uses": 3},
			{"speed": 0.31, "duration": 13.0, "radius": 3.9, "uses": 4},
			{"speed": 0.33, "duration": 14.0, "radius": 4.2, "uses": 5},
		],
	},
}

var state := _fresh_state()
var path: String
var save_error: Error = OK
var _read_only := false
var _dirty := false
var _revision := 0


func _init(save_path := SAVE_PATH) -> void:
	path = save_path
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return
	var loaded: Variant = config.get_value("zombies", "profile", null) if error == OK else null
	var version: Variant = config.get_value("zombies", "version", 0) if error == OK else 0
	if version == 1 and loaded is Dictionary:
		var virus: Variant = loaded.get("virus")
		loaded.initial_unlocked = loaded.get("first_victory", false) == true or (virus is int and virus > 0)
		loaded.erase("first_victory")
	if version in [1, 2] and _valid(loaded):
		state = loaded
		_dirty = version == 1
	else:
		_read_only = true
		_record_error(ERR_FILE_CORRUPT if error == OK else error)


static func empty_slots() -> PackedStringArray:
	var slots := PackedStringArray()
	slots.resize(SLOT_COUNT)
	return slots


static func _fresh_state() -> Dictionary:
	return {"virus": 0, "paid": {}, "slots": empty_slots(),
		"initial_unlocked": false, "reveal_seen": false}


static func level(build: Dictionary, id: String) -> int:
	return Draft.level(build, id)


static func effect_text(id: String, rank: int) -> String:
	match id:
		FLESH: return "+%d%% к максимуму HP всех форм" % roundi(NODES[id].hp_per_level * rank * 100)
		BRUTE: return "10% шанс появления при обращении. Удар по площади и отталкивание цели."
		HUNGER:
			var data: Dictionary = NODES[id].effects[rank - 1]
			return "+%d%% скорости · %s с · %sW · %d прим." % [
				roundi(data.speed * 100), data.duration, data.radius, data.uses]
	return ""


func credit_conversion() -> bool:
	var revealed: bool = not state.initial_unlocked
	state.virus += 1
	state.initial_unlocked = true
	_changed()
	return revealed


func mark_reveal_seen() -> void:
	if state.initial_unlocked and not state.reveal_seen:
		state.reveal_seen = true
		_changed()


func begin_edit() -> Draft:
	return Draft.new(state, _revision)


func apply(draft: Draft) -> Error:
	if draft.revision != _revision:
		return ERR_BUSY
	var proposed: Dictionary = draft.build.duplicate(true)
	if not _valid(proposed):
		return ERR_INVALID_DATA
	var error := _write(proposed)
	if error == OK:
		state = proposed
		_dirty = false
		_revision += 1
	return error


func flush() -> void:
	if _dirty and _write(state) == OK:
		_dirty = false


func reset_progress() -> Error:
	var fresh := _fresh_state()
	var error := _write(fresh, true)
	if error == OK:
		state = fresh
		_read_only = false
		_dirty = false
		_revision += 1
	return error


func _changed() -> void:
	_revision += 1
	_dirty = true
	flush()


func _write(profile: Dictionary, replace_unreadable := false) -> Error:
	if _read_only and not replace_unreadable:
		return save_error
	var config := ConfigFile.new()
	config.set_value("zombies", "version", 2)
	config.set_value("zombies", "profile", profile)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	_record_error(error)
	return error


func _record_error(error: Error) -> void:
	if error != OK and error != save_error:
		push_error("Zombie progression save (%s): %s" % [path, error_string(error)])
	save_error = error


func _valid(profile: Variant) -> bool:
	if not profile is Dictionary:
		return false
	if not profile.get("virus") is int or profile.virus < 0 or not profile.get("paid") is Dictionary:
		return false
	if not profile.get("initial_unlocked") is bool or not profile.get("reveal_seen") is bool:
		return false
	if not profile.get("slots") is PackedStringArray or profile.slots.size() != SLOT_COUNT:
		return false
	for id in profile.paid:
		var costs: Variant = profile.paid[id]
		if not NODES.has(id) or not costs is Array or costs.size() > NODES[id].costs.size():
			return false
		for cost in costs:
			if not cost is int or cost <= 0:
				return false
		if not costs.is_empty() and not profile.get(NODES[id].unlock, false):
			return false
	for id in profile.paid:
		if level(profile, id) > 0 and not Draft.requirements_met(profile, id):
			return false
	var assigned := {}
	for id in profile.slots:
		if id.is_empty():
			continue
		if not NODES.has(id) or not NODES[id].get("optional", false) or level(profile, id) == 0 or assigned.has(id):
			return false
		assigned[id] = true
	return true


class Draft:
	var original: Dictionary
	var build: Dictionary
	var revision: int

	static func level(profile: Dictionary, id: String) -> int:
		return profile.paid.get(id, []).size()

	static func requirements_met(profile: Dictionary, id: String) -> bool:
		for parent in NODES[id].requires:
			if level(profile, parent) < NODES[id].requires[parent]:
				return false
		return true

	func _init(saved: Dictionary, saved_revision: int) -> void:
		original = saved.duplicate(true)
		build = saved.duplicate(true)
		revision = saved_revision

	func changed() -> bool:
		return original != build

	func purchase_block(id: String, preview := false) -> String:
		var node: Dictionary = NODES[id]
		var rank := level(build, id)
		if not preview and not build.get(node.unlock, false):
			return "Откроется после первого начисления Вируса"
		for parent in node.requires:
			if level(build, parent) < node.requires[parent]:
				return "Требуется «%s», ур. %d" % [NODES[parent].title, node.requires[parent]]
		if rank >= node.costs.size():
			return "Максимальный уровень"
		if build.virus < node.costs[rank]:
			return "Недостаточно Вируса"
		return ""

	func purchase(id: String) -> void:
		if not purchase_block(id).is_empty():
			return
		var cost: int = NODES[id].costs[level(build, id)]
		if not build.paid.has(id):
			build.paid[id] = []
		build.paid[id].append(cost)
		build.virus -= cost

	func refund(id: String) -> void:
		_refund_levels(id, false)
		var cascade := true
		while cascade:
			cascade = false
			for dependent in NODES:
				if level(build, dependent) > 0 and not requirements_met(build, dependent):
					_refund_levels(dependent, true)
					cascade = true

	func reset() -> void:
		for id in NODES:
			_refund_levels(id, true)

	func _refund_levels(id: String, all_levels: bool) -> void:
		if level(build, id) == 0:
			return
		var costs: Array = build.paid[id]
		build.virus += costs.pop_back()
		if all_levels:
			for cost in costs:
				build.virus += cost
			costs.clear()
		if costs.is_empty():
			build.paid.erase(id)
			var slot: int = build.slots.find(id)
			if slot >= 0:
				build.slots[slot] = ""

	func assign(id: String, target: int, from_slot := -1) -> void:
		if target < 0 or target >= SLOT_COUNT or not NODES.has(id):
			return
		if not NODES[id].get("optional", false) or level(build, id) == 0:
			return
		var previous: int = build.slots.find(id)
		if previous == target:
			return
		if previous >= 0:
			build.slots[previous] = build.slots[target] if previous == from_slot else ""
		build.slots[target] = id

	func unassign(slot: int) -> void:
		if slot >= 0 and slot < SLOT_COUNT:
			build.slots[slot] = ""
