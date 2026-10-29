extends EnemyState
## Raised guard in response to an incoming attack. May riposte if it holds a token.

var _duration := 0.8


func enter(msg: Dictionary) -> void:
	_duration = msg.get("duration", 0.8)
	enemy.stop_moving()


func update(delta: float) -> void:
	face_target(delta, enemy.turn_speed * 1.5)
	enemy.stop_moving()
	if ai.time_in_state >= _duration:
		var close := enemy.has_target() and enemy.distance_to_target() <= enemy.attack_range + 0.4
		if close and enemy.coordinator and enemy.coordinator.request_attack(enemy, true):
			ai.transition(&"attack")
		elif enemy.has_target():
			ai.transition(&"circle")
		else:
			ai.transition(&"idle")
