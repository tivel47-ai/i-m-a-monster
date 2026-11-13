extends RefCounted

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
		"description": "Большая живая деревня: жилые кварталы, часовня, поля, мастерские и пост стражи. Река на восточной окраине пересекается по деревянному мосту. 32 жителя на карте 3000 × 2000.",
		"objectives": "Заразите или уничтожьте не менее 80% жителей деревни (26 из 32).",
		"scene": "res://scenes/village_simulation_map.tscn",
		"races": ["zombie"],
	},
}
const RACES := {
	"zombie": {
		"name": "Зомби",
		"description": "Прямое давление и увеличение армии через заражение жителей.",
		"gameplay": "Подведите зомби к жителю: они вступят в ближний бой. Успешное заражение превращает жителя в нового зомби и пополняет вашу армию.",
		"strengths": "Заражённый житель превращается в управляемого зомби.",
		"weaknesses": "Зомби получают ответный урон в ближнем бою и могут погибнуть.",
		"preview": "res://scenes/zombie.tscn",
		"development": [
			{"id": "infection", "name": "Заражение", "position": Vector2(0.29, 0.53)},
			{"id": "carrier", "name": "Форма носителя", "parent": "infection", "position": Vector2(0.21, 0.21)},
			{"id": "resilience", "name": "Стойкость", "position": Vector2(0.71, 0.53)},
			{"id": "brute", "name": "Форма громилы", "parent": "resilience", "position": Vector2(0.79, 0.21)},
		],
	},
}
