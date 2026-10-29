extends Node2D

const TARGET_PERCENT := 80

enum MissionState {
	ACTIVE,
	WON,
}

var villagers: Array[Node] = []
var total_residents: int = 0
var infected_residents: int = 0
var mission_state: MissionState = MissionState.ACTIVE

@onready var residents_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Residents
@onready var infected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Infected
@onready var uninfected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Uninfected
@onready var progress_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Progress
@onready var status_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Status


func _ready() -> void:
	for resident in find_children("*", "", true, false):
		if not resident.has_method("is_converted"):
			continue
		villagers.append(resident)
		if not resident.has_signal("converted"):
			push_error("Mission resident is missing the converted signal: %s" % resident.get_path())
			continue

		var error := resident.connect("converted", _on_resident_converted)
		if error != OK:
			push_error("Could not connect resident conversion signal: %s" % error_string(error))

	total_residents = villagers.size()
	_refresh_mission_progress()


func _on_resident_converted(resident: Node) -> void:
	if not villagers.has(resident):
		return

	_refresh_mission_progress()


func _refresh_mission_progress() -> void:
	infected_residents = 0
	for resident in villagers:
		if is_instance_valid(resident) and resident.call("is_converted"):
			infected_residents += 1

	var uninfected_residents := total_residents - infected_residents
	var progress_percent := 0
	var required_infections := 0
	if total_residents > 0:
		progress_percent = roundi(float(infected_residents * 100) / total_residents)
		required_infections = ceili(float(total_residents * TARGET_PERCENT) / 100.0)

	residents_label.text = "Жители: %d / %d" % [infected_residents, total_residents]
	infected_label.text = "Заражено: %d" % infected_residents
	uninfected_label.text = "Незаражено: %d" % uninfected_residents
	progress_label.text = "Прогресс: %d%%" % progress_percent

	if total_residents == 0:
		status_label.text = "Цель невозможна: жителей нет."
	elif mission_state == MissionState.WON:
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	elif infected_residents >= required_infections:
		mission_state = MissionState.WON
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	else:
		status_label.text = "Цель: заразить %d%% жителей (%d осталось)" % [
			TARGET_PERCENT,
			maxi(required_infections - infected_residents, 0)
		]
