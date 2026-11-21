extends RefCounted

const CELL := Vector2(160, 128)
const ANCHOR := Vector2(80, 116)
const STANDING_HEIGHT := 96.0
const FRAME_COUNT := 6
const CONTACT_FRAME := 3

enum Clip { IDLE, WALK, RUSH, SWIPE, OVERHEAD, REACH, HURT, DEATH_FORWARD, DEATH_BACK }
enum Appearance { PLAIN, NECROSIS, WOUNDED, BLOOM }

const TURN := [
	preload("res://assets/sprites/characters/ordinary_zombie/plain-turn.png"),
	preload("res://assets/sprites/characters/ordinary_zombie/necrosis-turn.png"),
	preload("res://assets/sprites/characters/ordinary_zombie/wounded-turn.png"),
	preload("res://assets/sprites/characters/ordinary_zombie/bloom-turn.png"),
]
# Diagonal animation views: SE, NE, NW, SW.
const VIEWS := [
	[
		preload("res://assets/sprites/characters/ordinary_zombie/plain-se.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/plain-ne.png"),
	],
	[
		preload("res://assets/sprites/characters/ordinary_zombie/necrosis-se.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/necrosis-ne.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/necrosis-nw.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/necrosis-sw.png"),
	],
	[
		preload("res://assets/sprites/characters/ordinary_zombie/wounded-se.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/wounded-ne.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/wounded-nw.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/wounded-sw.png"),
	],
	[
		preload("res://assets/sprites/characters/ordinary_zombie/bloom-se.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/bloom-ne.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/bloom-nw.png"),
		preload("res://assets/sprites/characters/ordinary_zombie/bloom-sw.png"),
	],
]

# RGB multipliers measured from idle and locomotion against each skin's turntable.
# Keep one correction per view so a clip's shading stays stable between frames.
const VIEW_TINTS := {
	Appearance.NECROSIS: [
		Color(0.873, 0.892, 0.894), Color(0.808, 0.800, 0.803),
		Color(0.681, 0.664, 0.663), Color(0.702, 0.686, 0.679),
	],
	Appearance.WOUNDED: [
		Color(0.923, 0.886, 0.866), Color(0.860, 0.820, 0.805),
		Color(0.831, 0.789, 0.795), Color(0.796, 0.738, 0.731),
	],
	Appearance.BLOOM: [
		Color(0.841, 0.821, 0.819), Color(0.789, 0.781, 0.766),
		Color(0.727, 0.701, 0.689), Color(0.709, 0.711, 0.690),
	],
}

const IDLE_TIME := 1.20
const WALK_DISTANCE := 59.0
const RUSH_DISTANCE := 49.0
const WINDUP_TIMES := [0.27, 0.35, 0.32]
const WALK_PHASES := [0.0, 0.18, 0.31, 0.47, 0.65, 0.81]

static var _appearance_rng := RandomNumberGenerator.new()


static func random_appearance() -> int:
	return _appearance_rng.randi_range(0, TURN.size() - 1)


static func walk_frame(progress: float) -> int:
	for index in range(WALK_PHASES.size() - 1, 0, -1):
		if progress >= WALK_PHASES[index]:
			return index
	return 0
