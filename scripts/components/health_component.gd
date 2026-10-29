class_name HealthComponent
extends Node
## Hit points with optional out-of-combat regeneration.

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

@export var max_health: float = 100.0
## Health regenerated per second once regen_delay has passed without taking damage (0 = off).
@export var regen_rate: float = 0.0
@export var regen_delay: float = 6.0

var current: float
var _since_damage := 0.0


func _ready() -> void:
	current = max_health


func _physics_process(delta: float) -> void:
	_since_damage += delta
	if regen_rate > 0.0 and current > 0.0 and current < max_health and _since_damage >= regen_delay:
		current = minf(max_health, current + regen_rate * delta)
		changed.emit(current, max_health)


func is_dead() -> bool:
	return current <= 0.0


func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0


## Applies damage and returns the amount actually removed.
func take_damage(amount: float) -> float:
	if current <= 0.0 or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, current)
	current -= dealt
	_since_damage = 0.0
	damaged.emit(dealt)
	changed.emit(current, max_health)
	if current <= 0.0:
		current = 0.0
		died.emit()
	return dealt


func heal(amount: float) -> void:
	if current <= 0.0:
		return
	current = minf(max_health, current + amount)
	changed.emit(current, max_health)


func restore_full() -> void:
	current = max_health
	_since_damage = 0.0
	changed.emit(current, max_health)
