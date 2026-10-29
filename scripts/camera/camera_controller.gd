class_name CameraController
extends Node3D
## Third-person orbit camera with lock-on framing, group framing, collision avoidance
## (SpringArm3D) and trauma-based screen shake.
##
## Hierarchy (built in camera_rig.tscn): CameraRig (this, top-level) -> Pitch -> SpringArm3D -> Camera3D

@export var target_path: NodePath
@export var mouse_sensitivity: float = 0.0025
@export var joystick_sensitivity: float = 2.6
@export var min_pitch_deg: float = -55.0
@export var max_pitch_deg: float = 35.0
@export var distance: float = 4.2
@export var min_distance: float = 2.2
@export var max_distance: float = 7.5
@export var zoom_step: float = 0.4
@export var follow_height: float = 1.55
@export var follow_smoothing: float = 14.0
@export var shoulder_offset: float = 0.35
@export var lock_yaw_speed: float = 7.0
@export var lock_pitch_deg: float = -14.0
## Extra camera distance per nearby enemy (keeps groups in frame).
@export var group_distance_per_enemy: float = 0.3
@export var max_group_distance: float = 1.8
@export var max_shake_offset: float = 0.22
@export var max_shake_roll_deg: float = 2.0

var target: Player
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var trauma := 0.0
var input_enabled := true
## Mouse look only applies while the mouse is captured (disabled by automated tests).
var require_mouse_capture := true

var _current_distance := 4.2
var _noise := FastNoiseLite.new()
var _noise_t := 0.0

@onready var pitch_pivot: Node3D = $Pitch
@onready var spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	_noise.frequency = 2.5
	_noise.seed = 1337
	if target_path:
		set_target(get_node_or_null(target_path) as Player)
	spring_arm.collision_mask = 1  # world only
	spring_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring_arm.shape = probe
	CombatFX.camera_shake_requested.connect(add_trauma)
	_current_distance = distance


func set_target(p: Player) -> void:
	target = p
	if target:
		target.camera_controller = self
		spring_arm.add_excluded_object(target.get_rid())
		snap_behind_target()


func snap_behind_target() -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3.UP * follow_height
	yaw = target.rotation.y
	pitch = deg_to_rad(-12.0)
	_apply_rotation()


## Yaw-only basis used for camera-relative movement.
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_mouse_capture):
		if not _locked():
			yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	elif event.is_action_pressed(&"camera_zoom_in"):
		distance = clampf(distance - zoom_step, min_distance, max_distance)
	elif event.is_action_pressed(&"camera_zoom_out"):
		distance = clampf(distance + zoom_step, min_distance, max_distance)


func _locked() -> bool:
	return target != null and target.lock_target != null and is_instance_valid(target.lock_target)


func _process(delta: float) -> void:
	if target == null:
		return
	# Gamepad look.
	if input_enabled:
		var look := Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
		if not _locked():
			yaw -= look.x * joystick_sensitivity * delta
		pitch = clampf(pitch - look.y * joystick_sensitivity * delta * 0.7, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	var focus := target.global_position + Vector3.UP * follow_height
	var extra_distance := 0.0
	if _locked():
		var lock_pos := target.lock_target.global_position
		var to := lock_pos - target.global_position
		to.y = 0.0
		if to.length() > 0.3:
			var desired_yaw := atan2(-to.x, -to.z)
			yaw = lerp_angle(yaw, desired_yaw, 1.0 - exp(-lock_yaw_speed * delta))
		# Frame both fighters: shift the focus toward the target and pull back with distance.
		focus += to.limit_length(2.0) * 0.3
		extra_distance += clampf(to.length() - 3.0, 0.0, 4.0) * 0.25
		pitch = lerpf(pitch, deg_to_rad(lock_pitch_deg), 1.0 - exp(-2.0 * delta))
	var nearby := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not e.is_dead() and e.global_position.distance_to(target.global_position) < 9.0:
			nearby += 1
	extra_distance += minf(maxi(nearby - 1, 0) * group_distance_per_enemy, max_group_distance)

	global_position = global_position.lerp(focus, 1.0 - exp(-follow_smoothing * delta))
	_current_distance = lerpf(_current_distance, distance + extra_distance, 1.0 - exp(-4.0 * delta))
	spring_arm.spring_length = _current_distance
	_apply_rotation()

	# Trauma-based shake (offsets the projection only, so collision is unaffected).
	trauma = maxf(0.0, trauma - delta * 1.6)
	_noise_t += delta * 60.0
	var shake := trauma * trauma
	camera.h_offset = shoulder_offset + _noise.get_noise_2d(_noise_t, 0.0) * max_shake_offset * shake
	camera.v_offset = _noise.get_noise_2d(0.0, _noise_t) * max_shake_offset * shake
	camera.rotation.z = deg_to_rad(_noise.get_noise_2d(_noise_t, _noise_t) * max_shake_roll_deg * shake)


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	pitch_pivot.rotation = Vector3(pitch, 0.0, 0.0)
