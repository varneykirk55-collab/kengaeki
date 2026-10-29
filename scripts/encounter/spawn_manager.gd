class_name SpawnManager
extends Node
## Sequential, safe enemy spawning. Requests are queued; one enemy enters every
## `interval` seconds at a free spawn point away from the player. Requests made while
## a wave is still entering are appended (up to max_pending / max_alive limits).

signal enemy_spawned(enemy: Enemy)
signal queue_changed(pending: int)

@export var max_alive: int = 16
@export var max_pending: int = 20
@export var min_player_distance: float = 7.0
@export var min_enemy_distance: float = 2.2
@export var retry_delay: float = 0.25

var enemy_scene: PackedScene
var spawn_points: Array[Node3D] = []
var container: Node3D
var player: Node3D
var interval := 2.0
var spawn_log: Array[float] = []  # game-time of each spawn (used by tests)

var _pending := 0
var _timer := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func pending_count() -> int:
	return _pending


func queue_spawns(count: int, spawn_interval: float) -> void:
	interval = maxf(spawn_interval, 0.1)
	var before := _pending
	_pending = clampi(_pending + maxi(count, 0), 0, max_pending)
	if before == 0:
		_timer = 0.0  # first enemy of a new wave enters immediately
	queue_changed.emit(_pending)


func cancel() -> void:
	_pending = 0
	queue_changed.emit(_pending)


func _physics_process(delta: float) -> void:
	_time += delta
	if _pending <= 0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _alive() >= max_alive:
		_timer = retry_delay
		return
	var point := _choose_point()
	if point == null:
		_timer = retry_delay
		return
	_spawn_at(point)
	_pending -= 1
	_timer = interval
	queue_changed.emit(_pending)


func _alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not e.is_dead():
			n += 1
	return n


func _choose_point() -> Node3D:
	var valid: Array = []
	for p in spawn_points:
		var pos := p.global_position
		if player and pos.distance_to(player.global_position) < min_player_distance:
			continue
		var blocked := false
		for e in get_tree().get_nodes_in_group(&"enemies"):
			if not e.is_dead() and (e as Node3D).global_position.distance_to(pos) < min_enemy_distance:
				blocked = true
				break
		if not blocked:
			valid.append(p)
	if valid.is_empty():
		return null
	# Prefer the farther half from the player so enemies walk in rather than pop in close.
	if player:
		valid.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) > b.global_position.distance_to(player.global_position))
		valid = valid.slice(0, maxi(1, ceili(valid.size() / 2.0)))
	return valid[_rng.randi() % valid.size()]


func _spawn_at(point: Node3D) -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.target = player as Player
	(container if container else get_tree().current_scene).add_child(enemy)
	enemy.global_position = point.global_position
	if player:
		enemy.face_point(player.global_position)
	spawn_log.append(_time)
	enemy_spawned.emit(enemy)
	CombatFX.spawn_dust(point.global_position + Vector3.UP * 0.1, 10)
