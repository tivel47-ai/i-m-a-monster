extends RefCounted

const SHIELD := &"shield"
const SWORD := &"sword"
const SPEAR := &"spear"
const CROSSBOW := &"crossbow"

const ZOMBIES := {
	"": {"health": 180.0, "speed": 58.0, "damage": 21.0, "interval": 1.4, "infection": 0.08},
	"brute": {"health": 360.0, "speed": 38.0, "damage": 42.0, "interval": 2.4, "infection": 0.02},
	"hound": {"health": 115.0, "speed": 108.0, "damage": 15.0, "interval": 0.9, "infection": 0.06},
	"carrier": {"health": 230.0, "speed": 48.0, "damage": 13.0, "interval": 1.5, "infection": 0.16},
}

const HUMANS := {
	&"peasant": {"health": 75.0, "damage": 8.0, "interval": 1.4, "peaceful": 24.0,
		"tactical": 60.0, "fleeing": 95.0, "armed_damage": 15.0, "armed_interval": 1.2},
	&"artisan": {"health": 90.0, "damage": 10.0, "interval": 1.4, "peaceful": 25.0,
		"tactical": 60.0, "fleeing": 87.0, "armed_damage": 18.0, "armed_interval": 1.3},
	&"priest_guard": {"health": 180.0, "damage": 30.0, "interval": 1.0, "peaceful": 30.0, "tactical": 75.0},
	&"priest": {"health": 80.0, "damage": 0.0, "interval": 0.0, "peaceful": 22.0, "tactical": 65.0},
}

const GUARD_VARIANTS := {
	SHIELD: {"health": 140.0, "damage": 26.0, "interval": 1.1, "peaceful": 35.0, "tactical": 80.0,
		"pursuit_factor": 0.8},
	SWORD: {"health": 155.0, "damage": 28.0, "interval": 1.1, "peaceful": 35.0, "tactical": 80.0},
	SPEAR: {"health": 130.0, "damage": 32.0, "interval": 1.4, "peaceful": 35.0, "tactical": 75.0,
		"support_priority": 25.0},
	CROSSBOW: {"health": 85.0, "damage": 23.0, "interval": 1.6, "peaceful": 35.0, "tactical": 85.0},
}
