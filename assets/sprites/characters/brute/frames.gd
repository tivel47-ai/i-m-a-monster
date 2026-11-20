# Sprite atlas cells indexed left to right, top to bottom.
extends RefCounted

const COLUMNS := 10
const CELL := Vector2i(192, 156)
const ANCHOR := Vector2i(96, 136)
const STANDING_HEIGHT := 112.0
const IDLE_BREATHING := [16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
const IDLE_GLANCE := [26, 27, 28, 29, 30, 31, 32, 33, 34, 35]

const VIEWS := [ # SE, NE, NW, SW
	{
		"texture": preload("res://assets/sprites/characters/brute/south_east.png"),
		"walk": [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47],
		"attacks": [[48, 49, 50, 51, 52, 53, 54, 55], [56, 57, 58, 59, 60, 61, 62, 63], [64, 65, 66, 67, 68, 69, 70, 71, 72, 73]],
		"contacts": [4, 4, 5],
		"hurt": [74, 75, 76, 77, 78],
		"deaths": [[79, 80, 81, 82, 83, 84, 85, 86], [87, 88, 89, 90, 91, 92, 93, 94]],
	},
	{
		"texture": preload("res://assets/sprites/characters/brute/north_east.png"),
		"walk": [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23],
		"attacks": [[3, 0, 1, 2, 3], [7, 4, 5, 6, 7], [3, 8, 9, 10, 3]],
		"contacts": [2, 2, 2],
		"hurt": [3, 11, 11, 3],
		"deaths": [[24, 25, 26, 27, 28], [29, 30, 31, 32, 33]],
	},
	{
		"texture": preload("res://assets/sprites/characters/brute/north_west.png"),
		"walk": [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23],
		"attacks": [[3, 0, 1, 2, 3], [7, 4, 5, 6, 7], [3, 8, 9, 10, 3]],
		"contacts": [2, 2, 2],
		"hurt": [3, 11, 11, 3],
		"deaths": [[24, 25, 26, 27, 28], [29, 30, 31, 32, 33]],
	},
	{
		"texture": preload("res://assets/sprites/characters/brute/south_west.png"),
		"walk": [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23],
		"attacks": [[3, 0, 1, 2, 3], [7, 4, 5, 6, 7], [3, 8, 9, 10, 3]],
		"contacts": [2, 2, 2],
		"hurt": [3, 11, 11, 3],
		"deaths": [[24, 25, 26, 27, 28], [29, 30, 31, 32, 33]],
	}
]
