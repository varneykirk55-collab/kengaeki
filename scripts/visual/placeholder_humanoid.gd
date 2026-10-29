class_name PlaceholderHumanoid
extends CharacterVisual
## Procedural stand-in body built from primitives, animated with keyed sword poses.
##
## Attack poses are sampled from the owner's AttackRunner (phase + progress), so what you
## see is exactly the gameplay timing: windup during startup, the cut during the active
## hit window, follow-through during recovery. Replace with ImportedHumanoidVisual once
## Hunyuan models / animations are available (see docs/ASSET_INTEGRATION.md).

enum Headgear { TOPKNOT, KASA, HACHIMAKI }

@export var cloth_color: Color = Color(0.13, 0.15, 0.3)
@export var hakama_color: Color = Color(0.1, 0.1, 0.12)
@export var skin_color: Color = Color(0.86, 0.7, 0.56)
@export var accent_color: Color = Color(0.7, 0.16, 0.12)
@export var headgear: Headgear = Headgear.TOPKNOT
@export var katana_scene: PackedScene = preload("res://scenes/weapons/katana.tscn")

const HIP_HEIGHT := 0.95
const UPPER_ARM := 0.31
const FOREARM := 0.31

## Pose = sword pivot position "sp" (torso space), sword rotation "sr" (deg),
## torso rotation "t" (deg), crouch "c" (m), optional rig spin "spin" (deg).
const POSES := {
	&"guard": {"sp": Vector3(0.06, 0.26, -0.34), "sr": Vector3(28, 0, 0), "t": Vector3(0, -8, 0), "c": 0.04},
	&"block": {"sp": Vector3(0.14, 0.52, -0.3), "sr": Vector3(8, 78, 0), "t": Vector3(0, -12, 0), "c": 0.1},
	&"sprint": {"sp": Vector3(0.22, 0.08, -0.1), "sr": Vector3(-20, -150, 0), "t": Vector3(-14, 0, 0), "c": 0.02},
	&"stagger": {"sp": Vector3(0.22, 0.2, -0.18), "sr": Vector3(-30, -40, 0), "t": Vector3(16, 18, 0), "c": 0.12},
	&"parried": {"sp": Vector3(0.18, 0.8, 0.05), "sr": Vector3(115, -30, 0), "t": Vector3(20, -10, 0), "c": 0.05},
	&"knockdown": {"sp": Vector3(0.25, 0.1, -0.1), "sr": Vector3(-50, -60, 0), "t": Vector3(30, 20, 0), "c": 0.3},
}

## Attack animation keys -> windup pose and strike-end pose.
const ATTACK_POSES := {
	&"slash_rl": [
		{"sp": Vector3(0.32, 0.46, -0.06), "sr": Vector3(12, -115, 0), "t": Vector3(0, -42, 0), "c": 0.08},
		{"sp": Vector3(-0.26, 0.3, -0.26), "sr": Vector3(-4, 105, 0), "t": Vector3(-6, 38, 0), "c": 0.12}],
	&"slash_lr": [
		{"sp": Vector3(-0.3, 0.42, -0.08), "sr": Vector3(10, 115, 0), "t": Vector3(0, 40, 0), "c": 0.08},
		{"sp": Vector3(0.3, 0.28, -0.26), "sr": Vector3(-6, -105, 0), "t": Vector3(-6, -40, 0), "c": 0.12}],
	&"overhead": [
		{"sp": Vector3(0.02, 0.78, 0.04), "sr": Vector3(112, 0, 0), "t": Vector3(10, -6, 0), "c": 0.0},
		{"sp": Vector3(0.02, 0.08, -0.38), "sr": Vector3(-38, 0, 0), "t": Vector3(-24, 0, 0), "c": 0.2}],
	&"kesa": [
		{"sp": Vector3(0.3, 0.76, 0.0), "sr": Vector3(70, -60, 0), "t": Vector3(6, -34, 0), "c": 0.02},
		{"sp": Vector3(-0.26, 0.04, -0.3), "sr": Vector3(-34, 72, 0), "t": Vector3(-20, 34, 0), "c": 0.22}],
	&"rising": [
		{"sp": Vector3(-0.22, 0.02, -0.26), "sr": Vector3(-42, 62, 0), "t": Vector3(-14, 30, 0), "c": 0.2},
		{"sp": Vector3(0.26, 0.82, -0.1), "sr": Vector3(72, -52, 0), "t": Vector3(10, -30, 0), "c": 0.0}],
	&"thrust": [
		{"sp": Vector3(0.12, 0.3, 0.06), "sr": Vector3(4, 0, 0), "t": Vector3(0, -24, 0), "c": 0.12},
		{"sp": Vector3(0.04, 0.36, -0.52), "sr": Vector3(0, 0, 0), "t": Vector3(-14, 6, 0), "c": 0.18}],
	&"spin": [
		{"sp": Vector3(-0.3, 0.38, -0.12), "sr": Vector3(6, 100, 0), "t": Vector3(0, 30, 0), "c": 0.16},
		{"sp": Vector3(0.36, 0.34, -0.2), "sr": Vector3(0, -90, 0), "t": Vector3(0, -20, 0), "c": 0.18, "spin": 360.0}],
}

var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _sword_pivot: Node3D
var _katana: Katana
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arm_segments: Array[MeshInstance3D] = []  # [r_upper, r_fore, l_upper, l_fore]
var _materials: Array[StandardMaterial3D] = []

var _pose: Dictionary = POSES[&"guard"].duplicate()
var _attack_from: Dictionary = {}
var _tracked_attack: AttackData
var _tracked_elapsed := -1.0
var _guard := false
var _local_velocity := Vector3.ZERO
var _max_speed := 1.0
var _gait_phase := 0.0
var _dodge_time := 0.0
var _dodge_duration := 0.0
var _dodge_dir := Vector3.ZERO
var _react_time := 0.0
var _react_duration := 0.0
var _react_power := 0
var _react_dir := Vector3.ZERO
var _parried_time := 0.0
var _dead := false
var _death_t := 0.0
var _flash := 0.0
var _block_kick := 0.0


func _ready() -> void:
	_build_body()


func get_katana() -> Katana:
	return _katana


func set_locomotion(local_velocity: Vector3, max_speed: float) -> void:
	_local_velocity = local_velocity
	_max_speed = maxf(max_speed, 0.1)


func set_guard(blocking: bool) -> void:
	_guard = blocking


func play_dodge(local_direction: Vector3, duration: float) -> void:
	_dodge_dir = local_direction.normalized()
	_dodge_duration = duration
	_dodge_time = duration


func play_hit(power: int, local_direction: Vector3) -> void:
	_react_power = power
	_react_dir = local_direction
	_react_duration = [0.2, 0.32, 0.75, 1.3][clampi(power, 0, 3)]
	_react_time = _react_duration
	_flash = 1.0


func play_block_impact() -> void:
	_block_kick = 1.0


func play_parried(duration: float) -> void:
	_parried_time = duration
	_react_time = 0.0


func play_death() -> void:
	_dead = true
	_death_t = 0.0
	_flash = 1.0


func reset_pose() -> void:
	_dead = false
	_death_t = 0.0
	_react_time = 0.0
	_parried_time = 0.0
	_dodge_time = 0.0
	_flash = 0.0
	_tracked_attack = null
	_rig.transform = Transform3D.IDENTITY
	_pose = POSES[&"guard"].duplicate()


# --- Animation -------------------------------------------------------------------

func _process(delta: float) -> void:
	if _rig == null:
		return
	_flash = maxf(0.0, _flash - delta * 5.0)
	_block_kick = maxf(0.0, _block_kick - delta * 6.0)
	_update_flash()
	if _dead:
		_animate_death(delta)
		_apply_pose(_pose)
		return
	var target := _target_pose(delta)
	_apply_pose(target)
	_animate_legs(delta)
	_animate_rig(delta, target)


func _target_pose(delta: float) -> Dictionary:
	var runner := combatant.attack_runner if combatant else null
	var target: Dictionary
	if runner and runner.is_running() and ATTACK_POSES.has(runner.attack.animation):
		if runner.attack != _tracked_attack or runner.elapsed < _tracked_elapsed:
			_tracked_attack = runner.attack
			_attack_from = _pose.duplicate()
		_tracked_elapsed = runner.elapsed
		var keys: Array = ATTACK_POSES[runner.attack.animation]
		var p := runner.phase_progress()
		match runner.phase:
			AttackRunner.Phase.STARTUP:
				target = _lerp_pose(_attack_from, keys[0], _ease_out(p))
			AttackRunner.Phase.ACTIVE:
				target = _lerp_pose(keys[0], keys[1], _ease_in_out(p))
				if keys[1].has("spin"):
					target["spin"] = keys[1]["spin"] * _ease_in_out(p)
			_:
				var settle: Dictionary = POSES[&"guard"]
				target = _lerp_pose(keys[1], settle, smoothstep(0.0, 1.0, p))
		_pose = target
		return target
	_tracked_attack = null
	_tracked_elapsed = -1.0
	var base_name := &"guard"
	if _parried_time > 0.0:
		_parried_time -= delta
		base_name = &"parried"
	elif _react_time > 0.0 and _react_power >= 3:
		base_name = &"knockdown"
	elif _react_time > 0.0 and _react_power >= 2:
		base_name = &"stagger"
	elif _guard:
		base_name = &"block"
	elif _local_velocity.length() > _max_speed * 0.8 and _max_speed > 5.0:
		base_name = &"sprint"
	var goal: Dictionary = POSES[base_name]
	_pose = _lerp_pose(_pose, goal, 1.0 - exp(-14.0 * delta))
	_pose.erase("spin")
	target = _pose.duplicate()
	if _block_kick > 0.0:
		target.sp = target.sp + Vector3(0, 0.05, 0.1) * _block_kick
		target.t = target.t + Vector3(8, 0, 0) * _block_kick
	return target


func _animate_rig(delta: float, pose: Dictionary) -> void:
	var lean := Vector3.ZERO
	var offset := Vector3.ZERO
	var crouch: float = pose.get("c", 0.0)
	if _dodge_time > 0.0:
		_dodge_time -= delta
		var k := sin(clampf(1.0 - _dodge_time / _dodge_duration, 0.0, 1.0) * PI)
		crouch += 0.28 * k
		lean.x += -_dodge_dir.z * 22.0 * k
		lean.z += -_dodge_dir.x * 22.0 * k
	if _react_time > 0.0:
		_react_time -= delta
		var k2 := clampf(_react_time / _react_duration, 0.0, 1.0)
		var dir := _react_dir.normalized() if _react_dir.length_squared() > 0.001 else Vector3(0, 0, 1)
		var amount: float = [6.0, 12.0, 20.0, 28.0][clampi(_react_power, 0, 3)]
		lean.x += dir.z * amount * k2
		lean.z += -dir.x * amount * k2
		offset += dir * 0.08 * k2
	# Lean into movement a little.
	lean.x += -_local_velocity.z / _max_speed * 5.0
	lean.z += -_local_velocity.x / _max_speed * 4.0
	var spin: float = pose.get("spin", 0.0)
	_rig.rotation = Vector3(deg_to_rad(lean.x), deg_to_rad(spin), deg_to_rad(lean.z))
	_rig.position = offset
	_hips.position.y = HIP_HEIGHT - crouch + absf(sin(_gait_phase)) * 0.03 * minf(_local_velocity.length() / _max_speed, 1.0)


func _animate_legs(delta: float) -> void:
	var speed := Vector2(_local_velocity.x, _local_velocity.z).length()
	var amount := clampf(speed / 3.5, 0.0, 1.0)
	var prev := sin(_gait_phase)
	_gait_phase = fmod(_gait_phase + delta * (4.0 + speed * 1.8) * (1.0 if amount > 0.05 else 0.0), TAU)
	if amount > 0.15 and signf(prev) != signf(sin(_gait_phase)):
		footstep.emit()
	var fwd := -_local_velocity.z / maxf(speed, 0.01)
	var side := _local_velocity.x / maxf(speed, 0.01)
	var crouch: float = _pose.get("c", 0.0)
	for i in 2:
		var s := sin(_gait_phase + PI * i)
		var swing := deg_to_rad(34.0) * amount * s
		_legs[i].rotation = Vector3(swing * fwd + deg_to_rad(crouch * 80.0), 0.0, -swing * side * 0.5 + deg_to_rad(4.0 if i == 0 else -4.0))
		var knee := deg_to_rad(crouch * 140.0) + deg_to_rad(45.0) * amount * maxf(0.0, -s)
		_knees[i].rotation.x = -knee


func _animate_death(delta: float) -> void:
	_death_t += delta
	var k := clampf(_death_t / 0.75, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 2.0)
	_rig.rotation = Vector3(deg_to_rad(84.0 * k), _rig.rotation.y, _rig.rotation.z * (1.0 - k))
	_rig.position = Vector3(0, -0.05 * k, 0.15 * k)
	_hips.position.y = lerpf(_hips.position.y, HIP_HEIGHT - 0.25 * k, 0.2)
	_pose = _lerp_pose(_pose, POSES[&"knockdown"], 1.0 - exp(-6.0 * delta))
	for i in 2:
		_knees[i].rotation.x = lerpf(_knees[i].rotation.x, deg_to_rad(-60.0), 0.1)


func _apply_pose(pose: Dictionary) -> void:
	var t: Vector3 = pose.t
	_torso.rotation = Vector3(deg_to_rad(t.x), deg_to_rad(t.y), deg_to_rad(t.z))
	_sword_pivot.position = pose.sp
	var sr: Vector3 = pose.sr
	_sword_pivot.basis = Basis.from_euler(Vector3(deg_to_rad(sr.x), deg_to_rad(sr.y), deg_to_rad(sr.z)))
	_update_arms()


func _update_arms() -> void:
	var grip_r := _sword_pivot.position
	var grip_l := _sword_pivot.transform * Vector3(0, 0, 0.14)
	_place_arm(Vector3(0.2, 0.52, 0.0), grip_r, Vector3(0.7, -1.0, 0.4), 0)
	_place_arm(Vector3(-0.2, 0.52, 0.0), grip_l, Vector3(-0.7, -1.0, 0.4), 2)


func _place_arm(shoulder: Vector3, hand: Vector3, pole: Vector3, index: int) -> void:
	var to_hand := hand - shoulder
	var d := clampf(to_hand.length(), 0.05, UPPER_ARM + FOREARM - 0.002)
	var dir := to_hand.normalized() if to_hand.length_squared() > 0.0001 else Vector3.DOWN
	var a := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + d * d) / (2.0 * d)
	var h := sqrt(maxf(UPPER_ARM * UPPER_ARM - a * a, 0.0))
	var pole_perp := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * a + pole_perp * h
	var wrist := shoulder + dir * d
	_place_segment(_arm_segments[index], shoulder, elbow)
	_place_segment(_arm_segments[index + 1], elbow, wrist)


func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var v := b - a
	var length := v.length()
	if length < 0.001:
		return
	var y := v / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


func _update_flash() -> void:
	for m in _materials:
		if _flash > 0.0:
			m.emission_enabled = true
			m.emission = Color(0.9, 0.15, 0.1)
			m.emission_energy_multiplier = _flash * 0.5
		elif m.emission_enabled:
			m.emission_enabled = false


# --- Pose math ---------------------------------------------------------------------

static func _lerp_pose(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	return {
		"sp": (a.sp as Vector3).lerp(b.sp, w),
		"sr": (a.sr as Vector3).lerp(b.sr, w),
		"t": (a.t as Vector3).lerp(b.t, w),
		"c": lerpf(a.get("c", 0.0), b.get("c", 0.0), w),
	}


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 2.0)


static func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# --- Construction ------------------------------------------------------------------

func _mat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_materials.append(m)
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 4
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_body() -> void:
	var cloth := _mat(cloth_color)
	var hakama := _mat(hakama_color)
	var skin := _mat(skin_color, 0.7)
	var accent := _mat(accent_color)
	var dark := _mat(Color(0.06, 0.05, 0.05))
	var straw := _mat(Color(0.62, 0.52, 0.32))

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position.y = HIP_HEIGHT
	_rig.add_child(_hips)

	# Legs (thigh + shin), wide hakama over the thighs.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side, 0, 0)
		_hips.add_child(leg)
		_mesh(leg, _capsule(0.085, 0.5), Vector3(0, -0.23, 0), hakama)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.46, 0)
		leg.add_child(knee)
		_mesh(knee, _capsule(0.065, 0.46), Vector3(0, -0.22, 0), hakama)
		_mesh(knee, _box(Vector3(0.1, 0.06, 0.22)), Vector3(0, -0.46, -0.05), dark)
		_legs.append(leg)
		_knees.append(knee)
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.19
	skirt.bottom_radius = 0.3
	skirt.height = 0.5
	skirt.radial_segments = 12
	_mesh(_hips, skirt, Vector3(0, -0.22, 0), hakama)

	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	_mesh(_torso, _box(Vector3(0.44, 0.5, 0.25)), Vector3(0, 0.3, 0), cloth)
	_mesh(_torso, _box(Vector3(0.46, 0.09, 0.27)), Vector3(0, 0.07, 0), accent)  # obi
	_mesh(_torso, _box(Vector3(0.5, 0.12, 0.27)), Vector3(0, 0.52, 0), cloth)  # shoulders
	_mesh(_torso, _box(Vector3(0.06, 0.28, 0.01)), Vector3(0.0, 0.38, -0.13), skin, Vector3(0, 0, 0))  # collar V
	_mesh(_torso, _capsule(0.05, 0.14), Vector3(0, 0.63, 0), skin)  # neck
	var head := SphereMesh.new()
	head.radius = 0.115
	head.height = 0.25
	_mesh(_torso, head, Vector3(0, 0.78, 0), skin)
	_mesh(_torso, _box(Vector3(0.12, 0.025, 0.02)), Vector3(0, 0.8, -0.108), dark)  # eye line (shows facing)
	match headgear:
		Headgear.KASA:
			var hat := CylinderMesh.new()
			hat.top_radius = 0.02
			hat.bottom_radius = 0.34
			hat.height = 0.15
			hat.radial_segments = 16
			_mesh(_torso, hat, Vector3(0, 0.92, 0), straw)
		Headgear.HACHIMAKI:
			var band := CylinderMesh.new()
			band.top_radius = 0.118
			band.bottom_radius = 0.118
			band.height = 0.04
			_mesh(_torso, band, Vector3(0, 0.84, 0), accent)
			_mesh(_torso, _box(Vector3(0.03, 0.12, 0.02)), Vector3(0, 0.8, 0.12), accent, Vector3(20, 0, 0))
		_:
			var hair := SphereMesh.new()
			hair.radius = 0.12
			hair.height = 0.16
			_mesh(_torso, hair, Vector3(0, 0.84, 0.02), dark)
			_mesh(_torso, _capsule(0.035, 0.13), Vector3(0, 0.93, 0.06), dark, Vector3(70, 0, 0))  # topknot
			var band2 := CylinderMesh.new()
			band2.top_radius = 0.12
			band2.bottom_radius = 0.12
			band2.height = 0.03
			_mesh(_torso, band2, Vector3(0, 0.82, 0), accent)

	# Arms are re-fitted every frame with 2-bone IK so both hands stay on the grip.
	for i in 4:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.055 if i % 2 == 0 else 0.045
		cyl.bottom_radius = 0.05 if i % 2 == 0 else 0.04
		cyl.height = 1.0
		cyl.radial_segments = 8
		_arm_segments.append(_mesh(_torso, cyl, Vector3.ZERO, cloth if i % 2 == 0 else skin))

	_sword_pivot = Node3D.new()
	_sword_pivot.name = "WeaponSocket"
	_torso.add_child(_sword_pivot)
	if katana_scene:
		_katana = katana_scene.instantiate() as Katana
		_sword_pivot.add_child(_katana)
	_apply_pose(_pose)
