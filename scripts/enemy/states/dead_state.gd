extends EnemyState
## Terminal state. Corpse handling lives in Enemy._update_corpse().

func enter(_msg: Dictionary) -> void:
	enemy.stop_moving()
