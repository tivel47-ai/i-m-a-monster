extends RefCounted

const PROGRESSION = preload("res://scripts/zombie_progression.gd")

var build: Dictionary
var hunger: Dictionary = {}
var hunger_slot: int
var hunger_radius := 0.0
var available_uses := 0
var targeting := false
var queued_points: Array[Vector2] = []
var virus_earned := 0
var revealed_development := false


func _init(saved_build: Dictionary, character_width: float) -> void:
	build = {"paid": saved_build.paid.duplicate(true), "slots": saved_build.slots.duplicate()}
	hunger_slot = build.slots.find(PROGRESSION.HUNGER)
	var rank := PROGRESSION.level(build, PROGRESSION.HUNGER)
	if hunger_slot >= 0 and rank > 0:
		hunger = PROGRESSION.NODES[PROGRESSION.HUNGER].effects[rank - 1]
		hunger_radius = hunger.radius * character_width
		available_uses = hunger.uses


func prepare_zombie(zombie: Node, converted: bool) -> void:
	var brute: Dictionary = PROGRESSION.NODES[PROGRESSION.BRUTE]
	zombie.is_brute = converted and PROGRESSION.level(build, PROGRESSION.BRUTE) > 0 and randf() < brute.chance
	if zombie.is_brute:
		zombie.max_health *= brute.health
		zombie.move_speed *= brute.speed
		zombie.attack_damage *= brute.damage
		zombie.attack_interval *= brute.interval
		zombie.infection_chance = brute.infection
	zombie.max_health *= 1.0 + PROGRESSION.NODES[PROGRESSION.FLESH].hp_per_level * PROGRESSION.level(build, PROGRESSION.FLESH)


func confirm(point: Vector2, tactical_pause: bool, mission: Node2D) -> void:
	if not targeting or available_uses <= 0:
		return
	available_uses -= 1
	targeting = available_uses > 0
	if tactical_pause:
		queued_points.append(point)
	else:
		_activate(point, mission)


func execute_queue(mission: Node2D) -> void:
	for point in queued_points:
		_activate(point, mission)
	queued_points.clear()


func _activate(point: Vector2, mission: Node2D) -> void:
	var radius_squared := hunger_radius * hunger_radius
	for zombie in mission.get_tree().get_nodes_in_group("player_units"):
		if mission.is_ancestor_of(zombie) and zombie.is_alive() and not zombie.is_queued_for_deletion() and zombie.global_position.distance_squared_to(point) <= radius_squared:
			zombie.apply_hunger(hunger.speed, hunger.duration)
