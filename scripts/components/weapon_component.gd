class_name WeaponComponent
extends Node
## Hit detection for a katana wielder.
##
## ARC_SWEEP (default): the blade's path is modelled as an arc in front of the wielder
## that is swept progressively across the attack's active window. Every physics tick
## only the newly swept slice is tested, so fast swings cannot tunnel and each target is
## struck at the moment the blade actually passes it.
## BLADE_AREA: uses the katana's Area3D overlapping hurtboxes (for animation-driven
## attacks once real swing animations exist). Both modes go through CombatManager.

enum DetectionMode { ARC_SWEEP, BLADE_AREA }

signal target_struck(target: Node3D, result: int)

@export var detection_mode: DetectionMode = DetectionMode.ARC_SWEEP
## Extra angular tolerance (degrees) on top of the target's body width.
@export var angle_padding: float = 6.0

var wielder: Combatant
var katana: Katana
var window_open := false
var _attack: AttackData
var _struck: Array[Node3D] = []


func _ready() -> void:
	wielder = get_parent() as Combatant


func begin_hit_window(attack: AttackData) -> void:
	window_open = true
	_attack = attack
	_struck.clear()
	if katana:
		katana.set_trail_emitting(true)


func end_hit_window() -> void:
	window_open = false
	_attack = null
	if katana:
		katana.set_trail_emitting(false)


func struck_count() -> int:
	return _struck.size()


## Tests the slice of the swing between progress p0 and p1 (0..1 of the active window).
func sweep(attack: AttackData, p0: float, p1: float) -> void:
	if not window_open or attack != _attack or wielder == null:
		return
	var candidates: Array[Node3D] = []
	if detection_mode == DetectionMode.BLADE_AREA and katana and katana.blade_area:
		for area in katana.blade_area.get_overlapping_areas():
			var c := area.get_meta(&"combatant", null) as Combatant
			if c and not candidates.has(c):
				candidates.append(c)
	else:
		var a0 := lerpf(attack.sweep_from, attack.sweep_to, p0)
		var a1 := lerpf(attack.sweep_from, attack.sweep_to, p1)
		for node in get_tree().get_nodes_in_group(&"combatants"):
			var c := node as Combatant
			if c and _in_arc_slice(c, attack, minf(a0, a1), maxf(a0, a1)):
				candidates.append(c)
	# Nearest targets first so max_targets prefers what the blade meets first.
	candidates.sort_custom(func(a, b): return wielder.global_position.distance_squared_to(a.global_position) < wielder.global_position.distance_squared_to(b.global_position))
	for target in candidates:
		if not window_open:
			return  # e.g. the swing was parried by an earlier target
		var c := target as Combatant
		if c == wielder or _struck.has(c) or c.faction == wielder.faction or c.is_dead():
			continue
		if attack.max_targets > 0 and _struck.size() >= attack.max_targets:
			return
		_struck.append(c)
		var result := CombatManager.resolve_hit(wielder, c, attack)
		target_struck.emit(c, result)


func _in_arc_slice(target: Combatant, attack: AttackData, lo: float, hi: float) -> bool:
	if target == wielder or target.faction == wielder.faction or target.is_dead():
		return false
	var to_target := target.global_position - wielder.global_position
	if absf(to_target.y) > 1.6:
		return false
	var local := wielder.global_transform.basis.orthonormalized().inverse() * to_target
	var flat := Vector2(local.x, local.z)
	var dist := flat.length()
	if dist - target.body_radius > attack.reach:
		return false
	if dist < 0.05:
		return true
	var angle := rad_to_deg(atan2(local.x, -local.z))
	var tolerance := rad_to_deg(atan2(target.body_radius, dist)) + angle_padding
	return angle >= lo - tolerance and angle <= hi + tolerance
