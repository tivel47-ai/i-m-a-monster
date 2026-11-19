extends RefCounted

const ZOMBIE_PROGRESSION = preload("res://scripts/zombie_progression.gd")

const HUMAN_TYPES := {
	"resident": "Житель",
	"peasant": "Крестьянин",
	"artisan": "Ремесленник",
	"guard": "Стражник",
	"priest": "Священник",
	"priest_guard": "Охранник священника",
}

# Content lives here; navigation does not depend on individual scene paths.
const MISSIONS := {
	"village": {
		"name": "Тестовая карта",
		"description": "Небольшая деревня с жилыми домами, площадью и хозяйственными постройками.",
		"objectives": "Заразите или уничтожьте не менее 80% жителей деревни.",
		"scene": "res://scenes/test_map.tscn",
		"races": ["zombie"],
	},
	"mission_1": {
		"name": "Миссия №1",
		"description": "Большая живая деревня: жилые кварталы, часовня, поля, мастерские и пост стражи. Река на восточной окраине пересекается по деревянному мосту. 44 жителя на карте 3000 × 2000.",
		"objectives": "Заразите или уничтожьте не менее 80% жителей деревни (36 из 44).",
		"scene": "res://scenes/village_simulation_map.tscn",
		"zombie_progression": true,
		"races": ["zombie"],
	},
}
const RACES := {
	"zombie": {
		"name": "Зомби",
		"description": "Прямое давление и увеличение армии через заражение жителей.",
		"gameplay": "Удерживайте ПКМ, чтобы задать область движения или атаки всей орде. Для штурма здания задайте число зомби отдельной командой. Успешное заражение пополняет орду.",
		"strengths": "Заражённый житель превращается в управляемого зомби.",
		"weaknesses": "Зомби получают ответный урон в ближнем бою и могут погибнуть.",
		"preview": "res://scenes/zombie.tscn",
		"active_perks": [ZOMBIE_PROGRESSION.HUNGER,
			ZOMBIE_PROGRESSION.FORTITUDE, ZOMBIE_PROGRESSION.SPASM],
		"cursor": {
			"idle": preload("res://assets/ui/cursors/zombie_idle.png"),
			"pressed": preload("res://assets/ui/cursors/zombie_pressed.png"),
			"hotspot": Vector2(3, 3),
		},
	},
}


static func monster_types() -> Dictionary:
	var types := {"zombie": "Зомби"}
	for form in ZOMBIE_PROGRESSION.FORMS:
		types[form] = ZOMBIE_PROGRESSION.NODES[form].title
	return types
