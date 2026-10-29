extends StaticBody2D

signal converted(villager: Node)

enum InfectionState {
	AVAILABLE,
	IN_COLLISION,
	CONVERTED,
}

const COLLISION_DURATION_SECONDS := 4.0

var infection_state: InfectionState = InfectionState.AVAILABLE
var converted_color: Color
var encounter_owner: Node2D

@onready var polygon: Polygon2D = $Polygon2D
@onready var collision_timer: Timer = $CollisionTimer


func is_available_for_infection() -> bool:
	return infection_state == InfectionState.AVAILABLE


func is_in_collision() -> bool:
	return infection_state == InfectionState.IN_COLLISION


func is_converted() -> bool:
	return infection_state == InfectionState.CONVERTED


func begin_encounter(result_color: Color, zombie: Node2D) -> bool:
	if not is_available_for_infection():
		return false

	infection_state = InfectionState.IN_COLLISION
	encounter_owner = zombie
	converted_color = result_color
	collision_timer.start(COLLISION_DURATION_SECONDS)
	return true


func is_encounter_owner(zombie: Node2D) -> bool:
	return is_in_collision() and encounter_owner == zombie


func cancel_encounter() -> void:
	if not is_in_collision():
		return

	collision_timer.stop()
	infection_state = InfectionState.AVAILABLE
	encounter_owner = null


func _on_collision_timer_timeout() -> void:
	if not is_in_collision():
		return

	infection_state = InfectionState.CONVERTED
	encounter_owner = null
	polygon.color = converted_color
	converted.emit(self)
