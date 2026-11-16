extends RefCounted

enum Order { NONE, MOVE, ATTACK }

const MOVE_SLOT_OCCUPANCY_DISTANCE_SQUARED := 324.0
const MOVE_RETRY_DELAY := 0.5

var mission: Node2D
var order := Order.NONE
var move_center := Vector2.ZERO
var move_radius := 0.0
var move_slots: Dictionary = {}
var retried_moves: Dictionary = {}
var move_revision := 0
var attack_targets: Array[Node2D] = []
var next_attacker := 0

var assault_building: InteractiveBuilding
var assault_elapsed := 0.0
var assault_quantity := 0
var assault_feedback := ""


func _init(owner_mission: Node2D) -> void:
	mission = owner_mission


func issue_move(center: Vector2, radius: float, units: Array[Node]) -> void:
	assault_feedback = ""
	order = Order.MOVE
	move_center = center
	move_radius = radius
	attack_targets.clear()
	retried_moves.clear()
	move_revision += 1
	# Resolve exterior assault transitions before sampling from the units' positions.
	for unit in units:
		if unit.is_assaulting_building():
			unit.building_task.cancel_assault(unit)
	var reserved: Array[Vector2] = []
	move_slots = mission.placement.assign_horde_positions(center, radius, units, reserved)
	for unit in units:
		_apply_move(unit)


func issue_attack(targets: Array[Node2D], units: Array[Node]) -> void:
	assault_feedback = ""
	order = Order.ATTACK
	attack_targets = targets
	move_slots.clear()
	retried_moves.clear()
	next_attacker = 0
	for unit in units:
		_apply_attack(unit)


func _apply_move(unit: Node) -> void:
	if move_slots.has(unit):
		var on_failure := _on_move_failed.bind(unit)
		if not unit.horde_move_failed.is_connected(on_failure):
			unit.horde_move_failed.connect(on_failure)
		unit.issue_player_area_move_order(move_slots[unit])
		unit.follows_horde_order = true
	else:
		unit.issue_player_area_hold_order()


func _on_move_failed(unit: Node) -> void:
	if retried_moves.has(unit):
		return
	retried_moves[unit] = true
	# Let the group settle after existing navigation recovery gives up.
	var retry_timer := mission.get_tree().create_timer(MOVE_RETRY_DELAY, false)
	retry_timer.timeout.connect(_retry_move.bind(unit, move_revision), CONNECT_ONE_SHOT)


func _retry_move(unit: Node, revision: int) -> void:
	if order == Order.MOVE and move_revision == revision and is_instance_valid(unit) and (
		move_slots.has(unit) and unit.can_receive_player_orders() and not unit.is_assaulting_building()
		and not unit.follows_horde_order and not is_instance_valid(unit.aggro_target) and is_instance_valid(mission)
		and mission.can_process()
	):
		var previous_slot: Vector2 = move_slots[unit]
		_assign_additional_slot(unit, [previous_slot], true)
		if not move_slots.has(unit):
			move_slots[unit] = previous_slot
		_apply_move(unit)


func _apply_attack(unit: Node) -> void:
	unit.issue_player_attack_order(attack_targets, next_attacker % attack_targets.size())
	unit.follows_horde_order = true
	next_attacker += 1


func refresh_attack_order() -> bool:
	if order != Order.ATTACK:
		return false
	for index in range(attack_targets.size() - 1, -1, -1):
		var target := attack_targets[index]
		if not is_instance_valid(target) or not target.is_alive() or is_instance_valid(target.interior_building):
			attack_targets.remove_at(index)
	if attack_targets.is_empty():
		order = Order.NONE
		return true
	return false


func inherit(unit: Node) -> void:
	if not is_instance_valid(unit) or not unit.can_receive_player_orders():
		return
	refresh_attack_order()
	if order == Order.ATTACK:
		_apply_attack(unit)
	elif order == Order.MOVE:
		retried_moves.erase(unit)
		_assign_additional_slot(unit, [])
		_apply_move(unit)


func _assign_additional_slot(unit: Node, reserved: Array[Vector2], start_outside := false) -> void:
	move_slots.erase(unit)
	for other in move_slots.keys():
		if not is_instance_valid(other) or other.is_dead:
			move_slots.erase(other)
			retried_moves.erase(other)
			continue
		var destination: Vector2 = move_slots[other]
		if other.can_receive_player_orders() and (
			other.follows_horde_order or other.global_position.distance_squared_to(destination) <= MOVE_SLOT_OCCUPANCY_DISTANCE_SQUARED
		):
			reserved.append(destination)
	var newcomers: Array[Node] = [unit]
	var additional: Dictionary = mission.placement.assign_horde_positions(
		move_center, move_radius, newcomers, reserved, start_outside)
	move_slots.merge(additional)


func cancel() -> void:
	assault_feedback = ""
	if order == Order.NONE:
		return
	order = Order.NONE
	move_slots.clear()
	retried_moves.clear()
	attack_targets.clear()
	for unit in mission._available_command_units():
		unit.cancel_horde_order()


func begin_assault(building: InteractiveBuilding) -> void:
	assault_building = building
	assault_elapsed = 0.0
	assault_quantity = 1
	assault_feedback = ""


func update_assault(delta: float, interval: float) -> bool:
	assault_elapsed += delta
	var quantity := 1 + floori(assault_elapsed / interval)
	if quantity == assault_quantity:
		return false
	assault_quantity = quantity
	return true


func reset_assault() -> void:
	assault_building = null
	assault_elapsed = 0.0
	assault_quantity = 0


func confirm_assault() -> bool:
	var building := assault_building
	var requested := assault_quantity
	reset_assault()
	if not is_instance_valid(building):
		return false

	var entrance := building.layout.to_global(building.layout.entrance)
	var candidates: Array[Node] = mission._available_command_units()
	var distances: Dictionary = {}
	for unit in candidates:
		distances[unit] = unit.global_position.distance_squared_to(entrance)
	candidates.sort_custom(func(a: Node, b: Node):
		if distances[a] == distances[b]:
			return a.get_instance_id() < b.get_instance_id()
		return distances[a] < distances[b])

	var quantity := mini(requested, candidates.size())
	for index in range(quantity):
		var unit := candidates[index]
		move_slots.erase(unit)
		unit.issue_player_building_order(building)
	assault_feedback = "Отправлено на штурм: %d" % quantity if quantity > 0 else "Нет доступных зомби"
	return quantity > 0
