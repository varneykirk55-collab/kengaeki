class_name EnemyState
extends RefCounted
## Base class for one enemy behaviour. States read the world through `enemy` and switch
## with `ai.transition(name, msg)`.

var ai: EnemyAI
var enemy: Enemy
var name: StringName


func enter(_msg: Dictionary) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


func face_target(delta: float, rate: float = -1.0) -> void:
	if enemy.has_target():
		enemy.face_point(enemy.target.global_position, (enemy.turn_speed if rate < 0.0 else rate) * delta)


## Common check: lost target -> idle.
func check_target() -> bool:
	if not enemy.has_target() or enemy.distance_to_target() > enemy.detection_range:
		ai.transition(&"idle")
		return false
	return true
