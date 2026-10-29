class_name HitInfo
extends RefCounted
## One resolved strike from an attacker against a defender.

enum Result { HIT, BLOCKED, PARRIED, GUARD_BROKEN, DODGED, IGNORED }

var attacker: Node3D
var defender: Node3D
var attack: AttackData
var damage: float = 0.0
var direction: Vector3 = Vector3.FORWARD  # attacker -> defender, flattened
var point: Vector3 = Vector3.ZERO
var result: Result = Result.HIT
var killed := false
