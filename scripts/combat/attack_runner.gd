class_name AttackRunner
extends Node
## Drives one attack through startup -> active -> recovery and tells the weapon
## when its hit window is open. Shared by player and enemies.
##
## Timing comes from AttackData (DATA) or from animation events relayed by the
## character visual (ANIMATION_EVENTS: "hit_start", "hit_end", "attack_end").

signal phase_changed(phase: int)
signal finished(attack: AttackData)

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }

@export var weapon_path: NodePath = ^"../Weapon"

var attack: AttackData
var phase: int = Phase.NONE
var phase_time := 0.0
var elapsed := 0.0
var weapon: WeaponComponent

var _anim_events: Array[StringName] = []


func _ready() -> void:
	weapon = get_node_or_null(weapon_path) as WeaponComponent


func is_running() -> bool:
	return phase != Phase.NONE


func start(new_attack: AttackData) -> void:
	if is_running():
		_close_window()
	attack = new_attack
	elapsed = 0.0
	_anim_events.clear()
	_set_phase(Phase.STARTUP)


func cancel() -> void:
	if not is_running():
		return
	_close_window()
	phase = Phase.NONE
	attack = null
	phase_changed.emit(phase)


## Called by the owner's visual when an imported animation emits a method-track event.
func on_animation_event(event_name: StringName) -> void:
	if is_running() and attack.timing_source == AttackData.TimingSource.ANIMATION_EVENTS:
		_anim_events.append(event_name)


func in_cancel_window() -> bool:
	return phase == Phase.RECOVERY and phase_time >= attack.cancel_point


func can_dodge_cancel() -> bool:
	if phase == Phase.STARTUP:
		return attack.dodge_cancel_startup >= 0.0 and phase_time <= attack.dodge_cancel_startup
	return in_cancel_window()


func is_in_startup() -> bool:
	return phase == Phase.STARTUP


func is_active() -> bool:
	return phase == Phase.ACTIVE


## 0..1 progress through the current phase (used by placeholder animation).
func phase_progress() -> float:
	if not is_running():
		return 0.0
	var length := _phase_length(phase)
	return clampf(phase_time / length, 0.0, 1.0) if length > 0.0 else 1.0


func _phase_length(p: int) -> float:
	match p:
		Phase.STARTUP:
			return attack.startup
		Phase.ACTIVE:
			return attack.active
		Phase.RECOVERY:
			return attack.recovery
	return 0.0


func tick(delta: float) -> void:
	if not is_running():
		return
	elapsed += delta
	var prev_time := phase_time
	phase_time += delta
	var use_events := attack.timing_source == AttackData.TimingSource.ANIMATION_EVENTS
	match phase:
		Phase.STARTUP:
			var open := phase_time >= attack.startup
			if use_events:
				# Fallback: if the animation never sends hit_start, open after 2x the data timing.
				open = _anim_events.has(&"hit_start") or phase_time >= attack.startup * 2.0
			if open:
				_set_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			var length := maxf(attack.active, 0.001)
			if weapon:
				weapon.sweep(attack, clampf(prev_time / length, 0.0, 1.0), clampf(phase_time / length, 0.0, 1.0))
				if not is_running():
					return  # parried mid-swing: the attack was cancelled by the defender
			var close := phase_time >= attack.active
			if use_events:
				close = _anim_events.has(&"hit_end") or phase_time >= attack.active * 2.0
			if close:
				if weapon and not use_events:
					weapon.sweep(attack, clampf(prev_time / length, 0.0, 1.0), 1.0)
					if not is_running():
						return
				_close_window()
				_set_phase(Phase.RECOVERY)
		Phase.RECOVERY:
			var done := phase_time >= attack.recovery
			if use_events:
				done = _anim_events.has(&"attack_end") or phase_time >= attack.recovery * 2.0
			if done:
				var finished_attack := attack
				phase = Phase.NONE
				attack = null
				phase_changed.emit(phase)
				finished.emit(finished_attack)


func _set_phase(p: int) -> void:
	phase = p
	phase_time = 0.0
	if p == Phase.ACTIVE and weapon:
		weapon.begin_hit_window(attack)
	phase_changed.emit(phase)


func _close_window() -> void:
	if weapon:
		weapon.end_hit_window()
