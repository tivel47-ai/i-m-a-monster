extends CharacterBody2D
const AUDIO = preload("res://scripts/audio/audio_manager.gd")
const DEFENDER_PROJECTILE = preload("res://scripts/defender_projectile.gd")

const LOCAL_MELEE_ROUTE = preload("res://scripts/local_melee_route.gd")
const PEASANT_VISUAL = preload("res://scripts/peasant_visual.gd")
const ARTISAN_ATLAS = preload("res://assets/sprites/characters/artisan/frames.png")
const GUARD_VISUAL = preload("res://scripts/guard_visual.gd")
const CROSSBOW_VISUAL = preload("res://scripts/crossbow_guard_visual.gd")
const CHURCH_CHARACTER_VISUAL = preload("res://scripts/church_character_visual.gd")
const COMBAT_FLUIDS = preload("res://scripts/combat_fluids.gd")
const MISSION_BALANCE = preload("res://scripts/mission_one_unit_balance.gd")
const UNIT_VISION = preload("res://scripts/unit_vision.gd")
var melee_route: LOCAL_MELEE_ROUTE
var unit_vision: UNIT_VISION
var _body_sprite: Sprite2D
var _civilian_visual: PEASANT_VISUAL
var _guard_visual: GUARD_VISUAL
var _crossbow_visual: CROSSBOW_VISUAL
var _church_visual: CHURCH_CHARACTER_VISUAL
var _bell_pose: Sprite2D

const MOVEMENT_STALL_TIMEOUT := 3.0
const ROUTE_YIELD_DELAY := 0.75
const ROUTE_YIELD_WINDOW := 0.75
const RESIDENT_BODY_LAYER := 4
const HEALTH_BAR_Y := -16.25

var visual_ui_offset_y := 0.0

signal converted(villager: Node)
signal died(villager: Node)
signal threat_recognized(zombie: Node2D)
signal warning_attempted(villager: Node2D, threat_position: Vector2)
signal encounter_started(zombie: Node2D)

enum InfectionState {
	AVAILABLE,
	IN_COLLISION,
	TRANSFORMING,
	CONVERTED,
	DEAD,
}

enum Activity { NONE = -1, HOME, WORK, SOCIAL, WANDER }
enum NavigationResult { MOVING, ARRIVED, FAILED }
enum InfectionSource { NONE, ZOMBIE_COMBAT, PLAYER_ABILITY }

@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var transformation_duration: float = 2.0
@export var autonomous_movement_enabled: bool = true
@export var points_of_interest_path: NodePath
@export var move_speed: float = 35.0
@export var wait_duration_min: float = 2.0
@export var wait_duration_max: float = 5.0
@export var arrival_tolerance: float = 4.0
@export var guard_variant: StringName
@export_group("Defensive ranged equipment")
## Opt-in equipment; existing maps keep their current melee assignments.
@export var defense_ranged_weapon: bool = false
## Negative values preserve the shared attack profile for legacy equipment.
@export var defense_ranged_damage: float = -1.0
@export var defense_ranged_interval: float = -1.0
@export var defense_weapon_range: float = 150.0
@export var defense_projectile_speed: float = 280.0
var ranged_ready_at: float = 0.0

@export_group("Peaceful activities")
@export_enum("Villager", "Peasant", "Craftsman") var civilian_profile: String = "Villager"
@export var home_point_path: NodePath
@export var work_point_path: NodePath
@export var home_weight: float = 25.0
@export var work_weight: float = 45.0
@export var social_weight: float = 20.0
@export var wander_weight: float = 10.0
@export var home_duration: Vector2 = Vector2(12.0, 24.0)
@export var work_duration: Vector2 = Vector2(18.0, 36.0)
@export var social_duration: Vector2 = Vector2(9.0, 18.0)
@export var wander_duration: Vector2 = Vector2(6.0, 12.0)

@export_group("Activity zones")
## Explicit assignments only; empty keeps the existing marker-based behavior.
@export var activity_zone_paths: Array[NodePath] = []
## Functional shelter markers may remain available without serving peaceful AI.
@export var marker_activity_fallback_enabled: bool = true
@export var preferred_district: StringName
@export_range(1, 10, 0.1) var district_zone_preference: float = 3.0
## Zero disables distance preference; otherwise this is the distance falloff scale.
@export_range(0, 3000, 10) var nearby_zone_distance: float = 0.0
## X: radius factor, Y: pause-duration factor, Z: movement-probability factor.
@export var home_local_rules: Vector3 = Vector3(0.65, 1.5, 0.6)
@export var work_local_rules: Vector3 = Vector3(0.5, 2.0, 0.4)
@export var social_local_rules: Vector3 = Vector3(0.8, 1.0, 1.2)
@export var wander_local_rules: Vector3 = Vector3(1.3, 0.5, 1.8)
@export_range(0, 1, 0.01) var local_long_move_chance: float = 0.1

var _using_zone: bool = false
var current_zone: ActivityZone2D
var local_wait_remaining: float = 0.0
var _last_local_origin: Vector2 = Vector2.INF
var current_activity: Activity = Activity.NONE
var is_performing_activity: bool = false

var has_destination: bool = false
var destination: Vector2
var wait_remaining: float = 0.0
var progress_position: Vector2
var stalled_seconds: float = 0.0
var _route_waypoint := Vector2.INF
var _route_best_distance := INF
var _route_stalled_seconds := 0.0
var _route_yield_remaining := 0.0
var _route_step_frame := -2
var _route_yield_velocity := Vector2.ZERO

var infection_state: InfectionState = InfectionState.AVAILABLE
var infection_source := InfectionSource.NONE
var infected_by_player_zombie := false
var immediate_combat_conversion := false
var player_infection_timer: Timer
var killed_by_player_monster := false
var current_health: float
var _audio_step_distance := 0.0
var converted_color: Color
var encounter_participants: Array[Node2D] = []
var building_task: Node
var interior_building: Node:
	set(value):
		interior_building = value
		if has_player_infection():
			queue_redraw()
		for indicator in [threat_detection, threat_reaction, local_warning]:
			if is_instance_valid(indicator):
				indicator.queue_redraw()
		if is_instance_valid(value) and is_instance_valid(priest_routine) and is_instance_valid(priest_routine.sermon_label):
			priest_routine.sermon_label.hide()
var defense: Node
var reinforcement_squad: Node
var guard_ai: Node
var escort: Node
var priest_ai: Node
var _balance_profile: Dictionary = {}
@onready var priest_guard = get_node_or_null("PriestGuard")

@onready var polygon: Polygon2D = $Polygon2D
@onready var transformation_timer: Timer = $TransformationTimer
@onready var encounter_attack_timer: Timer = Timer.new()
@onready var death_marker_a: Line2D = $DeathMarkerA
@onready var death_marker_b: Line2D = $DeathMarkerB
@onready var _audio := AUDIO.service() as AUDIO
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var threat_detection = $ThreatDetection
@onready var threat_reaction = $ThreatReaction
@onready var local_warning = $LocalWarning
@onready var guard_patrol = get_node_or_null("GuardPatrol")
@onready var priest_routine = get_node_or_null("PriestRoutine")


func private_shelter_marker() -> Node2D:
	if str(get_meta("village_role", "")) == "artisan":
		return get_node_or_null(work_point_path) as Node2D if not work_point_path.is_empty() else null
	return get_node_or_null(home_point_path) as Node2D if not home_point_path.is_empty() else null


func configure_mission_balance() -> void:
	var type_id := StringName(get_meta("village_role", ""))
	if type_id == &"guard":
		if not MISSION_BALANCE.GUARD_VARIANTS.has(guard_variant):
			guard_variant = MISSION_BALANCE.SHIELD
		_balance_profile = MISSION_BALANCE.GUARD_VARIANTS[guard_variant]
		defense_ranged_weapon = guard_variant == MISSION_BALANCE.CROSSBOW
		if defense_ranged_weapon:
			defense_ranged_damage = _balance_profile.ranged_damage
			defense_ranged_interval = _balance_profile.ranged_interval
			defense_weapon_range = _balance_profile.ranged_distance
			defense_projectile_speed = _balance_profile.projectile_speed
	else:
		_balance_profile = MISSION_BALANCE.HUMANS.get(type_id, {})
	if _balance_profile.is_empty():
		return
	max_health = _balance_profile.health
	attack_damage = _balance_profile.damage
	attack_interval = _balance_profile.interval
	move_speed = _balance_profile.peaceful


func tactical_move_speed(fallback: float) -> float:
	return _balance_profile.get("tactical", fallback)


func guard_pursuit_limit(limit: float) -> float:
	return limit * _balance_profile.get("pursuit_factor", 1.0)


func guard_support_priority() -> float:
	return _balance_profile.get("support_priority", 0.0)


func has_mission_crossbow() -> bool:
	return guard_variant == MISSION_BALANCE.CROSSBOW and _balance_profile.has("ranged_damage")


func try_fire_defense_bolt(enemy: Node2D) -> bool:
	if not defense_ranged_weapon or not is_instance_valid(defense) or not can_process():
		return false
	if not is_available_for_infection() or is_in_collision() or has_destination or not velocity.is_zero_approx():
		return false
	if not threat_detection._is_visible_target(enemy):
		return false
	var offset := enemy.global_position - global_position
	if offset.length_squared() > defense_weapon_range * defense_weapon_range or offset.is_zero_approx():
		return false
	if unit_vision != null:
		unit_vision.face_at_rest(offset)
	if _crossbow_visual != null:
		_crossbow_visual.hold_aim()
	if defense.elapsed < ranged_ready_at:
		return true
	var interval := defense_ranged_interval if defense_ranged_interval >= 0.0 else attack_interval
	ranged_ready_at = defense.elapsed + maxf(interval, 0.01)
	var battlefield: Node2D = defense.get_parent()
	if is_instance_valid(interior_building) and battlefield.get_meta(&"building_depth_sort", false):
		battlefield = interior_building.layout.airborne_effect_layer()
	var bolt := DEFENDER_PROJECTILE.new()
	bolt.position = battlefield.to_local(global_position)
	bolt.direction = offset.normalized()
	bolt.damage = defense_ranged_damage if defense_ranged_damage >= 0.0 else attack_damage
	bolt.speed = defense_projectile_speed
	bolt.remaining = defense_weapon_range
	bolt.interior_building = interior_building
	if _crossbow_visual != null:
		_crossbow_visual.play_shot(offset, defense.elapsed)
		bolt.display_origin_offset = _crossbow_visual.bolt_display_offset()
		bolt.display_convergence_distance = maxf(offset.length(), 1.0)
	battlefield.add_child(bolt)
	return true


func apply_armed_combat_profile() -> void:
	if not _balance_profile.has("armed_damage"):
		return
	attack_damage = _balance_profile.armed_damage
	attack_interval = _balance_profile.armed_interval
	if not encounter_attack_timer.is_stopped():
		var elapsed := encounter_attack_timer.wait_time - encounter_attack_timer.time_left
		encounter_attack_timer.start(maxf(attack_interval - elapsed, 0.01))
	encounter_attack_timer.wait_time = attack_interval


func _ready() -> void:
	if LOCAL_MELEE_ROUTE.enabled_for(self):
		melee_route = LOCAL_MELEE_ROUTE.new()
	add_to_group("activity_zone_residents")
	current_health = maxf(max_health, 0.0)
	if not _balance_profile.is_empty():
		navigation_agent.max_speed = move_speed
		threat_reaction.fleeing_speed = _balance_profile.get("fleeing", threat_reaction.fleeing_speed)
	encounter_attack_timer.name = "EncounterAttackTimer"
	if _can_counterattack():
		encounter_attack_timer.wait_time = maxf(attack_interval, 0.01)
	encounter_attack_timer.timeout.connect(_on_encounter_attack_timer_timeout)
	add_child(encounter_attack_timer)
	_setup_body_sprite()
	# Crossbow tactics already set the resident's heading on firing and after disengagement.
	var vision_visual := _body_sprite if _crossbow_visual == null else null
	unit_vision = UNIT_VISION.attach(self, vision_visual, UNIT_VISION.RESIDENT_RADIUS,
		priest_routine != null or get_meta("village_role", "") == "priest")
	if current_health == 0.0:
		_die()


func _setup_body_sprite() -> void:
	var role := StringName(get_meta("village_role", ""))
	if role in [&"priest", &"priest_guard"]:
		if _sprite_map(&"church_character_sprites") == null:
			return
		_church_visual = CHURCH_CHARACTER_VISUAL.new()
		_church_visual.is_escort = role == &"priest_guard"
		_church_visual.name = "PriestGuardVisual" if _church_visual.is_escort else "PriestVisual"
		_body_sprite = _church_visual
		visual_ui_offset_y = CHURCH_CHARACTER_VISUAL.HEALTH_BAR_Y - HEALTH_BAR_Y
	elif role == &"guard":
		if _sprite_map(&"guard_sprites") == null:
			return
		if guard_variant == MISSION_BALANCE.CROSSBOW:
			_crossbow_visual = CROSSBOW_VISUAL.new()
			_crossbow_visual.name = "CrossbowVisual"
			_body_sprite = _crossbow_visual
			visual_ui_offset_y = CROSSBOW_VISUAL.HEALTH_BAR_Y - HEALTH_BAR_Y
		elif defense_ranged_weapon:
			return
		else:
			_guard_visual = GUARD_VISUAL.new()
			_guard_visual.name = "GuardVisual"
			_guard_visual.appearance = guard_variant if GUARD_VISUAL.ATLASES.has(guard_variant) else GUARD_VISUAL.SHIELD
			_body_sprite = _guard_visual
			visual_ui_offset_y = _guard_visual.health_bar_y() - HEALTH_BAR_Y
	elif civilian_profile == "Peasant" and _sprite_map(&"peasant_sprites") != null:
		_setup_civilian_sprite("PeasantVisual")
	elif civilian_profile == "Craftsman" and _sprite_map(&"artisan_sprites") != null:
		_setup_civilian_sprite("ArtisanVisual", ARTISAN_ATLAS)
	else:
		return
	add_child(_body_sprite)
	polygon.hide()


func _setup_civilian_sprite(visual_name: String, atlas: Texture2D = null) -> void:
	_civilian_visual = PEASANT_VISUAL.new()
	_civilian_visual.name = visual_name
	_civilian_visual.texture = atlas
	_body_sprite = _civilian_visual
	visual_ui_offset_y = PEASANT_VISUAL.COMBAT_HEALTH_BAR_Y - HEALTH_BAR_Y


func _sprite_map(flag: StringName) -> Node:
	var ancestor := get_parent()
	while ancestor != null and not ancestor.get_meta(flag, false):
		ancestor = ancestor.get_parent()
	return ancestor


func contains_visual_point(world_position: Vector2) -> bool:
	var sprite := _bell_pose if _bell_pose != null and _bell_pose.visible else _body_sprite
	var sprite_visible := sprite != null and sprite.is_visible_in_tree()
	if sprite_visible and sprite.is_pixel_opaque(sprite.to_local(world_position)):
		return true
	return (sprite_visible or polygon.is_visible_in_tree()) and Geometry2D.is_point_in_polygon(
		polygon.to_local(world_position) - polygon.offset, polygon.polygon)


func bell_pose_role() -> StringName:
	if _crossbow_visual != null:
		return MISSION_BALANCE.CROSSBOW
	if _guard_visual != null:
		return _guard_visual.appearance
	return StringName(get_meta("village_role", "peasant"))


func show_bell_pose(atlas: Texture2D, frame: Rect2, feet: Vector2, direction := Vector2.ZERO) -> void:
	if unit_vision != null:
		unit_vision.face_for_pose(direction)
	if _bell_pose == null:
		_bell_pose = Sprite2D.new()
		_bell_pose.name = "BellPullPose"
		_bell_pose.centered = false
		_bell_pose.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_bell_pose.region_enabled = true
		_bell_pose.region_filter_clip_enabled = true
		_bell_pose.scale = Vector2.ONE * (PEASANT_VISUAL.WORLD_HEIGHT / PEASANT_VISUAL.FRAME_HEIGHT)
		_bell_pose.position.y = PEASANT_VISUAL.FEET_Y
		add_child(_bell_pose)
	_bell_pose.texture = atlas
	_bell_pose.region_rect = frame
	_bell_pose.offset = -feet
	if _body_sprite != null:
		_body_sprite.hide()
	else:
		polygon.hide()
	_bell_pose.show()


func clear_bell_pose() -> void:
	if _bell_pose == null or not _bell_pose.visible: return
	if unit_vision != null:
		unit_vision.face_for_pose(Vector2.ZERO)
	_bell_pose.hide()
	if infection_state == InfectionState.CONVERTED: return
	if _body_sprite == null:
		polygon.show()
	else:
		_body_sprite.show()


func _physics_process(delta: float) -> void:
	if is_instance_valid(building_task):
		return
	if is_instance_valid(defense) and defense.operating_bell(self):
		_stop_movement()
		return
	if (is_instance_valid(defense) and is_instance_valid(defense.last_stand)
		and defense.last_stand.operator == self and not defense.last_stand.beacon_lit
		and is_available_for_infection()):
		_stop_movement()
		return
	if defense != null and priest_guard != null and autonomous_movement_enabled:
		if priest_guard.update_ai(delta): return
	if defense != null and guard_ai != null and autonomous_movement_enabled:
		if guard_ai.update_ai(delta): return
	if defense != null and defense.organized != null and autonomous_movement_enabled:
		if defense.organized.update_actor(self, delta): return
	if escort != null and autonomous_movement_enabled and infection_state == InfectionState.IN_COLLISION:
		escort.update_combat()
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE:
		threat_reaction.cancel_response()
		_stop_movement()
		return
	var navigation_map := navigation_agent.get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return
	if is_instance_valid(priest_ai) and priest_ai.update_priest(delta):
		return
	if escort != null and escort.update_escort(delta): return
	if (not has_tactical_controller()) and threat_reaction.update_response(delta):
		return
	if guard_patrol!=null and guard_patrol.update_patrol(delta):
		return
	if _using_zone:
		if not is_instance_valid(current_zone) or not current_zone.allows_resident(self) or not current_zone.has_valid_polygon():
			_begin_wait()
			return
		if is_performing_activity:
			_update_zone_activity(delta)
			return
	if not has_destination:
		wait_remaining = maxf(wait_remaining - delta, 0.0)
		if wait_remaining == 0.0:
			_choose_destination(navigation_map)
		return
	var result := _advance_navigation(destination, move_speed, delta)
	if result != NavigationResult.MOVING:
		_begin_wait(result == NavigationResult.ARRIVED)


func _uses_local_melee_route(enemy: Node2D) -> bool:
	return melee_route != null and melee_route.applies(self, enemy, enemy.INFECTION_DISTANCE)


func _advance_melee_route(
	enemy: Node2D, speed: float, delta: float, home := Vector2.INF, leash := INF
) -> bool:
	melee_route.update(self, enemy, enemy.INFECTION_DISTANCE, home, leash)
	if melee_route.path.is_empty():
		return false
	if has_destination:
		_stop_movement()
	melee_route.move(self, navigation_agent, speed, delta)
	return true


func _advance_navigation(goal: Vector2, speed: float, delta: float) -> NavigationResult:
	navigation_agent.max_speed = maxf(speed, 0.0)
	navigation_agent.target_desired_distance = maxf(arrival_tolerance, 0.5)
	if global_position.distance_to(goal) <= navigation_agent.target_desired_distance:
		return NavigationResult.ARRIVED
	if global_position.distance_squared_to(progress_position) >= 4.0:
		progress_position = global_position
		stalled_seconds = 0.0
	else:
		stalled_seconds += delta
	if stalled_seconds >= MOVEMENT_STALL_TIMEOUT:
		return NavigationResult.FAILED
	var next_position := navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		return NavigationResult.FAILED
	if (has_destination and not _using_zone and not is_instance_valid(interior_building)
		and is_instance_valid(defense) and is_instance_valid(defense.last_stand)):
		_track_route_progress(next_position, speed, delta)
		if _route_stalled_seconds >= MOVEMENT_STALL_TIMEOUT:
			return NavigationResult.FAILED
	navigation_agent.velocity = global_position.direction_to(next_position) * maxf(speed, 0.0)
	return NavigationResult.MOVING


func _track_route_progress(waypoint: Vector2, speed: float, delta: float) -> void:
	var frame := Engine.get_physics_frames()
	var distance := global_position.distance_to(waypoint)
	if _route_step_frame < frame - 1 or not _route_waypoint.is_equal_approx(waypoint):
		_route_waypoint = waypoint
		_route_best_distance = distance
		_route_yield_remaining = 0.0
		_route_stalled_seconds = 0.0
	elif distance <= _route_best_distance - 2.0:
		_route_best_distance = distance
		_route_stalled_seconds = 0.0
	else:
		_route_stalled_seconds += delta
	_route_step_frame = frame
	_route_yield_velocity = Vector2.ZERO
	if _route_stalled_seconds >= ROUTE_YIELD_DELAY and _route_stalled_seconds - delta < ROUTE_YIELD_DELAY:
		_route_yield_remaining = ROUTE_YIELD_WINDOW
	if _route_yield_remaining > 0.0 and delta > 0.0:
		_route_yield_remaining = maxf(_route_yield_remaining - delta, 0.0)
		# Stay on the current navigation segment while passing friendly bodies.
		_route_yield_velocity = (waypoint - global_position).limit_length(maxf(speed, 0.0) * delta) / delta


func _choose_destination(navigation_map: RID) -> void:
	var points := get_node_or_null(points_of_interest_path) if not points_of_interest_path.is_empty() else null
	var options: Array[Dictionary] = []
	var total_weight := 0.0
	for activity in [Activity.HOME, Activity.WORK, Activity.SOCIAL, Activity.WANDER]:
		var weight := _activity_weight(activity)
		if weight <= 0.0:
			continue
		var candidates: Array[Dictionary] = []
		for path in activity_zone_paths:
			var zone := get_node_or_null(path) as ActivityZone2D if not path.is_empty() else null
			if zone == null or zone.activity != activity or not zone.allows_resident(self):
				continue
			var sample := zone.sample_destination(self, _zone_reservations(zone), null,
				maxf(arrival_tolerance, 0.5) + 1.0, maxf(arrival_tolerance, 0.5) + 1.0)
			if not sample.is_empty():
				candidates.append({"point": sample[0], "zone": zone})
		# Prefer assigned zones; unavailable assignments retain safe marker fallback.
		if candidates.is_empty() and marker_activity_fallback_enabled:
			for candidate in _activity_points(activity, points):
				if _is_destination_valid(candidate.global_position, navigation_map):
					candidates.append({"point": candidate.global_position, "zone": null})
		if not candidates.is_empty():
			options.append({"activity": activity, "weight": weight, "points": candidates})
			total_weight += weight
	if priest_routine != null and priest_routine.routine_enabled:
		options = priest_routine.filter_options(options)
		total_weight = 0.0
		for option in options: total_weight += float(option.weight)
	if options.is_empty():
		_begin_wait()
		return
	var roll := randf() * total_weight
	var selected: Dictionary = options[-1]
	for option in options:
		roll -= float(option["weight"])
		if roll < 0.0:
			selected = option
			break
	current_activity = selected["activity"]
	is_performing_activity = false
	var candidates: Array = selected["points"]
	var target := _choose_activity_target(candidates)
	current_zone = target["zone"]
	_using_zone = current_zone != null
	wait_remaining = 0.0
	local_wait_remaining = 0.0
	_last_local_origin = Vector2.INF
	_set_peaceful_destination(target["point"])


func _zone_preference_weight(zone: ActivityZone2D) -> float:
	var weight := 1.0
	if not preferred_district.is_empty() and zone.district_id == preferred_district:
		weight *= maxf(district_zone_preference, 1.0)
	if nearby_zone_distance > 0.0:
		weight /= 1.0 + global_position.distance_to(zone.global_position) / nearby_zone_distance
	return weight


func _choose_activity_target(candidates: Array) -> Dictionary:
	# Neutral assignments retain Stage 2's uniform choice and random sequence.
	if preferred_district.is_empty() and nearby_zone_distance <= 0.0:
		return candidates.pick_random()
	var total := 0.0
	for candidate in candidates:
		total += _zone_preference_weight(candidate["zone"]) if candidate["zone"] != null else 1.0
	var roll := randf() * total
	for candidate in candidates:
		roll -= _zone_preference_weight(candidate["zone"]) if candidate["zone"] != null else 1.0
		if roll < 0.0: return candidate
	return candidates[-1]


func _activity_points(activity: Activity, points: Node) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	if points == null:
		return result
	if activity == Activity.HOME or activity == Activity.WORK:
		var path := home_point_path if activity == Activity.HOME else work_point_path
		var marker := get_node_or_null(path) if not path.is_empty() else null
		if marker is Marker2D:
			result.append(marker)
	else:
		for marker in points.get_children():
			if marker is Marker2D and (activity == Activity.WANDER or marker.is_in_group("civilian_social_points")):
				result.append(marker)
	return result


func _activity_weight(activity: Activity) -> float:
	match activity:
		Activity.HOME: return maxf(home_weight, 0.0)
		Activity.WORK: return maxf(work_weight, 0.0)
		Activity.SOCIAL: return maxf(social_weight, 0.0)
		Activity.WANDER: return maxf(wander_weight, 0.0)
	return 0.0


func _activity_duration(activity: Activity) -> Vector2:
	if is_instance_valid(current_zone) and current_zone.activity == activity and current_zone.duration_override != Vector2.ZERO:
		return current_zone.duration_override
	if priest_routine != null and priest_routine.routine_enabled:
		return priest_routine.activity_duration(current_zone, Vector2(wait_duration_min, wait_duration_max))
	match activity:
		Activity.HOME: return home_duration
		Activity.WORK: return work_duration
		Activity.SOCIAL: return social_duration
		Activity.WANDER: return wander_duration
	return Vector2(wait_duration_min, wait_duration_max)


func _is_destination_valid(point: Vector2, navigation_map: RID) -> bool:
	return not _validated_path_to(point, navigation_map).is_empty()


func _validated_path_to(point: Vector2, navigation_map: RID) -> PackedVector2Array:
	if global_position.distance_to(point) <= maxf(arrival_tolerance, 0.5):
		return PackedVector2Array()
	if NavigationServer2D.map_get_closest_point(navigation_map, point).distance_to(point) > 1.0:
		return PackedVector2Array()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = $CollisionShape2D.shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return PackedVector2Array()
	var path := NavigationServer2D.map_get_path(navigation_map, global_position, point, true, navigation_agent.navigation_layers)
	return path if not path.is_empty() and path[-1].distance_to(point) <= 1.0 else PackedVector2Array()


func _stop_movement() -> void:
	if guard_patrol!=null: guard_patrol.cancel_patrol()
	if _using_zone:
		wait_remaining = 0.0
	_using_zone = false
	current_zone = null
	local_wait_remaining = 0.0
	_last_local_origin = Vector2.INF
	has_destination = false
	current_activity = Activity.NONE
	is_performing_activity = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO


func _begin_wait(arrived: bool = false) -> void:
	var activity := current_activity if arrived else Activity.NONE
	var zone := current_zone if arrived and is_instance_valid(current_zone) else null
	_stop_movement()
	current_zone = zone
	_using_zone = zone != null
	current_activity = activity
	is_performing_activity = activity != Activity.NONE
	var duration := _activity_duration(activity)
	var minimum := maxf(duration.x, 0.0)
	wait_remaining = randf_range(minimum, maxf(duration.y, minimum))
	if current_zone != null:
		_begin_local_pause()


func _local_rules(activity: Activity) -> Vector3:
	if priest_routine != null and priest_routine.routine_enabled:
		var base := _civilian_local_rules(activity)
		return priest_routine.local_rules(current_zone, base)
	return _civilian_local_rules(activity)


func _civilian_local_rules(activity: Activity) -> Vector3:
	match activity:
		Activity.HOME: return home_local_rules
		Activity.WORK: return work_local_rules
		Activity.SOCIAL: return social_local_rules
		Activity.WANDER: return wander_local_rules
	return Vector3.ONE


func _zone_local_speed() -> float:
	var speed := minf(maxf(current_zone.local_move_speed, 0.0), maxf(move_speed, 0.0) * 0.9)
	if priest_routine != null and priest_routine.routine_enabled and priest_routine.zone_territory(current_zone) in [0, 1]:
		speed = minf(speed, maxf(priest_routine.primary_local_speed, 0.0))
	return speed


func _set_peaceful_destination(point: Vector2) -> void:
	destination = point
	navigation_agent.target_position = point
	has_destination = true
	progress_position = global_position
	stalled_seconds = 0.0


func _zone_reservations(zone: ActivityZone2D) -> PackedVector2Array:
	var positions := PackedVector2Array()
	for resident in get_tree().get_nodes_in_group("activity_zone_residents"):
		if resident == self or resident.is_queued_for_deletion() or resident.get_world_2d() != get_world_2d():
			continue
		if is_instance_valid(resident.current_zone) and resident.has_destination and resident.is_available_for_infection() and zone.contains_world_point(resident.destination):
			positions.append(resident.destination)
	return positions


func _begin_local_pause() -> void:
	has_destination = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO
	stalled_seconds = 0.0
	var interval := current_zone.local_pause_duration * maxf(_local_rules(current_activity).y, 0.0)
	var minimum := maxf(interval.x, 0.25)
	local_wait_remaining = randf_range(minimum, maxf(interval.y, minimum))


func _update_zone_activity(delta: float) -> void:
	if not current_zone.contains_world_point(global_position):
		_begin_wait()
		return
	# One activity clock covers every local route and every intentional pause.
	wait_remaining = maxf(wait_remaining - delta, 0.0)
	if wait_remaining == 0.0:
		if priest_routine != null and priest_routine.routine_enabled:
			priest_routine.activity_completed(current_zone)
		_stop_movement()
		return
	_advance_local_zone_cycle(delta)


func _advance_local_zone_cycle(delta: float) -> void:
	if has_destination:
		var result := _advance_navigation(destination, _zone_local_speed(), delta)
		if result != NavigationResult.MOVING:
			_begin_local_pause()
		return
	local_wait_remaining = maxf(local_wait_remaining - delta, 0.0)
	if local_wait_remaining > 0.0:
		return
	var rules := _local_rules(current_activity)
	var probability := clampf(current_zone.local_move_probability * rules.z, 0.0, 1.0)
	if _zone_local_speed() <= 0.0 or randf() >= probability:
		_begin_local_pause()
		return
	var radius := maxf(current_zone.local_move_radius * rules.x, 0.0)
	if randf() < clampf(local_long_move_chance, 0.0, 1.0):
		radius *= 1.8
	var sample := current_zone.sample_local_destination(self, radius,
		maxf(arrival_tolerance * 3.0, 10.0), _last_local_origin, _zone_reservations(current_zone))
	if sample.is_empty():
		_begin_local_pause()
		return
	_last_local_origin = global_position
	_set_peaceful_destination(sample[0])


func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if is_instance_valid(building_task):
		return
	if (
		autonomous_movement_enabled and infection_state == InfectionState.AVAILABLE
		and melee_route != null and not melee_route.path.is_empty()
		and melee_route.last_update == Engine.get_physics_frames()
	):
		return
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE or not (has_destination or threat_reaction.has_route):
		velocity = Vector2.ZERO
		return
	if _using_zone and not is_instance_valid(current_zone):
		velocity = Vector2.ZERO
		return
	if is_performing_activity and is_instance_valid(current_zone) and not threat_reaction.has_route:
		# Bound avoidance/slide displacement by the distance to any polygon edge.
		# Geometry only: no per-frame path or physics-space queries.
		var clearance := maxf(current_zone.distance_to_boundary(global_position) - 0.05, 0.0)
		safe_velocity = safe_velocity.limit_length(clearance / maxf(get_physics_process_delta_time(), 0.000001))
	if _route_step_frame == Engine.get_physics_frames() and not _route_yield_velocity.is_zero_approx():
		var mask := collision_mask
		set_collision_mask_value(RESIDENT_BODY_LAYER, false)
		velocity = _route_yield_velocity * barricade_speed_factor()
		_move_with_audio_steps()
		collision_mask = mask
		return
	velocity = safe_velocity * barricade_speed_factor()
	_move_with_audio_steps()


func _move_with_audio_steps() -> void:
	var before := global_position
	var speed := velocity.length()
	move_and_slide()
	if speed < 2.0 or is_instance_valid(interior_building) or (_audio == null or not _audio.owns(self)) \
		or get_meta("village_role", &"peasant") not in [&"peasant", &"artisan"]:
		_audio_step_distance = 0.0
		return
	var moved := global_position.distance_to(before)
	if moved > speed * get_physics_process_delta_time() + 0.5:
		_audio_step_distance = 0.0
		return
	_audio_step_distance += moved
	var stride := lerpf(16.0, 24.0, smoothstep(45.0, 85.0, speed))
	if _audio_step_distance < stride:
		return
	_audio_step_distance -= stride
	var terrain = defense.get_parent().get_node_or_null("Ground") if is_instance_valid(defense) else null
	if terrain != null and terrain.has_method("audio_surface") and terrain.audio_surface(global_position) == &"dirt":
		_audio.play_at(&"movement.footstep.dirt.light", global_position, get_instance_id())


func barricade_speed_factor() -> float:
	return defense.crossing_speed(self) if is_instance_valid(defense) else 1.0


func has_tactical_controller() -> bool:
	if is_instance_valid(priest_ai) and priest_ai.alarm_active():
		return true
	return priest_guard != null or (guard_ai != null and guard_ai.enabled) or (defense != null and defense.organized != null and defense.organized.active())


func get_recognized_threat() -> Node2D:
	return threat_detection.get_recognized_target()


func _on_threat_recognized(zombie: Node2D) -> void:
	if is_available_for_infection():
		if not has_tactical_controller(): threat_reaction.recognize_threat(zombie)
		threat_recognized.emit(zombie)


func _on_warning_attempted(threat_position: Vector2) -> void:
	if is_available_for_infection():
		warning_attempted.emit(self, threat_position)


func is_available_for_infection() -> bool:
	return infection_state == InfectionState.AVAILABLE and current_health > 0.0


func is_in_collision() -> bool:
	return not encounter_participants.is_empty()


func can_join_encounter() -> bool:
	return (
		current_health > 0.0
		and infection_state in [InfectionState.IN_COLLISION, InfectionState.TRANSFORMING]
		and (infection_state != InfectionState.TRANSFORMING or not encounter_participants.is_empty())
	)


func is_converted() -> bool:
	return infection_state == InfectionState.CONVERTED


func is_dead() -> bool:
	return infection_state == InfectionState.DEAD


func is_alive() -> bool:
	return (
		infection_state != InfectionState.DEAD
		and infection_state != InfectionState.CONVERTED
	)


func has_player_infection() -> bool:
	return infection_source == InfectionSource.PLAYER_ABILITY and is_alive()


func can_receive_player_infection() -> bool:
	return (
		current_health > 0.0
		and infection_state in [InfectionState.AVAILABLE, InfectionState.IN_COLLISION]
		and infection_source == InfectionSource.NONE
	)


func apply_player_infection(duration: float) -> bool:
	if not can_receive_player_infection():
		return false
	infection_source = InfectionSource.PLAYER_ABILITY
	player_infection_timer = Timer.new()
	player_infection_timer.one_shot = true
	player_infection_timer.timeout.connect(_complete_conversion)
	add_child(player_infection_timer)
	player_infection_timer.start(duration)
	queue_redraw()
	return true


func take_damage(amount: float, attacker: Node = null, organic_melee := false) -> void:
	if not is_alive() or current_health <= 0.0 or amount <= 0.0:
		return

	threat_reaction.interrupt_warning()
	current_health = maxf(current_health - amount, 0.0)
	if organic_melee and _audio != null and _audio.owns(self) \
		and get_meta("village_role", &"peasant") in [&"peasant", &"artisan", &"priest"]:
		_audio.play_at(&"combat.impact.flesh", global_position, get_instance_id(), interior_building)
	queue_redraw()
	if current_health > 0.0:
		_show_blood_hit(attacker, false)
		if _church_visual != null:
			_church_visual.play_hurt()
		elif _civilian_visual != null:
			_civilian_visual.play_hurt()
		elif _crossbow_visual != null:
			_crossbow_visual.play_hurt()
		return

	if infection_state == InfectionState.TRANSFORMING:
		if immediate_combat_conversion:
			_complete_conversion()
		else:
			_end_encounter()
	else:
		_show_blood_hit(attacker, true)
		_die(attacker)


func _show_blood_hit(attacker: Node, lethal: bool) -> void:
	var fluids = COMBAT_FLUIDS.for_actor(self)
	if fluids == null:
		return
	var direction := Vector2.ZERO
	if is_instance_valid(attacker) and attacker is Node2D:
		direction = global_position - attacker.global_position
	var height := PEASANT_VISUAL.WORLD_HEIGHT if _body_sprite != null else 15.6
	fluids.hit(self, COMBAT_FLUIDS.Fluid.BLOOD, direction, lethal, height)


func _leave_blood_pool() -> void:
	var fluids = COMBAT_FLUIDS.for_actor(self)
	if fluids != null:
		fluids.settled(self, COMBAT_FLUIDS.Fluid.BLOOD, _body_sprite)


func receive_knockback(motion: Vector2) -> void:
	move_and_collide(motion)


func receive_zombie_attack(amount: float, chance: float, zombie: Node2D, splash := false) -> void:
	if (
		not is_alive()
		or current_health <= 0.0
		or (not splash and not encounter_participants.has(zombie))
		or amount <= 0.0
	):
		return

	var can_be_infected := infection_state == InfectionState.IN_COLLISION or (
		splash and infection_state == InfectionState.AVAILABLE)
	if can_be_infected and infection_source == InfectionSource.NONE and randf() < clampf(chance, 0.0, 1.0):
		var zombie_visual := zombie.get_node_or_null("Polygon2D") as Polygon2D
		if zombie_visual != null:
			converted_color = zombie_visual.color
		_start_transformation(zombie, splash)

	take_damage(amount, zombie, not splash)


func _start_transformation(zombie: Node2D = null, splash := false) -> void:
	if infection_source != InfectionSource.NONE:
		return
	if infection_state != InfectionState.IN_COLLISION and not (splash and infection_state == InfectionState.AVAILABLE):
		return

	infection_state = InfectionState.TRANSFORMING
	if _audio != null and _audio.owns(self):
		_audio.stop_source_event(&"human.civilian.fear", get_instance_id())
	infection_source = InfectionSource.ZOMBIE_COMBAT
	infected_by_player_zombie = is_instance_valid(zombie) and zombie.is_in_group("player_units")
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
	_stop_movement()
	transformation_timer.wait_time = maxf(transformation_duration, 0.01)
	transformation_timer.start()


func _die(attacker: Node = null) -> void:
	if not is_alive():
		return
	if has_player_infection():
		_complete_conversion()
		return

	killed_by_player_monster = is_instance_valid(attacker) and attacker.is_in_group("player_units")
	infection_state = InfectionState.DEAD
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
	_stop_movement()
	navigation_agent.avoidance_enabled = false
	current_health = 0.0
	transformation_timer.stop()
	_end_encounter()
	if _sprite_map(&"building_depth_sort") == null:
		z_index = 0
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	if _church_visual != null:
		clear_bell_pose()
		_church_visual.death_finished.connect(_leave_blood_pool, CONNECT_ONE_SHOT)
		_church_visual.play_death()
	elif _guard_visual != null:
		_guard_visual.death_finished.connect(_leave_blood_pool, CONNECT_ONE_SHOT)
		_guard_visual.play_death()
	elif _crossbow_visual != null:
		clear_bell_pose()
		_crossbow_visual.death_finished.connect(_leave_blood_pool, CONNECT_ONE_SHOT)
		_crossbow_visual.play_death()
	elif _civilian_visual != null:
		clear_bell_pose()
		_civilian_visual.death_finished.connect(_leave_blood_pool, CONNECT_ONE_SHOT)
		_civilian_visual.play_death()
	else:
		death_marker_a.show()
		death_marker_b.show()
		_leave_blood_pool.call_deferred()
	queue_redraw()
	died.emit(self)


func begin_encounter(result_color: Color, zombie: Node2D) -> bool:
	if (
		not is_alive()
		or current_health <= 0.0
		or infection_state
		not in [InfectionState.AVAILABLE, InfectionState.IN_COLLISION, InfectionState.TRANSFORMING]
		or (
			infection_state == InfectionState.TRANSFORMING
			and encounter_participants.is_empty()
		)
		or not zombie.has_method("is_alive")
		or not zombie.call("is_alive")
		or interior_building != zombie.get("interior_building")
	):
		return false

	var starting_encounter := infection_state == InfectionState.AVAILABLE
	if starting_encounter:
		if not is_instance_valid(interior_building) and not has_tactical_controller():
			threat_reaction.seeking_home = true
			threat_reaction.threat_position = zombie.global_position
			local_warning._remember_observation(zombie)
		infection_state = InfectionState.IN_COLLISION
		threat_reaction.cancel_response()
		threat_detection.reset_awareness()
		_begin_wait()
		converted_color = result_color
	if not encounter_participants.has(zombie):
		encounter_participants.append(zombie)
		if _can_counterattack() and encounter_attack_timer.is_stopped():
			encounter_attack_timer.start()
	if starting_encounter:
		encounter_started.emit(zombie)
	return true


func is_encounter_owner(zombie: Node2D) -> bool:
	return encounter_participants.has(zombie)


func cancel_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func leave_encounter(zombie: Variant) -> void:
	if is_instance_valid(zombie):
		if not encounter_participants.has(zombie): return
		encounter_participants.erase(zombie)
		if zombie.has_method("on_encounter_ended"): zombie.call("on_encounter_ended", self)
	else:
		# A despawned opponent cannot be passed to a typed Array.has/erase.
		for index in range(encounter_participants.size() - 1, -1, -1):
			if not is_instance_valid(encounter_participants[index]): encounter_participants.remove_at(index)
	if encounter_participants.is_empty():
		encounter_attack_timer.stop()
	if encounter_participants.is_empty() and infection_state == InfectionState.IN_COLLISION:
		infection_state = InfectionState.AVAILABLE
		if not is_instance_valid(interior_building) and not has_tactical_controller(): threat_reaction.request_reassessment()
	elif encounter_participants.is_empty() and infection_state == InfectionState.TRANSFORMING:
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.set_deferred("disabled", true)


func _end_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func _on_encounter_attack_timer_timeout() -> void:
	var participant := _encounter_attack_target()
	if participant == null:
		encounter_attack_timer.stop()
		return
	if _church_visual != null:
		_church_visual.play_impact(participant.global_position - global_position, encounter_attack_timer.wait_time)
	elif _guard_visual != null:
		_guard_visual.play_impact(participant.global_position - global_position, encounter_attack_timer.wait_time)
	elif _crossbow_visual != null:
		var heading := participant.global_position - global_position
		if unit_vision != null:
			unit_vision.face(heading)
		_crossbow_visual.play_impact(heading, encounter_attack_timer.wait_time)
	elif _civilian_visual != null:
		_civilian_visual.play_impact(participant.global_position - global_position, encounter_attack_timer.wait_time)
	elif unit_vision != null:
		unit_vision.face(participant.global_position - global_position)
	participant.call("take_damage", attack_damage, participant.global_position - global_position, true)


func _can_counterattack() -> bool:
	return priest_routine == null and get_meta("village_role", "") != "priest"


func _encounter_attack_target() -> Node2D:
	if not _can_counterattack() or not is_alive():
		return null
	for participant in encounter_participants:
		if (
			is_instance_valid(participant)
			and participant.has_method("is_alive")
			and participant.has_method("take_damage")
			and participant.call("is_alive")
		):
			if is_instance_valid(interior_building) and (global_position.distance_to(participant.global_position) > participant.INFECTION_DISTANCE or not participant._has_line_of_sight(self)):
				continue
			return participant
	return null


func _on_transformation_timer_timeout() -> void:
	if infection_state == InfectionState.TRANSFORMING:
		_complete_conversion()


func _complete_conversion() -> void:
	if not is_alive():
		return

	infection_state = InfectionState.CONVERTED
	transformation_timer.stop()
	if is_instance_valid(player_infection_timer):
		player_infection_timer.stop()
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
	_stop_movement()
	navigation_agent.avoidance_enabled = false
	_end_encounter()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	if infection_source == InfectionSource.ZOMBIE_COMBAT:
		polygon.color = converted_color
	clear_bell_pose()
	if _body_sprite != null:
		_body_sprite.hide()
		_body_sprite.set_physics_process(false)
	queue_redraw()
	converted.emit(self)


func _draw() -> void:
	if not is_alive():
		return

	var health_ratio := current_health / max_health if max_health > 0.0 else 0.0
	var health_y := HEALTH_BAR_Y + visual_ui_offset_y
	var health_rect := Rect2(-5.85, health_y, 11.7, 2.6)
	draw_rect(health_rect, Color(0.12, 0.12, 0.12, 0.9), true)
	draw_rect(
		Rect2(health_rect.position + Vector2(0.65, 0.65), Vector2(10.4 * health_ratio, 1.3)),
		Color(0.9, 0.2, 0.2),
		true
	)
	draw_rect(health_rect, Color(0.05, 0.05, 0.05), false, 0.65)
	if has_player_infection() and not is_instance_valid(interior_building):
		var marker_y := health_y - (10.75 if _body_sprite != null else 4.75)
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(0, marker_y - 3), Vector2(3, marker_y),
				Vector2(0, marker_y + 3), Vector2(-3, marker_y),
			]),
			Color("b8dc79")
		)
