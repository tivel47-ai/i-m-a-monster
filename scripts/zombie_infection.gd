extends RefCounted

const INITIAL_CHARGES := 3
const DURATION := 10.0
const KILLS_PER_CHARGE := 5
const TARGET_ROLES := ["peasant", "artisan"]

var charges := INITIAL_CHARGES
var recovery_progress := 0
var targeting := false


func can_infect(resident: Variant) -> bool:
	return (
		is_instance_valid(resident)
		and str(resident.get_meta("village_role", "")) in TARGET_ROLES
		and resident.can_receive_player_infection()
	)


func infect(resident: Node) -> bool:
	if charges <= 0 or not can_infect(resident) or not resident.apply_player_infection(DURATION):
		return false
	charges -= 1
	if charges == 0:
		targeting = false
	return true


func infect_occupant(building: InteractiveBuilding) -> bool:
	var candidates := building.residents.filter(can_infect)
	return not candidates.is_empty() and infect(candidates.pick_random())


func record_non_converting_kill() -> void:
	recovery_progress += 1
	if recovery_progress == KILLS_PER_CHARGE:
		recovery_progress = 0
		charges += 1
