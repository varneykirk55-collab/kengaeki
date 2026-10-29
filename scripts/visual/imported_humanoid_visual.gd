class_name ImportedHumanoidVisual
extends CharacterVisual
## CharacterVisual for imported rigged humanoids (Hunyuan samurai / ronin models).
##
## Usage (see docs/ASSET_INTEGRATION.md):
##  1. Import the model (.glb/.fbx) with a humanoid skeleton. Use Godot's Retarget
##     (SkeletonProfileHumanoid) in the import dialog so all animations share bone names.
##  2. Replace the "Visual" node of player.tscn / enemy.tscn with a node using this script,
##     set model_scene, and fill animation_map with the clip names of your library.
##  3. Attack clips are time-stretched to match AttackData timings, or (with
##     AttackData.timing_source = ANIMATION_EVENTS) add a method track calling
##     emit_animation_event("hit_start"/"hit_end"/"attack_end") on this node.
## NOTE: written against the Godot 4.3 API but not yet exercised with real Hunyuan assets.

@export var model_scene: PackedScene
@export var katana_scene: PackedScene = preload("res://scenes/weapons/katana.tscn")
## Bone that holds the katana grip (after humanoid retargeting this is "RightHand").
@export var weapon_bone: StringName = &"RightHand"
## Offset of the katana grip relative to the hand bone.
@export var weapon_offset: Transform3D = Transform3D.IDENTITY
## Rotation applied to the model so that it faces -Z (Godot forward).
@export var model_yaw_degrees: float = 180.0
@export var model_scale: float = 1.0
@export var blend_time: float = 0.12
## Logical animation name -> clip name in the model's AnimationPlayer.
## Attack keys match AttackData.animation (slash_rl, slash_lr, overhead, kesa, rising, thrust, spin).
@export var animation_map: Dictionary = {
	"idle": "Idle", "walk": "Walk", "run": "Run", "strafe_left": "StrafeLeft",
	"strafe_right": "StrafeRight", "walk_back": "WalkBack", "block": "Block",
	"block_impact": "BlockImpact", "dodge": "Dodge", "hit_light": "HitLight",
	"hit_heavy": "HitHeavy", "knockdown": "Knockdown", "parried": "Parried", "death": "Death",
	"slash_rl": "SlashRL", "slash_lr": "SlashLR", "overhead": "Overhead", "kesa": "Kesa",
	"rising": "Rising", "thrust": "Thrust", "spin": "Spin",
}

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var _katana: Katana
var _locked_until := 0.0  # one-shot clips block locomotion until this time
var _tracked_attack: AttackData
var _guard := false
var _dead := false
var _time := 0.0


func _ready() -> void:
	if model_scene == null:
		push_warning("ImportedHumanoidVisual: model_scene not set")
		return
	model = model_scene.instantiate() as Node3D
	model.rotation_degrees.y = model_yaw_degrees
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	anim_player = _find(model, "AnimationPlayer") as AnimationPlayer
	if skeleton and katana_scene:
		var attach := BoneAttachment3D.new()
		attach.bone_name = weapon_bone
		skeleton.add_child(attach)
		_katana = katana_scene.instantiate() as Katana
		_katana.transform = weapon_offset
		attach.add_child(_katana)
	elif katana_scene:
		push_warning("ImportedHumanoidVisual: no Skeleton3D found; katana attached to root")
		_katana = katana_scene.instantiate() as Katana
		add_child(_katana)


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found:
			return found
	return null


func get_katana() -> Katana:
	return _katana


func _play(logical: String, custom_speed: float = 1.0, restart: bool = false) -> float:
	if anim_player == null:
		return 0.0
	var clip: String = animation_map.get(logical, logical)
	if not anim_player.has_animation(clip):
		return 0.0
	if restart or anim_player.current_animation != clip:
		anim_player.play(clip, blend_time, custom_speed)
		if restart:
			anim_player.seek(0.0, true)
	return anim_player.get_animation(clip).length / maxf(custom_speed, 0.01)


func _one_shot(logical: String, speed: float = 1.0) -> void:
	var length := _play(logical, speed, true)
	_locked_until = _time + length


func _process(delta: float) -> void:
	_time += delta
	if _dead or combatant == null:
		return
	var runner := combatant.attack_runner
	if runner.is_running():
		if runner.attack != _tracked_attack:
			_tracked_attack = runner.attack
			var speed := 1.0
			if runner.attack.timing_source == AttackData.TimingSource.DATA and anim_player:
				var clip: String = animation_map.get(String(runner.attack.animation), "")
				if anim_player.has_animation(clip):
					speed = anim_player.get_animation(clip).length / maxf(runner.attack.total_time(), 0.05)
			_one_shot(String(runner.attack.animation), speed)
		return
	_tracked_attack = null


func set_locomotion(local_velocity: Vector3, max_speed: float) -> void:
	if _dead or _time < _locked_until or (combatant and combatant.attack_runner.is_running()):
		return
	if _guard:
		_play("block")
		return
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	if speed < 0.3:
		_play("idle")
	elif absf(local_velocity.x) > absf(local_velocity.z):
		_play("strafe_right" if local_velocity.x > 0.0 else "strafe_left")
	elif local_velocity.z > 0.0:
		_play("walk_back")
	else:
		_play("run" if speed > max_speed * 0.75 and max_speed > 5.0 else "walk")


func set_guard(blocking: bool) -> void:
	_guard = blocking


func play_dodge(_local_direction: Vector3, duration: float) -> void:
	var length := _clip_length("dodge")
	_one_shot("dodge", length / duration if length > 0.0 else 1.0)


func play_hit(power: int, _local_direction: Vector3) -> void:
	match power:
		3:
			_one_shot("knockdown")
		2:
			_one_shot("hit_heavy")
		_:
			_one_shot("hit_light")


func play_block_impact() -> void:
	_one_shot("block_impact")


func play_parried(duration: float) -> void:
	var length := _clip_length("parried")
	_one_shot("parried", length / duration if length > 0.0 else 1.0)


func play_death() -> void:
	_dead = true
	_play("death", 1.0, true)


func reset_pose() -> void:
	_dead = false
	_locked_until = 0.0
	_play("idle", 1.0, true)


func _clip_length(logical: String) -> float:
	if anim_player == null:
		return 0.0
	var clip: String = animation_map.get(logical, logical)
	return anim_player.get_animation(clip).length if anim_player.has_animation(clip) else 0.0
