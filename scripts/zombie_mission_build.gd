extends RefCounted

const PROGRESSION = preload("res://scripts/zombie_progression.gd")

var build: Dictionary
var hunger: Dictionary = {}
var hunger_slot: int
var hunger_radius := 0.0
var active_ability := PROGRESSION.HUNGER
var abilities: Dictionary = {}
var available_uses: int:
	get: return uses_for(active_ability)
var targeting := false
var queued_points: Array[Vector2] = []
var queued_abilities: Array[String] = []
var virus_earned := 0
var revealed_development := false
var _character_width: float
var _developer_abilities: Array[String] = []


func _init(saved_build: Dictionary, character_width: float) -> void:
	_character_width = character_width
	build = {"paid": saved_build.paid.duplicate(true), "slots": saved_build.slots.duplicate()}
	for id in build.slots:
		if id.is_empty() or PROGRESSION.level(build, id) == 0:
			continue
		_add_ability(id, PROGRESSION.level(build, id))
	hunger_slot = build.slots.find(PROGRESSION.HUNGER)
	var rank := PROGRESSION.level(build, PROGRESSION.HUNGER)
	if hunger_slot >= 0 and rank > 0:
		hunger = PROGRESSION.NODES[PROGRESSION.HUNGER].effects[rank - 1]
		hunger_radius = hunger.radius * character_width


func _add_ability(id: String, rank: int) -> void:
	var effect: Dictionary = PROGRESSION.NODES[id].effects[rank - 1]
	abilities[id] = {"effect": effect, "radius": effect.radius * _character_width,
		"uses": effect.uses, "rank": rank}


func add_developer_ability(id: String) -> bool:
	var slot: int = build.slots.find("")
	if slot < 0 or id in build.slots or not PROGRESSION.NODES.get(id, {}).has("effects"):
		return false
	_add_ability(id, maxi(1, PROGRESSION.level(build, id)))
	build.slots[slot] = id
	_developer_abilities.append(id)
	return true


func clear_developer_abilities() -> void:
	if active_ability in _developer_abilities:
		targeting = false
		active_ability = PROGRESSION.HUNGER
	for index in range(queued_abilities.size() - 1, -1, -1):
		if queued_abilities[index] in _developer_abilities:
			queued_abilities.remove_at(index)
			queued_points.remove_at(index)
	for id in _developer_abilities:
		build.slots[build.slots.find(id)] = ""
		abilities.erase(id)
	_developer_abilities.clear()


func restore_charges() -> void:
	for ability in abilities.values():
		ability.uses = ability.effect.uses


func uses_for(id: String) -> int:
	return abilities[id].uses if abilities.has(id) else 0


func radius_for(id: String) -> float:
	return abilities[id].radius if abilities.has(id) else 0.0


func prepare_zombie(zombie: Node, converted: bool) -> void:
	apply_form(zombie, PROGRESSION.choose_form(build, randf()) if converted else "")
	zombie.max_health *= 1.0 + PROGRESSION.NODES[PROGRESSION.FLESH].hp_per_level * PROGRESSION.level(build, PROGRESSION.FLESH)
	zombie.speed_modifiers[PROGRESSION.TENDONS] = PROGRESSION.NODES[PROGRESSION.TENDONS].speed_per_level * PROGRESSION.level(build, PROGRESSION.TENDONS)
	if not zombie.is_brute:
		zombie.infection_chance += PROGRESSION.NODES[PROGRESSION.SALIVA].infection_per_level * PROGRESSION.level(build, PROGRESSION.SALIVA)
	zombie.entrance_damage_bonus = PROGRESSION.NODES[PROGRESSION.GROWTHS].entrance_per_level * PROGRESSION.level(build, PROGRESSION.GROWTHS)


static func apply_form(zombie: Node, id: String) -> void:
	zombie.zombie_form = id
	zombie.is_brute = id == PROGRESSION.BRUTE
	if id.is_empty():
		return
	var form: Dictionary = PROGRESSION.NODES[id]
	zombie.max_health *= form.health
	zombie.move_speed *= form.speed
	zombie.attack_damage *= form.damage
	zombie.attack_interval *= form.interval
	zombie.infection_chance = form.infection


func confirm(point: Vector2, tactical_pause: bool, mission: Node2D) -> void:
	if not targeting or available_uses <= 0:
		return
	abilities[active_ability].uses -= 1
	targeting = available_uses > 0
	if tactical_pause:
		queued_points.append(point)
		queued_abilities.append(active_ability)
	else:
		_activate(point, mission, active_ability)


func execute_queue(mission: Node2D) -> void:
	for index in queued_points.size():
		_activate(queued_points[index], mission, queued_abilities[index])
	queued_points.clear()
	queued_abilities.clear()


func _activate(point: Vector2, mission: Node2D, id: String = PROGRESSION.HUNGER) -> void:
	var effect: Dictionary = abilities[id].effect
	var radius_squared := radius_for(id) * radius_for(id)
	for zombie in mission.get_tree().get_nodes_in_group("player_units"):
		if mission.is_ancestor_of(zombie) and zombie.is_alive() and not zombie.is_queued_for_deletion() and zombie.global_position.distance_squared_to(point) <= radius_squared:
			zombie.apply_racial_effect(id, effect)
