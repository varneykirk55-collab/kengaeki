class_name EncounterManager
extends Node
## Owns the live encounter: enemy registry, attack-token coordination and the
## spawn/clear/reset sandbox actions exposed to the encounter menu.
##
## Coordination model:
##  * At most `max_active_attackers` enemies hold an attack token at once.
##  * Waiting enemies queue first-come-first-served (by the time they started waiting),
##    so every enemy eventually gets a turn; tokens expire after `token_max_hold`.
##  * Waiting enemies are spread evenly on a ring around the player (slot angles are
##    re-assigned periodically keeping each enemy near its current bearing).

signal enemy_count_changed(alive: int, pending: int)
signal encounter_reset

@export var enemy_scene: PackedScene = preload("res://scenes/characters/enemy.tscn")
@export_range(1, 6) var max_active_attackers: int = 2
@export var token_max_hold: float = 5.0
@export var slot_refresh_interval: float = 0.5
## Ring positions are clamped to this half-extent so slots never fall behind walls.
@export var arena_half_extent: float = 18.8

var player: Player
var enemies: Array[Enemy] = []
var last_requested_count := 3

var _tokens: Dictionary = {}  # Enemy -> grant time
var _cooldowns: Dictionary = {}  # Enemy -> time when it may request again
var _waiting: Dictionary = {}  # Enemy -> time it began waiting
var _slot_angles: Dictionary = {}  # Enemy -> radians around the player
var _time := 0.0
var _slot_timer := 0.0
## Stats for testing / debugging.
var peak_active_attackers := 0
var tokens_granted: Dictionary = {}  # Enemy instance id -> count

@onready var spawner: SpawnManager = $SpawnManager


func _ready() -> void:
	spawner.enemy_scene = enemy_scene
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	spawner.queue_changed.connect(func(_n): _emit_count())


func _physics_process(delta: float) -> void:
	_time += delta
	for e in _tokens.keys():
		if not _is_live(e) or _time - _tokens[e] > token_max_hold:
			_tokens.erase(e)
	_slot_timer -= delta
	if _slot_timer <= 0.0:
		_slot_timer = slot_refresh_interval
		_assign_slots()


# --- Sandbox actions ---------------------------------------------------------------

func spawn_enemies(count: int, interval: float) -> void:
	last_requested_count = count
	spawner.queue_spawns(count, interval)


func clear_enemies() -> void:
	spawner.cancel()
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.remove()
	enemies.clear()
	_tokens.clear()
	_waiting.clear()
	_cooldowns.clear()
	_slot_angles.clear()
	_emit_count()


func reset_encounter() -> void:
	clear_enemies()
	CombatFX.clear_time_effects()
	if player:
		player.revive()
	peak_active_attackers = 0
	tokens_granted.clear()
	encounter_reset.emit()


func restore_player_health() -> void:
	if player and not player.is_dead():
		player.health.restore_full()
		player.stamina.restore_full()


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if _is_live(e):
			n += 1
	return n


func _on_enemy_spawned(enemy: Enemy) -> void:
	enemy.coordinator = self
	enemy.target = player
	enemies.append(enemy)
	enemy.died.connect(func(_c): _on_enemy_died(enemy))
	enemy.removed.connect(_on_enemy_removed)
	_emit_count()


func _on_enemy_died(enemy: Enemy) -> void:
	release_attack(enemy, 0.0)
	_waiting.erase(enemy)
	_emit_count()


func _on_enemy_removed(enemy: Enemy) -> void:
	enemies.erase(enemy)
	_tokens.erase(enemy)
	_waiting.erase(enemy)
	_cooldowns.erase(enemy)
	_slot_angles.erase(enemy)
	_emit_count()


func _emit_count() -> void:
	enemy_count_changed.emit(alive_count(), spawner.pending_count())


func _is_live(e) -> bool:
	return e != null and is_instance_valid(e) and not e.is_dead()


# --- Attack tokens -----------------------------------------------------------------

func begin_waiting(enemy: Enemy) -> void:
	if not _waiting.has(enemy):
		_waiting[enemy] = _time


func end_waiting(enemy: Enemy) -> void:
	_waiting.erase(enemy)


func active_attacker_count() -> int:
	return _tokens.size()


func has_attack_token(enemy: Enemy) -> bool:
	return _tokens.has(enemy)


## Grants a token if a slot is free and this enemy is next in line.
## `opportunistic` requests (e.g. a riposte after blocking) skip the queue but still
## respect the attacker limit.
func request_attack(enemy: Enemy, opportunistic: bool = false) -> bool:
	if _tokens.has(enemy):
		return true
	if not _is_live(enemy) or player == null or player.is_dead():
		return false
	if _time < _cooldowns.get(enemy, 0.0):
		return false
	var free := max_active_attackers - _tokens.size()
	if free <= 0:
		return false
	if not opportunistic:
		# Rank eligible waiting enemies by how long they have waited.
		var queue: Array = []
		for e in _waiting.keys():
			if _is_live(e) and not _tokens.has(e) and _time >= _cooldowns.get(e, 0.0):
				queue.append(e)
		queue.sort_custom(func(a, b): return _waiting[a] < _waiting[b])
		var rank := queue.find(enemy)
		if rank == -1 or rank >= free:
			return false
	_tokens[enemy] = _time
	_waiting.erase(enemy)
	peak_active_attackers = maxi(peak_active_attackers, _tokens.size())
	var key := enemy.get_instance_id()
	tokens_granted[key] = tokens_granted.get(key, 0) + 1
	return true


func release_attack(enemy: Enemy, cooldown: float) -> void:
	_tokens.erase(enemy)
	if cooldown > 0.0:
		_cooldowns[enemy] = _time + cooldown


# --- Ring slots --------------------------------------------------------------------

func get_ring_position(enemy: Enemy, radius: float = -1.0) -> Vector3:
	if player == null:
		return enemy.global_position
	if radius < 0.0:
		radius = enemy.ring_radius
	var angle: float = _slot_angles.get(enemy, _bearing(enemy))
	var p := player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * radius
	p.x = clampf(p.x, -arena_half_extent, arena_half_extent)
	p.z = clampf(p.z, -arena_half_extent, arena_half_extent)
	return p


func _bearing(enemy: Enemy) -> float:
	var d := enemy.global_position - player.global_position
	return atan2(d.x, d.z)


## Spreads non-attacking enemies evenly around the player while keeping their order
## around the circle (minimises crossing paths).
func _assign_slots() -> void:
	if player == null:
		return
	var ring: Array = []
	for e in enemies:
		if _is_live(e) and not _tokens.has(e):
			ring.append([_bearing(e), e])
	if ring.is_empty():
		return
	ring.sort_custom(func(a, b): return a[0] < b[0])
	var n := ring.size()
	var spacing := TAU / n
	# Rotation offset that best matches current bearings (circular mean of residuals).
	var sx := 0.0
	var sy := 0.0
	for i in n:
		var residual: float = ring[i][0] - i * spacing
		sx += cos(residual)
		sy += sin(residual)
	var offset := atan2(sy, sx)
	# Attackers occupy the front; leave a gap there when only a few wait.
	for i in n:
		_slot_angles[ring[i][1]] = offset + i * spacing
