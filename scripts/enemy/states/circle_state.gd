extends EnemyState
## Waiting for an attack token: hold a slot on the ring, strafe, feint, keep facing the
## player, and ask the coordinator for permission to attack. The coordinator queues
## requests first-come-first-served, so no enemy waits forever.

var _strafe_dir := 1.0
var _next_strafe_change := 0.0
var _feint_until := 0.0
var _next_feint := 0.0
var _radius_offset := 0.0


func enter(_msg: Dictionary) -> void:
	if enemy.coordinator:
		enemy.coordinator.begin_waiting(enemy)
	_strafe_dir = 1.0 if enemy.rng.randf() < 0.5 else -1.0
	_next_strafe_change = enemy.rng.randf_range(1.5, 3.5)
	_next_feint = enemy.rng.randf_range(1.5, 4.0)
	_radius_offset = enemy.rng.randf_range(-0.6, 0.8)


func update(delta: float) -> void:
	if not check_target():
		return
	var t := ai.time_in_state
	if enemy.coordinator and enemy.coordinator.request_attack(enemy):
		ai.transition(&"engage")
		return
	if t >= _next_strafe_change:
		_strafe_dir = -_strafe_dir
		_next_strafe_change = t + enemy.rng.randf_range(1.5, 3.5)
		_radius_offset = enemy.rng.randf_range(-0.6, 0.8)
	var radius := enemy.ring_radius + _radius_offset
	if t >= _next_feint:
		# Threatening step-in that does not commit to an attack.
		_feint_until = t + 0.45
		_next_feint = t + enemy.rng.randf_range(2.5, 5.0)
	if t < _feint_until:
		radius -= 1.6
	var slot: Vector3 = enemy.coordinator.get_ring_position(enemy, radius) if enemy.coordinator else enemy.global_position
	var player_pos := enemy.target.global_position
	# Orbit a little around the slot so waiting enemies never look frozen.
	var around := (enemy.global_position - player_pos)
	around.y = 0.0
	var tangent := Vector3.UP.cross(around.normalized()) * _strafe_dir
	var goal := slot + tangent * 0.8
	var too_close := enemy.distance_to_target() < 2.2
	if too_close:
		goal = player_pos + around.normalized() * (radius + 0.5)
	enemy.move_toward_point(goal, enemy.walk_speed * (1.4 if too_close else 0.8))
	face_target(delta)


func exit() -> void:
	if enemy.coordinator:
		enemy.coordinator.end_waiting(enemy)
