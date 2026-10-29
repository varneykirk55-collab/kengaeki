extends EnemyState
## Closes distance toward this enemy's assigned slot on the ring around the player.

func update(delta: float) -> void:
	if not check_target():
		return
	var slot: Vector3 = enemy.coordinator.get_ring_position(enemy) if enemy.coordinator else enemy.target.global_position
	var dist_to_player := enemy.distance_to_target()
	var speed := enemy.run_speed if dist_to_player > enemy.ring_radius + 3.0 else enemy.walk_speed
	enemy.move_toward_point(slot, speed)
	if dist_to_player > enemy.ring_radius + 3.0:
		enemy.face_direction(enemy.desired_velocity, 8.0 * delta)
	else:
		face_target(delta)
	if dist_to_player <= enemy.ring_radius + 1.0 or enemy.global_position.distance_to(slot) < 1.0:
		ai.transition(&"circle")
