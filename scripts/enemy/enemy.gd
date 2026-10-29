class_name Enemy
extends Combatant
## Katana-wielding enemy. Simpler than the player: a handful of telegraphed attacks,
## reactive blocking, stagger/parry vulnerability. Decisions come from the modular
## EnemyAI state machine; group behaviour from the EncounterManager's coordinator.

signal removed(enemy: Enemy)

@export_group("Movement")
@export var walk_speed: float = 2.6
@export var run_speed: float = 4.6
@export var acceleration: float = 18.0
@export var turn_speed: float = 7.0
@export var gravity: float = 22.0
@export var use_navigation: bool = true

@export_group("Combat")
@export var attack_folder: String = "res://resources/attacks/enemy"
@export var attack_range: float = 2.0
## Radius of the ring that waiting enemies hold around the player.
@export var ring_radius: float = 4.6
@export var detection_range: float = 40.0
@export_range(0.0, 1.0) var block_chance: float = 0.3
## Block chance grows with each consecutive clean hit taken (they adapt to spam).
@export var block_chance_per_hit: float = 0.12
@export var max_block_chance: float = 0.75
@export_range(0.0, 1.0) var heavy_chance: float = 0.25
@export var stagger_by_power: Array[float] = [0.2, 0.45, 0.9, 1.5]
@export var parried_stagger: float = 1.6
@export var guard_break_stagger: float = 1.7

@export_group("Cleanup")
## Seconds a corpse stays before sinking away (<= 0 keeps it until cleared).
@export var corpse_time: float = 5.0

var attacks: Dictionary = {}
var target: Player
var coordinator: Node  # EncounterManager
var desired_velocity := Vector3.ZERO
var consecutive_hits := 0
var rng := RandomNumberGenerator.new()

var _nav_goal := Vector3(INF, INF, INF)
var _dead_time := 0.0
var _removed := false

@onready var ai: EnemyAI = $AI
@onready var nav: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	faction = Faction.ENEMY
	super._ready()
	add_to_group(&"enemies")
	rng.randomize()
	for file in DirAccess.get_files_at(attack_folder):
		var clean := file.trim_suffix(".remap")
		if clean.get_extension() == "tres":
			var a := load(attack_folder.path_join(clean)) as AttackData
			if a:
				attacks[a.id] = a
	CombatManager.attack_started.connect(_on_any_attack_started)
	visual.footstep.connect(func(): AudioManager.play_sfx(&"footstep", global_position, -4.0))
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Player


func _physics_process(delta: float) -> void:
	if is_dead():
		_update_corpse(delta)
		return
	ai.physics_update(delta)
	attack_runner.tick(delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if attack_runner.is_running() or ai.current_name == &"stagger":
		horizontal = desired_velocity
	else:
		horizontal = horizontal.move_toward(desired_velocity + separation() * 2.2, acceleration * delta)
	horizontal += _decay_knockback(delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	var local_vel := global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	visual.set_locomotion(local_vel, run_speed)
	visual.set_guard(is_blocking())


# --- Movement helpers used by AI states --------------------------------------------

func has_target() -> bool:
	return target != null and is_instance_valid(target) and not target.is_dead()


func distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var d := target.global_position - global_position
	d.y = 0.0
	return d.length()


## Steers toward a world point (via the navmesh when available). Returns remaining distance.
func move_toward_point(point: Vector3, speed: float) -> float:
	var to := point - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.15:
		desired_velocity = Vector3.ZERO
		return dist
	var dir := to / dist
	if use_navigation and nav and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
		if point.distance_to(_nav_goal) > 0.6:
			nav.target_position = point
			_nav_goal = point
		var next := nav.get_next_path_position()
		var step := next - global_position
		step.y = 0.0
		if step.length() > 0.05:
			dir = step.normalized()
	desired_velocity = dir * speed
	return dist


func stop_moving() -> void:
	desired_velocity = Vector3.ZERO


## Pushes away from nearby enemies so groups do not stack up.
func separation() -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e == null or e == self or e.is_dead():
			continue
		var away := global_position - e.global_position
		away.y = 0.0
		var d := away.length()
		if d < 1.7 and d > 0.001:
			push += away / d * (1.7 - d)
	return push


func choose_attack_sequence() -> Array[AttackData]:
	var seq: Array[AttackData] = []
	var roll := rng.randf()
	if roll < heavy_chance:
		seq.append(attacks[&"enemy_heavy"])
	elif roll < heavy_chance + 0.2:
		seq.append(attacks[&"enemy_thrust"])
	elif roll < heavy_chance + 0.55:
		seq.append(attacks[&"enemy_slash"])
		seq.append(attacks[&"enemy_slash_2"])
	else:
		seq.append(attacks[&"enemy_slash"])
	return seq


func start_attack(attack: AttackData) -> void:
	attack_runner.start(attack)
	CombatManager.announce_attack(self, attack)


# --- Combat reactions --------------------------------------------------------------

func is_blocking() -> bool:
	return ai.current_name == &"block" and not is_dead()


func is_vulnerable() -> bool:
	return ai.current_name == &"stagger" and ai.current_state.vulnerable and not is_dead()


func _on_any_attack_started(attacker: Combatant, attack: AttackData) -> void:
	if is_dead() or attacker.faction == faction or not has_target() or not ai.enabled:
		return
	if not ai.current_name in [&"circle", &"approach", &"engage", &"idle"]:
		return
	if global_position.distance_to(attacker.global_position) > attack.reach + 1.2:
		return
	if not is_facing_point(attacker.global_position, 75.0) or attack.unblockable:
		return
	var chance := minf(block_chance + consecutive_hits * block_chance_per_hit, max_block_chance)
	if rng.randf() < chance:
		ai.transition(&"block", {"duration": rng.randf_range(0.5, 1.0)})


func on_hit(info: HitInfo) -> void:
	consecutive_hits += 1
	if is_dead():
		return
	var local_dir := global_transform.basis.inverse() * info.direction
	if has_hyper_armor() and info.attack.stagger_power < 3:
		visual.play_hit(0, local_dir)
		return
	var power := info.attack.stagger_power
	attack_runner.cancel()
	visual.play_hit(power, local_dir)
	ai.transition(&"stagger", {"duration": stagger_by_power[clampi(power, 0, 3)], "vulnerable": power >= 3})


func on_blocked_hit(info: HitInfo) -> void:
	consecutive_hits = 0
	visual.play_block_impact()
	apply_knockback(info.direction, 0.3)


func on_guard_broken(info: HitInfo) -> void:
	consecutive_hits = 0
	attack_runner.cancel()
	visual.play_hit(2, global_transform.basis.inverse() * info.direction)
	ai.transition(&"stagger", {"duration": guard_break_stagger, "vulnerable": true})


func on_parried(_by: Combatant) -> void:
	attack_runner.cancel()
	visual.play_parried(parried_stagger)
	ai.transition(&"stagger", {"duration": parried_stagger, "vulnerable": true})


func _on_health_depleted() -> void:
	super._on_health_depleted()
	ai.transition(&"dead")
	if coordinator:
		coordinator.release_attack(self, 0.0)
	collision_layer = 0
	collision_mask = 1
	hurtbox.collision_layer = 0
	desired_velocity = Vector3.ZERO
	visual.play_death()


func _update_corpse(delta: float) -> void:
	_dead_time += delta
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if corpse_time > 0.0 and _dead_time > corpse_time:
		visual.position.y -= delta * 0.6
		if _dead_time > corpse_time + 1.5:
			remove()


## Removes the enemy from the arena immediately (used by cleanup and Clear Enemies).
func remove() -> void:
	if _removed:
		return
	_removed = true
	if coordinator:
		coordinator.release_attack(self, 0.0)
	removed.emit(self)
	queue_free()
