class_name EnemyAI
extends Node
## Minimal hierarchical-free state machine hosting modular EnemyState objects.
## Add a behaviour by writing a new EnemyState script and registering it in STATES.

signal state_changed(from: StringName, to: StringName)

const STATES := {
	&"enter": preload("res://scripts/enemy/states/enter_state.gd"),
	&"idle": preload("res://scripts/enemy/states/idle_state.gd"),
	&"approach": preload("res://scripts/enemy/states/approach_state.gd"),
	&"circle": preload("res://scripts/enemy/states/circle_state.gd"),
	&"engage": preload("res://scripts/enemy/states/engage_state.gd"),
	&"attack": preload("res://scripts/enemy/states/attack_state.gd"),
	&"block": preload("res://scripts/enemy/states/block_state.gd"),
	&"stagger": preload("res://scripts/enemy/states/stagger_state.gd"),
	&"dead": preload("res://scripts/enemy/states/dead_state.gd"),
}

@export var initial_state: StringName = &"enter"
## When false the enemy stands still (used by tests and for debugging).
@export var enabled: bool = true

var enemy: Enemy
var current_state: EnemyState
var current_name: StringName = &""
var time_in_state := 0.0
var _states: Dictionary = {}


func _ready() -> void:
	enemy = get_parent() as Enemy
	for key in STATES:
		var s: EnemyState = STATES[key].new()
		s.ai = self
		s.enemy = enemy
		s.name = key
		_states[key] = s
	transition.call_deferred(initial_state)


func transition(to: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(to):
		push_error("EnemyAI: unknown state %s" % to)
		return
	if current_name == &"dead":
		return
	var from := current_name
	if current_state:
		current_state.exit()
	current_state = _states[to]
	current_name = to
	time_in_state = 0.0
	current_state.enter(msg)
	state_changed.emit(from, to)


func physics_update(delta: float) -> void:
	if current_state == null:
		return
	time_in_state += delta
	if not enabled and current_name != &"stagger" and current_name != &"dead":
		enemy.stop_moving()
		return
	current_state.update(delta)
