class_name BuildingRules
extends Resource

@export_group("Original entrance")
@export_range(1.0, 1000.0) var door_health := 100.0
@export_range(0.1, 60.0) var reinforcement_seconds := 10.0
@export_range(1.0, 1000.0) var reinforcement_health := 60.0
@export_range(0.0, 0.95) var reinforced_damage_reduction := 0.35
@export_range(0.0, 1.0) var slowdown_per_attacker := 0.18
@export_range(0.0, 0.95) var maximum_slowdown := 0.65

@export_group("Restoration")
@export_range(1.0, 1000.0) var barricade_health := 100.0
@export_range(0.1, 100.0) var build_per_second := 10.0
@export_range(0.01, 0.99) var second_worker_efficiency := 0.6
@export_range(0.0, 60.0) var damage_cooldown := 10.0
@export_range(0.0, 60.0) var recovery_seconds := 5.0
@export_range(0.0, 20.0) var healing_per_second := 1.0
@export_range(0.1, 4.0) var crossing_clearance := 0.5
@export_range(0.0, 2.0) var crossing_attack_delay := 0.35

@export_group("Roof")
@export_range(0.0, 1.0) var reveal_at_zoom_fraction := 0.85
@export_range(0.1, 20.0) var roof_fade_speed := 6.0
