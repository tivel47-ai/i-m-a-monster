extends RefCounted

const ZOMBIE_PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ORDINARY_ART = preload("res://assets/sprites/characters/ordinary_zombie/frames.gd")

const HUMAN_TYPES := {
	"peasant": "Крестьянин",
	"artisan": "Ремесленник",
	"guard": "Стражник",
	"priest": "Священник",
	"priest_guard": "Охранник священника",
}
const ZOMBIE_TYPES := {
	"zombie": "Обычный зомби",
	ZOMBIE_PROGRESSION.BRUTE: ZOMBIE_PROGRESSION.NODES[ZOMBIE_PROGRESSION.BRUTE].title,
	ZOMBIE_PROGRESSION.HOUND: ZOMBIE_PROGRESSION.NODES[ZOMBIE_PROGRESSION.HOUND].title,
	ZOMBIE_PROGRESSION.CARRIER: ZOMBIE_PROGRESSION.NODES[ZOMBIE_PROGRESSION.CARRIER].title,
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
		"preview": "res://assets/maps/mission_01_preview.png",
		"zombie_progression": true,
		"races": ["zombie"],
	},
}
const RACES := {
	"zombie": {
		"name": "Зомби",
		"unit_types": ZOMBIE_TYPES,
		"description": "Зомби — медлительная, чрезвычайно живучая и постепенно разрастающаяся орда. Они уступают людям в мобильности, боевой подготовке и организованности, но превосходят их в физической выносливости и способности восполнять свою численность посредством заражения. Их сила заключается в неотвратимости, численности и продолжительном противостоянии.",
		"gameplay": "Удерживайте ПКМ, чтобы задать область движения или атаки всей орде. Для штурма здания задайте число зомби отдельной командой. Успешное заражение пополняет орду.",
		"strengths": "Заражённый житель превращается в управляемого зомби.",
		"weaknesses": "Зомби получают ответный урон в ближнем бою и могут погибнуть.",
		"preview": preload("res://scripts/zombie_race_stage.gd"),
		"active_perks": [ZOMBIE_PROGRESSION.HUNGER,
			ZOMBIE_PROGRESSION.FORTITUDE, ZOMBIE_PROGRESSION.SPASM],
		"cursor": {
			"idle": preload("res://assets/ui/cursors/zombie_idle.png"),
			"pressed": preload("res://assets/ui/cursors/zombie_pressed.png"),
			"hotspot": Vector2(3, 3),
		},
	},
	"human": {
		"name": "Люди",
		"unit_types": HUMAN_TYPES,
		"active_perks": [],
	},
}
