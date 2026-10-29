extends EnemyState
## No valid target (none present, or the player is dead): keep a respectful distance.

func enter(_msg: Dictionary) -> void:
	if enemy.coordinator:
		enemy.coordinator.release_attack(enemy, 0.0)


func update(delta: float) -> void:
	if enemy.has_target() and enemy.distance_to_target() <= enemy.detection_range:
		ai.transition(&"approach")
		return
	if enemy.target and is_instance_valid(enemy.target) and enemy.distance_to_target() < 6.0:
		# Player fallen: step back and hold guard nearby.
		var away := enemy.global_position - enemy.target.global_position
		away.y = 0.0
		enemy.move_toward_point(enemy.target.global_position + away.normalized() * 6.5, enemy.walk_speed)
		face_target(delta, 4.0)
	else:
		enemy.stop_moving()
