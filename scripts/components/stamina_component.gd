class_name StaminaComponent
extends Node
## Stamina / guard resource. Used by the player for actions and by enemies as guard (poise).

signal changed(current: float, maximum: float)
signal depleted

@export var max_stamina: float = 100.0
@export var regen_rate: float = 30.0
## Seconds after spending before regeneration resumes.
@export var regen_delay: float = 0.7
## Regeneration multiplier while the owner is blocking.
@export var blocking_regen_multiplier: float = 0.35

var current: float
var blocking := false
var _cooldown := 0.0


func _ready() -> void:
	current = max_stamina


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	if current < max_stamina:
		var rate := regen_rate * (blocking_regen_multiplier if blocking else 1.0)
		current = minf(max_stamina, current + rate * delta)
		changed.emit(current, max_stamina)


func has(amount: float) -> bool:
	return current >= amount


## Spends stamina if available. Returns false (and spends nothing) when insufficient.
func try_consume(amount: float) -> bool:
	if current < amount:
		return false
	consume(amount)
	return true


## Spends stamina unconditionally (clamped at zero).
func consume(amount: float) -> void:
	if amount <= 0.0:
		return
	current = maxf(0.0, current - amount)
	_cooldown = regen_delay
	changed.emit(current, max_stamina)
	if current <= 0.0:
		depleted.emit()


## Continuous drain (e.g. sprinting). Delays regeneration.
func drain(rate: float, delta: float) -> void:
	consume(rate * delta)


func ratio() -> float:
	return current / max_stamina if max_stamina > 0.0 else 0.0


func restore_full() -> void:
	current = max_stamina
	_cooldown = 0.0
	changed.emit(current, max_stamina)
