class_name Player
extends Combatant
## Third-person samurai controller: movement, dodge, block/parry, attack state machine.
## Technique selection (combos, counters, finishers) is delegated to PlayerCombat.

signal state_changed(state: int)
signal lock_target_changed(target: Combatant)
signal player_died
signal player_revived

enum State { MOVE, ATTACK, BLOCK, DODGE, HITSTUN, DEAD }

@export_group("Movement")
@export var walk_speed: float = 4.6
@export var sprint_speed: float = 7.4
@export var strafe_speed: float = 3.9
@export var block_speed: float = 1.8
@export var acceleration: float = 30.0
@export var deceleration: float = 24.0
@export var turn_speed: float = 14.0
@export var sprint_stamina_per_sec: float = 14.0
@export var gravity: float = 22.0

@export_group("Dodge")
@export var dodge_distance: float = 4.2
@export var dodge_duration: float = 0.42
@export var dodge_iframes_start: float = 0.02
@export var dodge_iframes_end: float = 0.3
@export var dodge_stamina: float = 18.0
## After this much of the dodge, attacks / another dodge may cut in.
@export var dodge_cancel_time: float = 0.3

@export_group("Reactions")
@export var hitstun_by_power: Array[float] = [0.22, 0.38, 0.65, 1.0]
@export var guard_break_stun: float = 0.9
@export var parried_stun: float = 0.8

@export_group("Lock-on")
@export var lock_range: float = 20.0
@export var flick_threshold: float = 45.0

var state: int = State.MOVE
var state_time := 0.0
var game_time := 0.0
var lock_target: Combatant
var camera_controller: Node  # CameraController
var input_enabled := true
var spawn_transform: Transform3D

var _dodge_dir := Vector3.ZERO
var _dodge_requested_at := -100.0
var _stun_time := 0.0
var _attack_target: Combatant
var _lunge_left := 0.0
var _last_flick := -100.0

@onready var combat: PlayerCombat = $Combat


func _ready() -> void:
	faction = Faction.PLAYER
	super._ready()
	add_to_group(&"player")
	spawn_transform = global_transform
	attack_runner.finished.connect(_on_attack_finished)
	visual.footstep.connect(_on_footstep)


# --- Input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or state == State.DEAD:
		return
	if event.is_action_pressed(&"light_attack"):
		combat.buffer_attack(PlayerCombat.LIGHT)
	elif event.is_action_pressed(&"heavy_attack"):
		combat.buffer_attack(PlayerCombat.HEAVY)
	elif event.is_action_pressed(&"dodge"):
		_dodge_requested_at = game_time
	elif event.is_action_pressed(&"block"):
		combat.on_block_pressed()
	elif event.is_action_pressed(&"lock_on"):
		toggle_lock_on()
	elif event.is_action_pressed(&"switch_target"):
		switch_target(1)
	elif event is InputEventMouseMotion and lock_target and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if absf(event.relative.x) > flick_threshold and game_time - _last_flick > 0.35:
			_last_flick = game_time
			switch_target(signi(int(event.relative.x)))


func get_move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Camera-relative world direction from movement input (length 0..1).
func get_move_direction() -> Vector3:
	var v := get_move_input()
	if v.length_squared() < 0.0001:
		return Vector3.ZERO
	var basis := Basis.IDENTITY
	if camera_controller:
		basis = camera_controller.get_yaw_basis()
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	var dir := right.normalized() * v.x + forward.normalized() * -v.y
	return dir.limit_length(1.0)


func _block_held() -> bool:
	return input_enabled and Input.is_action_pressed(&"block")


func _dodge_pending() -> bool:
	return game_time - _dodge_requested_at <= 0.25


# --- State machine -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	game_time += delta
	state_time += delta
	_validate_lock_target()
	var move_dir := get_move_direction()
	var desired := Vector3.ZERO

	match state:
		State.MOVE:
			desired = _update_move(delta, move_dir)
		State.BLOCK:
			desired = _update_block(delta, move_dir)
		State.ATTACK:
			desired = _update_attack(delta)
		State.DODGE:
			desired = _update_dodge(delta)
		State.HITSTUN:
			_stun_time -= delta
			if _stun_time <= 0.0:
				_set_state(State.MOVE)
		State.DEAD:
			pass

	attack_runner.tick(delta)
	stamina.blocking = state == State.BLOCK

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if state == State.DODGE or state == State.ATTACK:
		horizontal = desired
	else:
		var rate := acceleration if desired.length() > horizontal.length() else deceleration
		horizontal = horizontal.move_toward(desired, rate * delta)
	horizontal += _decay_knockback(delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

	var local_vel := global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	visual.set_locomotion(local_vel, sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed)
	visual.set_guard(state == State.BLOCK)


func _set_state(new_state: int) -> void:
	if state == new_state:
		state_time = 0.0
		return
	state = new_state
	state_time = 0.0
	state_changed.emit(state)


func _update_move(delta: float, move_dir: Vector3) -> Vector3:
	if _block_held():
		_set_state(State.BLOCK)
		return Vector3.ZERO
	if _dodge_pending() and _try_dodge(move_dir):
		return _update_dodge(0.0)
	if combat.has_buffered_attack() and _try_attack(combat.combo_alive()):
		return Vector3.ZERO
	var speed := walk_speed
	var sprinting := Input.is_action_pressed(&"sprint") and move_dir.length() > 0.1 and stamina.current > 1.0
	if sprinting:
		speed = sprint_speed
		stamina.drain(sprint_stamina_per_sec, delta)
	elif _has_lock():
		speed = strafe_speed
	if _has_lock() and not sprinting:
		face_point(lock_target.global_position, turn_speed * delta)
	elif move_dir.length() > 0.1:
		face_direction(move_dir, turn_speed * delta)
	return move_dir * speed


func _update_block(delta: float, move_dir: Vector3) -> Vector3:
	if not _block_held():
		_set_state(State.MOVE)
		return Vector3.ZERO
	if _dodge_pending() and _try_dodge(move_dir):
		return _update_dodge(0.0)
	if combat.has_buffered_attack() and _try_attack(false):
		return Vector3.ZERO
	var threat := lock_target if _has_lock() else _nearest_enemy(6.0)
	if threat:
		face_point(threat.global_position, turn_speed * delta)
	return move_dir * block_speed


func _update_attack(delta: float) -> Vector3:
	if not attack_runner.is_running():
		_set_state(State.MOVE)
		return Vector3.ZERO
	var attack := attack_runner.attack
	# Cancels: dodge (startup or recovery window), block / next attack (recovery window).
	if _dodge_pending() and attack_runner.can_dodge_cancel():
		var dir := get_move_direction()
		attack_runner.cancel()
		if _try_dodge(dir):
			return _update_dodge(0.0)
		_set_state(State.MOVE)
		return Vector3.ZERO
	if attack_runner.in_cancel_window():
		if combat.has_buffered_attack():
			if _try_attack(true):
				return Vector3.ZERO
		elif _block_held():
			attack_runner.cancel()
			combat.on_attack_finished(attack)
			_set_state(State.BLOCK)
			return Vector3.ZERO
	# Track the target during startup, lunge through startup + active.
	if attack_runner.is_in_startup() and attack.track_target_during_startup and _attack_target and is_instance_valid(_attack_target):
		face_point(_attack_target.global_position, 18.0 * delta)
	if attack_runner.phase == AttackRunner.Phase.RECOVERY or _lunge_left <= 0.0:
		return Vector3.ZERO
	var lunge_time := maxf(attack.startup + attack.active, 0.05)
	var step_speed := attack.lunge_distance / lunge_time
	var step := minf(step_speed * delta, _lunge_left)
	if _attack_target and is_instance_valid(_attack_target):
		var gap := global_position.distance_to(_attack_target.global_position) - (body_radius + _attack_target.body_radius + 0.55)
		step = clampf(minf(step, gap), 0.0, _lunge_left)
	_lunge_left -= step
	return get_forward() * (step / maxf(delta, 0.0001))


func _update_dodge(delta: float) -> Vector3:
	if state != State.DODGE:
		return Vector3.ZERO
	if state_time >= dodge_duration:
		_set_state(State.MOVE)
		return Vector3.ZERO
	if state_time >= dodge_cancel_time:
		if combat.has_buffered_attack() and _try_attack(false):
			return Vector3.ZERO
	var t := clampf(state_time / dodge_duration, 0.0, 1.0)
	# Fast burst that eases out: integral of the speed curve over the dodge == dodge_distance.
	var speed := dodge_distance / dodge_duration * 2.0 * (1.0 - t)
	return _dodge_dir * speed


func _try_dodge(move_dir: Vector3) -> bool:
	_dodge_requested_at = -100.0
	if not stamina.try_consume(dodge_stamina):
		return false
	var dir := move_dir.normalized() if move_dir.length() > 0.1 else -get_forward()
	_dodge_dir = dir
	attack_runner.cancel()
	combat.clear_buffer()
	_set_state(State.DODGE)
	if not _has_lock() and move_dir.length() > 0.1:
		face_direction(dir, 1.0)
	visual.play_dodge(global_transform.basis.inverse() * dir, dodge_duration)
	AudioManager.play_sfx(&"dodge", global_position + Vector3.UP * 0.5)
	CombatFX.spawn_dust(global_position + Vector3.UP * 0.05, 6)
	return true


func _try_attack(continuing: bool) -> bool:
	var kind := combat.buffered
	if stamina.current < 1.0:
		return false
	var attack := combat.select_attack(kind, continuing)
	combat.clear_buffer()
	if attack == null:
		return false
	stamina.consume(attack.stamina_cost)
	_attack_target = combat.current_target
	if _attack_target:
		face_point(_attack_target.global_position, 0.7)
	elif get_move_direction().length() > 0.1:
		face_direction(get_move_direction(), 0.8)
	_lunge_left = attack.lunge_distance
	attack_runner.start(attack)
	combat.on_attack_started(attack)
	_set_state(State.ATTACK)
	CombatManager.announce_attack(self, attack)
	if attack.is_counter:
		AudioManager.play_ui(&"counter")
		CombatFX.slow_motion(0.4, 0.22)
		CombatFX.shake(0.2)
	elif attack.id == &"finishing_strike":
		AudioManager.play_ui(&"finisher")
		CombatFX.slow_motion(0.45, 0.2)
	return true


func _on_attack_finished(attack: AttackData) -> void:
	combat.on_attack_finished(attack)


# --- Combat queries / reactions ------------------------------------------------------

func is_invulnerable() -> bool:
	if state == State.DODGE and state_time >= dodge_iframes_start and state_time <= dodge_iframes_end:
		return true
	return super.is_invulnerable()


func is_parrying() -> bool:
	return state == State.BLOCK and combat.is_parry_active()


func is_blocking() -> bool:
	return state == State.BLOCK


func on_hit(info: HitInfo) -> void:
	if is_dead():
		_die()
		return
	if has_hyper_armor():
		visual.play_hit(0, global_transform.basis.inverse() * info.direction)
		return
	attack_runner.cancel()
	combat.reset_combo()
	_stun_time = hitstun_by_power[clampi(info.attack.stagger_power, 0, 3)]
	_set_state(State.HITSTUN)
	visual.play_hit(info.attack.stagger_power, global_transform.basis.inverse() * info.direction)


func on_blocked_hit(info: HitInfo) -> void:
	visual.play_block_impact()
	apply_knockback(info.direction, 0.25)
	if is_dead():
		_die()


func on_guard_broken(info: HitInfo) -> void:
	_stun_time = guard_break_stun
	_set_state(State.HITSTUN)
	visual.play_hit(2, global_transform.basis.inverse() * info.direction)
	if is_dead():
		_die()


func on_parried(_by: Combatant) -> void:
	attack_runner.cancel()
	_stun_time = parried_stun
	_set_state(State.HITSTUN)
	visual.play_parried(parried_stun)


func on_parry_success(attacker: Combatant, _attack: AttackData) -> void:
	combat.register_parry(attacker)
	visual.play_block_impact()
	CombatFX.slow_motion(0.35, 0.3)


func _die() -> void:
	if state == State.DEAD:
		return
	attack_runner.cancel()
	_set_state(State.DEAD)
	set_lock_target(null)
	visual.play_death()
	player_died.emit()


func _on_health_depleted() -> void:
	super._on_health_depleted()
	_die()


func revive(at: Transform3D = spawn_transform) -> void:
	health.restore_full()
	stamina.restore_full()
	global_transform = at
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	attack_runner.cancel()
	combat.reset_combo()
	combat.clear_buffer()
	set_lock_target(null)
	visual.reset_pose()
	_set_state(State.MOVE)
	player_revived.emit()


# --- Lock-on -------------------------------------------------------------------------

func _has_lock() -> bool:
	return lock_target != null and is_instance_valid(lock_target) and not lock_target.is_dead()


func set_lock_target(target: Combatant) -> void:
	if target == lock_target:
		return
	lock_target = target
	lock_target_changed.emit(target)


func toggle_lock_on() -> void:
	if _has_lock():
		set_lock_target(null)
		return
	set_lock_target(_best_lock_candidate())


func switch_target(direction: int) -> void:
	if not _has_lock():
		set_lock_target(_best_lock_candidate())
		return
	# Order candidates by screen-space angle around the camera and step left/right.
	var basis: Basis = camera_controller.get_yaw_basis() if camera_controller else global_transform.basis
	var cam_fwd := -basis.z
	var candidates: Array = []
	for c in _living_enemies(lock_range):
		var to := c.global_position - global_position
		to.y = 0.0
		candidates.append([cam_fwd.signed_angle_to(to.normalized(), Vector3.DOWN), c])
	if candidates.size() < 2:
		return
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var idx := 0
	for i in candidates.size():
		if candidates[i][1] == lock_target:
			idx = i
	set_lock_target(candidates[(idx + direction + candidates.size()) % candidates.size()][1])


func _best_lock_candidate() -> Combatant:
	var basis: Basis = camera_controller.get_yaw_basis() if camera_controller else global_transform.basis
	var cam_fwd := -basis.z
	cam_fwd.y = 0.0
	var best: Combatant
	var best_score := INF
	for c in _living_enemies(lock_range):
		var to := c.global_position - global_position
		to.y = 0.0
		var score := rad_to_deg(cam_fwd.angle_to(to.normalized())) + to.length() * 3.0
		if score < best_score:
			best_score = score
			best = c
	return best


func _validate_lock_target() -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or lock_target.is_dead() \
			or global_position.distance_to(lock_target.global_position) > lock_range * 1.25:
		var was_dead := is_instance_valid(lock_target) and lock_target.is_dead()
		lock_target = null
		# Keep the flow going: hop to the nearest enemy when the locked one falls.
		set_lock_target(_nearest_enemy(10.0) if was_dead else null)
		if lock_target == null:
			lock_target_changed.emit(null)


func _living_enemies(max_range: float) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var c := n as Combatant
		if c and not c.is_dead() and global_position.distance_to(c.global_position) <= max_range:
			out.append(c)
	return out


func _nearest_enemy(max_range: float) -> Combatant:
	var best: Combatant
	var best_d := max_range
	for c in _living_enemies(max_range):
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _on_footstep() -> void:
	AudioManager.play_sfx(&"footstep", global_position)
