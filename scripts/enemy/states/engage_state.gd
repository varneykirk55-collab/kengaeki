extends EnemyState
## Holds an attack token: close to striking range, then attack.

const TIMEOUT := 4.0


func update(delta: float) -> void:
	if not check_target():
		return
	if enemy.coordinator and not enemy.coordinator.has_attack_token(enemy):
		ai.transition(&"circle")
		return
	var dist := enemy.distance_to_target()
	face_target(delta, enemy.turn_speed * 1.4)
	if dist <= enemy.attack_range and enemy.is_facing_point(enemy.target.global_position, 30.0):
		enemy.stop_moving()
		ai.transition(&"attack")
		return
	var to_player := enemy.target.global_position - enemy.global_position
	to_player.y = 0.0
	var stand := enemy.target.global_position - to_player.normalized() * (enemy.attack_range - 0.3)
	enemy.move_toward_point(stand, enemy.run_speed)
	if ai.time_in_state > TIMEOUT:
		if enemy.coordinator:
			enemy.coordinator.release_attack(enemy, 0.5)
		ai.transition(&"circle")
