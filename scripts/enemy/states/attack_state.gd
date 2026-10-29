extends EnemyState
## Performs a short attack string (1-2 techniques), then backs off and frees the token.

var _sequence: Array[AttackData] = []
var _index := 0
var _retreat_time := 0.0


func enter(_msg: Dictionary) -> void:
	_sequence = enemy.choose_attack_sequence()
	_index = 0
	_retreat_time = 0.0
	enemy.stop_moving()
	_start_next()


func _start_next() -> void:
	enemy.start_attack(_sequence[_index])


func update(delta: float) -> void:
	var runner := enemy.attack_runner
	if runner.is_running():
		var attack := runner.attack
		if runner.is_in_startup():
			face_target(delta, enemy.turn_speed * 0.9)
		# Short committed step during the windup and strike.
		if runner.phase != AttackRunner.Phase.RECOVERY and enemy.distance_to_target() > enemy.body_radius * 2.0 + 0.7:
			enemy.desired_velocity = enemy.get_forward() * attack.lunge_distance / maxf(attack.startup + attack.active, 0.05)
		else:
			enemy.desired_velocity = Vector3.ZERO
		if runner.in_cancel_window() and _index + 1 < _sequence.size() and enemy.has_target():
			_index += 1
			_start_next()
		return
	# Finished: brief retreat, then give the token back.
	if _retreat_time == 0.0 and enemy.coordinator:
		enemy.coordinator.release_attack(enemy, enemy.rng.randf_range(1.0, 2.2))
	_retreat_time += delta
	if enemy.has_target():
		var away := enemy.global_position - enemy.target.global_position
		away.y = 0.0
		enemy.desired_velocity = away.normalized() * enemy.walk_speed * 0.9
		face_target(delta)
	if _retreat_time > 0.6 or not enemy.has_target():
		ai.transition(&"circle" if enemy.has_target() else &"idle")

