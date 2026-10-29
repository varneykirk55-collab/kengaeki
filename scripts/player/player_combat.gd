class_name PlayerCombat
extends Node
## Player sword logic: input buffering, combo graph, parry timing, parry counters and
## finishing strikes. Movement/state transitions live in Player; this node decides
## *which* technique to perform and owns the defensive timing windows.

signal counter_window_opened(target: Combatant)
signal attack_performed(attack: AttackData)
signal parry_succeeded(attacker: Combatant)

const LIGHT := &"light"
const HEAVY := &"heavy"

## Combo graph: previous technique -> input -> next technique.
const COMBO := {
	&"none": {LIGHT: &"light_1", HEAVY: &"heavy_1"},
	&"light_1": {LIGHT: &"light_2", HEAVY: &"light_heavy"},
	&"light_2": {LIGHT: &"light_3", HEAVY: &"finisher_kesa"},
	&"light_3": {LIGHT: &"light_1", HEAVY: &"heavy_1"},
	&"heavy_1": {LIGHT: &"heavy_light", HEAVY: &"heavy_1"},
	&"light_heavy": {LIGHT: &"light_2", HEAVY: &"heavy_1"},
	&"heavy_light": {LIGHT: &"light_2", HEAVY: &"light_heavy"},
	&"finisher_kesa": {LIGHT: &"light_1", HEAVY: &"heavy_1"},
	&"counter_riposte": {LIGHT: &"light_2", HEAVY: &"heavy_1"},
	&"finishing_strike": {LIGHT: &"light_1", HEAVY: &"heavy_1"},
}

@export var attack_folder: String = "res://resources/attacks/player"
## How long a pressed attack stays buffered (seconds).
@export var input_buffer_time: float = 0.4
## After an attack fully ends, the combo can still be continued for this long.
@export var combo_grace: float = 0.3
## Parry window opened by pressing block (seconds).
@export var parry_window: float = 0.2
## Pressing block again sooner than this after a failed parry gives no parry window (anti-mash).
@export var parry_cooldown: float = 0.4
@export var counter_window: float = 1.1
@export var counter_range: float = 4.5
@export var finisher_range: float = 3.4
@export var soft_target_range: float = 4.5

var attacks: Dictionary = {}  # StringName -> AttackData
var buffered: StringName = &""
var buffered_at := -100.0
var last_attack_id: StringName = &""
var last_attack_end := -100.0
var parry_until := -100.0
var last_parry_press := -100.0
var last_parry_success := -100.0
var counter_target: Combatant
var counter_until := -100.0
var current_target: Combatant

@onready var player: Player = get_parent()


func _ready() -> void:
	for file in DirAccess.get_files_at(attack_folder):
		var clean := file.trim_suffix(".remap")
		if clean.get_extension() == "tres":
			var a := load(attack_folder.path_join(clean)) as AttackData
			if a:
				attacks[a.id] = a
	if attacks.size() < 9:
		push_error("PlayerCombat: expected 9 attacks, found %d" % attacks.size())


func now() -> float:
	return player.game_time


func buffer_attack(kind: StringName) -> void:
	buffered = kind
	buffered_at = now()


func has_buffered_attack() -> bool:
	return buffered != &"" and now() - buffered_at <= input_buffer_time


func clear_buffer() -> void:
	buffered = &""


# --- Defence -----------------------------------------------------------------------

func on_block_pressed() -> void:
	var t := now()
	if t - last_parry_press >= parry_cooldown or last_parry_success >= last_parry_press:
		parry_until = t + parry_window
	last_parry_press = t


func is_parry_active() -> bool:
	return now() <= parry_until


func register_parry(attacker: Combatant) -> void:
	last_parry_success = now()
	parry_until = -100.0
	counter_target = attacker
	counter_until = now() + counter_window
	player.stamina.current = minf(player.stamina.max_stamina, player.stamina.current + 15.0)
	parry_succeeded.emit(attacker)
	counter_window_opened.emit(attacker)


func has_counter_opportunity() -> bool:
	return counter_target != null and is_instance_valid(counter_target) and not counter_target.is_dead() \
		and now() <= counter_until \
		and player.global_position.distance_to(counter_target.global_position) <= counter_range


# --- Offence -----------------------------------------------------------------------

## Picks the next technique for the buffered input, or null if nothing should start.
func select_attack(kind: StringName, continuing_combo: bool) -> AttackData:
	if has_counter_opportunity():
		current_target = counter_target
		counter_target = null
		counter_until = -100.0
		return attacks.get(&"counter_riposte")
	if kind == HEAVY:
		var victim := find_finisher_target()
		if victim:
			current_target = victim
			return attacks.get(&"finishing_strike")
	var from: StringName = last_attack_id if continuing_combo and last_attack_id != &"" else &"none"
	var row: Dictionary = COMBO.get(from, COMBO[&"none"])
	var next_id: StringName = row.get(kind, &"light_1")
	current_target = find_attack_target()
	return attacks.get(next_id)


## Returns true if the combo chain from the previous attack is still alive.
func combo_alive() -> bool:
	return last_attack_id != &"" and now() - last_attack_end <= combo_grace


func on_attack_started(attack: AttackData) -> void:
	last_attack_id = attack.id
	attack_performed.emit(attack)


func on_attack_finished(_attack: AttackData) -> void:
	last_attack_end = now()


func reset_combo() -> void:
	last_attack_id = &""
	last_attack_end = -100.0


func find_finisher_target() -> Combatant:
	var best: Combatant
	var best_d := finisher_range
	for c in _enemies():
		if c.is_vulnerable():
			var d := player.global_position.distance_to(c.global_position)
			if d <= best_d and (c == player.lock_target or player.is_facing_point(c.global_position, 100.0)):
				best_d = d
				best = c
	return best


## Lock-on target if close enough, otherwise the enemy best matching where the player is
## aiming (movement input, or facing when idle).
func find_attack_target() -> Combatant:
	if player.lock_target and is_instance_valid(player.lock_target) and not player.lock_target.is_dead() \
			and player.global_position.distance_to(player.lock_target.global_position) <= 7.0:
		return player.lock_target
	var aim := player.get_move_direction()
	if aim.length_squared() < 0.01:
		aim = player.get_forward()
	var best: Combatant
	var best_score := INF
	for c in _enemies():
		var to := c.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d > soft_target_range:
			continue
		var angle := rad_to_deg(aim.angle_to(to.normalized())) if d > 0.01 else 0.0
		if angle > 85.0 and d > 2.2:
			continue
		var score := angle + d * 12.0
		if score < best_score:
			best_score = score
			best = c
	return best


func _enemies() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var c := n as Combatant
		if c and not c.is_dead():
			out.append(c)
	return out
