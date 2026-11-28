extends Resource

enum Source { NONE, RECRUITMENT, SHELTER, CHURCH }

const SOURCES := {
	Source.NONE: "—",
	Source.RECRUITMENT: "Вступление в группу",
	Source.SHELTER: "Запертое укрытие",
	Source.CHURCH: "Прибытие к церкви",
}

@export var weapons: Dictionary = {
	&"pitchfork": {"label": "Вилы", "marker": "Вилы", "weights": [25, 5], "melee": Vector3(0.90, 1.00, 1.30)},
	&"axe": {"label": "Топор", "marker": "Топор", "weights": [20, 20], "melee": Vector3(1.20, 1.20, 1.00)},
	&"torch": {"label": "Факел", "marker": "Факел", "weights": [15, 10], "melee": Vector3.ONE},
	&"hammer": {"label": "Молот", "marker": "Молот", "weights": [0, 25], "melee": Vector3(1.25, 1.30, 0.90)},
	&"club": {"label": "Дубина", "marker": "Дубина", "weights": [10, 10], "melee": Vector3(0.85, 0.85, 1.00)},
	&"sling": {"label": "Праща", "marker": "Праща", "weights": [15, 15], "ranged": true,
		"damage": 8.0, "interval": 1.8, "reach": 130.0, "error": 0.30, "speed": 210.0, "deviation": 15.0},
	&"hunting_bow": {"label": "Охотничий лук", "marker": "Лук", "weights": [15, 15], "ranged": true,
		"damage": 12.0, "interval": 2.2, "reach": 150.0, "error": 0.15, "speed": 260.0, "deviation": 12.0},
}
@export_range(0.0, 1.0) var preferred_fraction := 0.70
@export_range(0.0, 1.0) var retreat_fraction := 0.30
@export var initiative_radius := 75.0
@export var support_weight := 0.55
@export var cover_offset := 25.0
@export var maneuver_interval := 0.75


func validation_error() -> String:
	if weapons.size() != 7:
		return "Требуется семь определений оружия."
	var totals := Vector2.ZERO
	for id in weapons:
		if id not in [&"pitchfork", &"axe", &"torch", &"hammer", &"club", &"sling", &"hunting_bow"]:
			return "Неизвестное оружие %s." % id
		if not weapons[id] is Dictionary:
			return "Некорректное определение %s." % id
		var entry: Dictionary = weapons[id]
		var ranged: Variant = entry.get("ranged", false)
		if not ranged is bool or ranged != (id in [&"sling", &"hunting_bow"]):
			return "Неверная категория %s." % id
		var weights: Variant = entry.get("weights", [])
		if (not weights is Array or weights.size() != 2 or not entry.get("label", "") is String or entry.label.is_empty()
			or not entry.get("marker", "") is String):
			return "Не задано название или веса %s." % id
		for weight in weights:
			if not (weight is int or weight is float) or not is_finite(weight) or weight < 0:
				return "Некорректный вес %s." % id
		totals += Vector2(weights[0], weights[1])
		if ranged:
			for field in ["damage", "interval", "reach", "speed", "deviation"]:
				var value: Variant = entry.get(field, 0.0)
				if not (value is int or value is float) or not is_finite(value) or value <= 0.0:
					return "Некорректный параметр %s у %s." % [field, id]
			var error: Variant = entry.get("error", -1.0)
			if not (error is int or error is float) or not is_finite(error) or error < 0.0 or error > 1.0 or entry.deviation >= 90.0:
				return "Некорректная ошибка прицеливания %s." % id
		else:
			var melee: Variant = entry.get("melee", Vector3.ZERO)
			if not melee is Vector3 or not melee.is_finite() or minf(melee.x, minf(melee.y, melee.z)) <= 0.0:
				return "Некорректные множители %s." % id
	if not totals.is_equal_approx(Vector2(100.0, 100.0)):
		return "Веса каждой профессии должны давать 100%%. Текущие суммы %s." % totals
	if (not is_finite(retreat_fraction) or not is_finite(preferred_fraction) or retreat_fraction <= 0.0
		or preferred_fraction <= retreat_fraction or preferred_fraction > 1.0
		or not is_finite(initiative_radius) or initiative_radius <= 0.0 or not is_finite(support_weight)
		or support_weight < 0.0 or not is_finite(cover_offset) or cover_offset <= 0.0
		or not is_finite(maneuver_interval) or maneuver_interval <= 0.0):
		return "Некорректные параметры тактики гражданских."
	return ""


func choose(role: String, random: RandomNumberGenerator) -> StringName:
	var role_index := ["peasant", "artisan"].find(role)
	if role_index < 0:
		return &""
	var roll := random.randf() * 100.0
	var last_weighted: StringName
	for id in weapons:
		var weight: float = weapons[id].weights[role_index]
		if weight <= 0.0:
			continue
		last_weighted = id
		roll -= weight
		if roll < 0.0:
			return id
	# randf() can return exactly one.
	return last_weighted


func shot_direction(offset: Vector2, target_radius: float, profile: Dictionary, random: RandomNumberGenerator) -> Vector2:
	var heading := offset.normalized()
	if random.randf() >= float(profile.error):
		return heading
	var clearance := asin(clampf((target_radius + 1.0) / offset.length(), 0.0, 1.0))
	var deviation := maxf(deg_to_rad(profile.deviation), clearance)
	return heading.rotated(deviation if random.randi_range(0, 1) == 0 else -deviation)
