extends EnemyState
## Hit reaction / stagger / parried / guard broken. `vulnerable` enables player finishers.

var vulnerable := false
var _duration := 0.4


func enter(msg: Dictionary) -> void:
	_duration = msg.get("duration", 0.4)
	vulnerable = msg.get("vulnerable", false)
	enemy.attack_runner.cancel()
	if enemy.coordinator and vulnerable:
		enemy.coordinator.release_attack(enemy, 1.0)


func update(_delta: float) -> void:
	enemy.desired_velocity = Vector3.ZERO
	if ai.time_in_state >= _duration:
		vulnerable = false
		if not enemy.has_target():
			ai.transition(&"idle")
		elif enemy.coordinator and enemy.coordinator.has_attack_token(enemy):
			ai.transition(&"engage")
		else:
			ai.transition(&"circle")


func exit() -> void:
	vulnerable = false
