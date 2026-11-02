extends RefCounted

# Content lives here; navigation does not depend on individual scene paths.
const MISSIONS := {
	"village": {
		"name": "Первая деревня",
		"description": "Небольшая деревня с жилыми домами, площадью и хозяйственными постройками.",
		"objectives": "Заразите или уничтожьте не менее 80% жителей деревни.",
		"scene": "res://scenes/test_map.tscn",
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
