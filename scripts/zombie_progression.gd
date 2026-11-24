extends RefCounted

const BALANCE = preload("res://scripts/mission_one_unit_balance.gd")
const SAVE_PATH := "user://zombie_progression.cfg"
const SLOT_COUNT := 10
const FLESH := "tough_flesh"
const BRUTE := "brute"
const HUNGER := "call_of_hunger"
const TENDONS := "grasping_tendons"
const SALIVA := "infectious_saliva"
const GROWTHS := "bone_growths"
const HOUND := "hound"
const CARRIER := "carrier"
const FORTITUDE := "dead_fortitude"
const SPASM := "hungry_spasm"
const FORMS := [BRUTE, HOUND, CARRIER]
const NODES := {
	FLESH: {
		"tree_position": Vector2(0.289, 0.274),
		"icon": preload("res://assets/ui/zombie_style/tough_flesh.png"),
		"title": "Крепкая плоть", "costs": [8, 16, 28, 45, 65], "requires": {},
		"unlock": "initial_unlocked", "hp_per_level": 0.05,
	},
	BRUTE: {
		"tree_position": Vector2(0.163, 0.122),
		"icon": preload("res://assets/ui/zombie_style/brute.png"),
		"title": "Громила", "costs": [25], "requires": {FLESH: 2},
		"unlock": "initial_unlocked", "chance": 0.10,
		"splash": 0.4, "radius": 1.5, "knockback": 0.5,
	},
	HUNGER: {
		"tree_position": Vector2(0.726, 0.716),
		"title": "Зов голода", "costs": [10, 20, 35, 55, 80], "requires": {},
		"unlock": "initial_unlocked", "optional": true,
		"icon": preload("res://assets/ui/zombie_style/call_of_hunger.png"),
		"effects": [
			{"speed": 0.25, "duration": 10.0, "radius": 3.0, "uses": 1},
			{"speed": 0.27, "duration": 11.0, "radius": 3.3, "uses": 2},
			{"speed": 0.29, "duration": 12.0, "radius": 3.6, "uses": 3},
			{"speed": 0.31, "duration": 13.0, "radius": 3.9, "uses": 4},
			{"speed": 0.33, "duration": 14.0, "radius": 4.2, "uses": 5},
		],
	},
	TENDONS: {
		"tree_position": Vector2(0.86, 0.55),
		"title": "Цепкие сухожилия", "costs": [8, 16, 28, 45, 65], "requires": {HUNGER: 1},
		"speed_per_level": 0.02, "icon": preload("res://assets/ui/zombie_style/grasping_tendons.png"),
	},
	SALIVA: {
		"tree_position": Vector2(0.28, 0.015),
		"title": "Заразная слюна", "costs": [10, 20, 35, 55, 80], "requires": {FLESH: 1},
		"infection_per_level": 0.01, "icon": preload("res://assets/ui/zombie_style/infectious_saliva.png"),
	},
	GROWTHS: {
		"tree_position": Vector2(0.10, 0.72),
		"tree_via": [Vector2(0.05, 0.28), Vector2(0.06, 0.58)],
		"title": "Костяные наросты", "costs": [8, 16, 28, 45, 65], "requires": {BRUTE: 1},
		"entrance_per_level": 0.05, "icon": preload("res://assets/ui/zombie_style/bone_growths.png"),
	},
	HOUND: {
		"tree_position": Vector2(0.94, 0.70),
		"title": "Бегун", "costs": [30], "requires": {TENDONS: 2},
		"chance": 0.08, "icon": preload("res://assets/ui/zombie_style/hound.png"),
	},
	CARRIER: {
		"tree_position": Vector2(0.56, 0.04),
		"title": "Носитель", "costs": [40], "requires": {SALIVA: 2},
		"chance": 0.06, "icon": preload("res://assets/ui/zombie_style/carrier.png"),
	},
	FORTITUDE: {
		"tree_position": Vector2(0.30, 0.70),
		"title": "Мёртвая стойкость", "costs": [10, 20, 35, 55, 80], "requires": {FLESH: 3},
		"optional": true, "icon": preload("res://assets/ui/zombie_style/dead_fortitude.png"),
		"effects": [
			{"reduction": 0.15, "duration": 8.0, "radius": 3.0, "uses": 1},
			{"reduction": 0.17, "duration": 9.0, "radius": 3.3, "uses": 2},
			{"reduction": 0.19, "duration": 10.0, "radius": 3.6, "uses": 3},
			{"reduction": 0.21, "duration": 11.0, "radius": 3.9, "uses": 4},
			{"reduction": 0.23, "duration": 12.0, "radius": 4.2, "uses": 5},
		],
	},
	SPASM: {
		"tree_position": Vector2(0.85, 0.81),
		"title": "Голодная судорога", "costs": [10, 20, 35, 55, 80], "requires": {HUNGER: 3},
		"optional": true, "icon": preload("res://assets/ui/zombie_style/hungry_spasm.png"),
		"effects": [
			{"frequency": 0.15, "speed": -0.15, "duration": 6.0, "radius": 3.0, "uses": 1},
			{"frequency": 0.17, "speed": -0.15, "duration": 7.0, "radius": 3.3, "uses": 2},
			{"frequency": 0.19, "speed": -0.15, "duration": 8.0, "radius": 3.6, "uses": 3},
			{"frequency": 0.21, "speed": -0.15, "duration": 9.0, "radius": 3.9, "uses": 4},
			{"frequency": 0.23, "speed": -0.15, "duration": 10.0, "radius": 4.2, "uses": 5},
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
	if version in [1, 2] and loaded is Dictionary and loaded.get("paid") is Dictionary and loaded.paid.values().all(func(costs): return costs is Array):
		loaded.revealed = PackedStringArray()
		for id in NODES:
			if not NODES[id].has("unlock") and Draft.requirements_met(loaded, id):
				loaded.revealed.append(id)
	if version in [1, 2, 3] and _valid(loaded):
		state = loaded
		_dirty = version != 3
	else:
		_read_only = true
		_record_error(ERR_FILE_CORRUPT if error == OK else error)


static func empty_slots() -> PackedStringArray:
	var slots := PackedStringArray()
	slots.resize(SLOT_COUNT)
	return slots


static func _fresh_state() -> Dictionary:
	return {"virus": 0, "paid": {}, "slots": empty_slots(),
		"initial_unlocked": false, "reveal_seen": false, "revealed": PackedStringArray()}


static func level(build: Dictionary, id: String) -> int:
	return Draft.level(build, id)


static func effect_text(id: String, rank: int) -> String:
	match id:
		FLESH: return "+%d%% к максимуму HP всех форм" % roundi(NODES[id].hp_per_level * rank * 100)
		BRUTE, HOUND, CARRIER:
			var stats: Dictionary = BALANCE.ZOMBIES[id]
			var description := "%d%% при обращении · %d HP · скорость %d · %d урона каждые %s с · заражение %d%% до пассивов." % [
				roundi(NODES[id].chance * 100), stats.health, stats.speed, stats.damage,
				str(stats.interval).replace(".", ","), roundi(stats.infection * 100)]
			if id == BRUTE:
				description += " Удар по площади и отталкивание цели."
			return description
		TENDONS: return "+%d%% скорости всех форм от базовой скорости формы" % (rank * 2)
		SALIVA: return "+%d п.п. заражения обычных зомби, Бегунов и Носителей. Громила сохраняет 2%%." % rank
		GROWTHS: return "+%d%% урона дверям и баррикадам всех форм" % (rank * 5)
		FORTITUDE:
			var data: Dictionary = NODES[id].effects[rank - 1]
			return "−%d%% входящего урона · %s с · %sW · %d прим. Без лечения." % [roundi(data.reduction * 100), data.duration, data.radius, data.uses]
		SPASM:
			var data: Dictionary = NODES[id].effects[rank - 1]
			return "+%d%% частоты атак · −15%% скорости · %s с · %sW · %d прим." % [roundi(data.frequency * 100), data.duration, data.radius, data.uses]
		HUNGER:
			var data: Dictionary = NODES[id].effects[rank - 1]
			return "+%d%% скорости · %s с · %sW · %d прим." % [
				roundi(data.speed * 100), data.duration, data.radius, data.uses]
	return ""


static func is_revealed(build: Dictionary, id: String) -> bool:
	return Draft.is_revealed(build, id)


static func choose_form(build: Dictionary, roll: float) -> String:
	# Fixed disjoint intervals: an unowned form's share belongs to ordinary zombies.
	var edge := 0.0
	for id in FORMS:
		edge += NODES[id].chance
		if roll < edge:
			return id if level(build, id) > 0 else ""
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
	config.set_value("zombies", "version", 3)
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
	if not profile.get("revealed") is PackedStringArray:
		return false
	var seen := {}
	for id in profile.revealed:
		if not NODES.has(id) or NODES[id].has("unlock") or seen.has(id) or not profile.initial_unlocked:
			return false
		seen[id] = true
	for id in profile.paid:
		var costs: Variant = profile.paid[id]
		if not NODES.has(id) or not costs is Array or costs.size() > NODES[id].costs.size():
			return false
		for cost in costs:
			if not cost is int or cost <= 0:
				return false
		if not costs.is_empty() and not is_revealed(profile, id):
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

	static func is_revealed(profile: Dictionary, id: String) -> bool:
		return profile.get("initial_unlocked", false) if NODES[id].has("unlock") else id in profile.get("revealed", [])

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
		if not preview and not is_revealed(build, id):
			return "Откроется при развитии предыдущего узла" if not node.has("unlock") else "Откроется после первого начисления Вируса"
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
		for next_id in NODES:
			if not NODES[next_id].has("unlock") and requirements_met(build, next_id) and next_id not in build.revealed:
				build.revealed.append(next_id)

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
