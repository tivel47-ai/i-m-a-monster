extends RefCounted

# Content lives here; navigation does not depend on individual scene paths.
const MISSIONS := {
	"village": {
		"name": "Первая деревня",
		"description": "Заразите или уничтожьте не менее 80% жителей деревни.",
		"scene": "res://scenes/test_map.tscn",
		"marker": Vector2(440, 240),
		"races": ["zombie"],
	},
}
const RACES := {
	"zombie": {
		"name": "Зомби",
		"description": "Прямое давление и увеличение армии через заражение жителей.",
		"strengths": "Заражённый житель превращается в управляемого зомби.",
		"weaknesses": "Зомби получают ответный урон в ближнем бою и могут погибнуть.",
		"preview": "res://scenes/zombie.tscn",
	},
}
