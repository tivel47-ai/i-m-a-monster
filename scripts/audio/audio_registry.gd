extends RefCounted
## Runtime names match the inventory. Definitions remain valid in a checkout without local audio.

const ROOT := "res://assets/audio/local/"
const EVENTS := {
	&"ambience.wind.base": {"bus": &"Ambience",
		"file": "ambience/global/amb_wind_base", "count": 1,
		"loop": true, "db": -13, "fade": 1.8, "background": true},
	&"ambience.village.distant": {"bus": &"Ambience",
		"file": "ambience/global/amb_village_distant", "count": 1,
		"loop": true, "db": -4, "fade": 1.8, "background": true},
	&"ambience.river.flow": {"bus": &"Ambience",
		"file": "ambience/nature/amb_river", "count": 1,
		"loop": true, "db": -9, "fade": 0.48, "background": true, "distance": 1350, "pan": 0.45},
	&"ambience.forest.vegetation": {"bus": &"Ambience",
		"file": "ambience/nature/amb_forest", "count": 1,
		"loop": true, "db": -7, "fade": 0.65, "background": true},
	&"ambience.tension.dark": {"bus": &"Ambience",
		"file": "ambience/global/amb_dark_drone", "count": 1,
		"loop": true, "db": 9, "fade": 2, "background": true},
	&"environment.animal.crow": {"bus": &"Environment",
		"file": "environment/animals/env_crow", "count": 3,
		"db": -8, "distance": 690, "priority": 22, "limit": 2, "interval": Vector2(25, 70), "detail": -4, "cooldown": 4},
	&"environment.animal.birds": {"bus": &"Environment",
		"file": "environment/animals/env_birds", "count": 3,
		"db": -7, "distance": 580, "priority": 18, "limit": 2, "interval": Vector2(12, 35), "detail": -6, "cooldown": 3},
	&"environment.animal.dog": {"bus": &"Environment",
		"file": "environment/animals/env_dog_bark", "count": 3,
		"db": -9, "distance": 650, "priority": 22, "limit": 1, "interval": Vector2(30, 75)},
	&"environment.fire.loop": {"bus": &"Environment",
		"file": "environment/buildings/env_fire_loop", "count": 1,
		"loop": true, "db": -9, "fade": 0.45, "distance": 430, "detail": -4, "pan": 0.65},
	&"human.civilian.chatter": {"bus": &"HumanVoices",
		"file": "units/humans/civilians/human_chatter", "count": 4,
		"db": -8, "distance": 380, "priority": 24, "limit": 2, "interval": Vector2(18, 45), "detail": -8, "cooldown": 5},
	&"human.civilian.fear": {"bus": &"HumanVoices",
		"file": "units/humans/civilians/human_fear", "count": 5,
		"db": -5, "distance": 580, "priority": 67, "limit": 4, "source_cooldown": 11, "cooldown": 0.12, "detail": -4},
	&"movement.footstep.dirt.light": {"bus": &"Footsteps",
		"file": "environment/footsteps/footstep_dirt_light", "count": 6,
		"db": -7, "distance": 260, "priority": 10, "limit": 8, "source_cooldown": 0.16, "detail": -11,
		"offsets": [0.046, 0.043, 0.018, 0.048, 0.032, 0.062]},
	&"zombie.ordinary.idle": {"bus": &"MonsterVoices",
		"file": "units/zombies/ordinary/zombie_ordinary_idle", "count": 5,
		"db": -9, "distance": 360, "priority": 25, "limit": 3, "interval": Vector2(8, 25),
		"detail": -7, "cooldown": 0.65, "pitch": Vector2(0.98, 1.02), "source_group": &"ordinary_voice"},
	&"zombie.ordinary.attack": {"bus": &"MonsterVoices",
		"file": "units/zombies/ordinary/zombie_ordinary_attack", "count": 5,
		"db": -7, "distance": 530, "priority": 54, "limit": 5, "source_cooldown": 1.2,
		"probability": 0.5, "detail": -4, "pitch": Vector2(0.98, 1.02), "source_group": &"ordinary_voice"},
	&"combat.impact.flesh": {"bus": &"Combat",
		"file": "combat/impacts/combat_flesh_impact", "count": 6,
		"db": -6, "distance": 640, "priority": 82, "limit": 10, "detail": -2, "offsets": [0.008, 0.097, 0.007, 0.090, 0.060, 0.082]},
}


static func path_for(event: Dictionary, variant: int) -> String:
	return event.get("root", ROOT) + "%s_%02d.%s" % [event.file, variant + 1, event.get("extension", "wav")]

