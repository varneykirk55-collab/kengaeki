extends EnemyState
## Walks in from the spawn gate toward the arena before joining the fight.

var _goal := Vector3.ZERO
var _duration := 1.2


func enter(_msg: Dictionary) -> void:
	_duration = enemy.rng.randf_range(0.9, 1.4)
	var inward := -enemy.global_position
	inward.y = 0.0
	_goal = enemy.global_position + inward.normalized() * 3.5 if inward.length() > 0.1 else enemy.global_position


func update(delta: float) -> void:
	enemy.move_toward_point(_goal, enemy.walk_speed + 0.6)
	enemy.face_direction(enemy.desired_velocity, 8.0 * delta)
	if ai.time_in_state >= _duration:
		ai.transition(&"approach" if enemy.has_target() else &"idle")
