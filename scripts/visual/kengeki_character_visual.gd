class_name KengekiCharacterVisual
extends CharacterVisual
## CharacterVisual for the AccuRIG Kengeki samurai (assets/models/kengeki/*.glb).
##
## The GLB holds one skeleton and seven Mixamo-retargeted clips (see
## Kengeki/assets/animation_pipeline_output/ANIMATION_REPORT.md). They are driven by an
## AnimationTree built in code:
##
##   locomotion (Idle/Walk/Run, cross-faded) ──┐
##   action slots A/B (attacks, jump, guard,   ├─ full-body Blend2 ── upper-body Blend2 ── output
##     dodge; time set every frame by gameplay)┘                     (Draw / Sheathe, filtered)
##
## Root motion: every clip carries its ground travel on RL_BoneRoot. That track is set as the
## tree's root_motion_track and the extracted motion is ignored, so all clips play in place
## and only the existing controller moves the CharacterBody3D (no double movement, no snap
## back when a clip loops or ends). Attack lunges stay code-driven in Player._update_attack.
##
## Attack timing: each AttackData animation key maps to a combat clip and one swing segment
## [start, hit_start, hit_end, end] (clip seconds). The clip time is derived from the
## AttackRunner phase every frame, so the clip's contact frames always play inside the real
## hit window. The katana combat clips come from the KinemIQ library
## (assets/animations/kinemiq/, see docs/COMBAT_ANIMATIONS.md); if it is missing, the original
## Sword_Combo_OneHand segments are used.

const RIG := "Kengeki_Rig/Skeleton3D"
const CLIP_IDLE := &"Idle_Unarmed"
const CLIP_WALK := &"Walk"
const CLIP_RUN := &"Run"
const CLIP_JUMP := &"Jump"
const CLIP_DRAW := &"Sword_Draw"
const CLIP_SHEATHE := &"Sword_Sheathe"
const CLIP_COMBO := &"Sword_Combo_OneHand"

## Ground speed (m/s at model scale 1) of the in-place clips, measured from their root motion.
const WALK_CLIP_SPEED := 1.154
const RUN_CLIP_SPEED := 4.153

## Swing segments of Sword_Combo_OneHand, from the right-hand speed profile of the clip:
## A = right-to-left cut (peak 0.50 s), B = left-to-right return cut (peak 1.00 s),
## C = high right-to-left finishing cut (peak 1.50 s), then back to guard by 2.08 s.
## Segment A starts from the half-raised blade (0.25 s): the full 0.46 s wind-up squeezed
## into a 0.14 s light startup would move faster than the cut itself.
const SEG_A := [0.25, 0.458, 0.625, 0.708]
const SEG_B := [0.708, 0.958, 1.125, 1.208]
const SEG_C := [1.208, 1.458, 1.583, 2.083]
const ATTACK_SEGMENTS := {
	&"slash_rl": SEG_A, &"thrust": SEG_A,
	&"slash_lr": SEG_B, &"rising": SEG_B,
	&"spin": SEG_C, &"overhead": SEG_C, &"kesa": SEG_C,
}
## First frame of the combo clip is a two-handed guard stance; used as the block pose.
const GUARD_TIME := 0.0

## KinemIQ katana combat clips (30 fps, built onto this rig by tools/build_combat_animations.gd).
const COMBAT_LIBRARY_PATH := "res://assets/animations/kinemiq/kinemiq_combat.res"
const KQ_SLASH_A := &"kinemiq/Light_Slash_A"
const KQ_COMBO := &"kinemiq/Light_Combo"
const KQ_HEAVY_B := &"kinemiq/Heavy_Slash_B"
const KQ_HEAVY_C := &"kinemiq/Heavy_Slash_C"
const KQ_BLOCK := &"kinemiq/Block"
## Contact frames, from the blade-tip and right-hand speed of each clip (docs/COMBAT_ANIMATIONS.md).
## Light_Slash_A: diagonal right-high to left-low cut, tip fastest 0.20-0.30 s.
## Light_Combo: cut 2 horizontal left-to-right (0.57-0.70 s), cut 3 rising left-to-right
## (1.27-1.40 s), cut 4 lunging right-to-left (1.97-2.07 s). Its cut 1 is Light_Slash_A.
## Heavy_Slash_B: rising left-low to right-high (0.33-0.47 s).
## Heavy_Slash_C: deep lunging horizontal cut, left to right (0.47-0.60 s).
const KQ_ATTACKS := {
	&"slash_rl": [KQ_SLASH_A, [0.0, 0.183, 0.317, 0.367]],
	&"kesa": [KQ_SLASH_A, [0.0, 0.183, 0.317, 0.367]],
	&"slash_lr": [KQ_COMBO, [0.367, 0.567, 0.7, 0.8]],
	&"spin": [KQ_COMBO, [0.85, 1.2, 1.4, 1.633]],
	&"thrust": [KQ_COMBO, [1.8, 1.967, 2.067, 2.3]],
	&"rising": [KQ_HEAVY_B, [0.0, 0.333, 0.467, 0.5]],
	&"overhead": [KQ_HEAVY_C, [0.267, 0.433, 0.6, 0.7]],
}
## Block clip: frame 0 is the ready stance; the guard is up by 0.17 s and held until 0.6 s.
const KQ_BLOCK_RAISE := 0.167
const KQ_BLOCK_HOLD := 0.3
## The combat ready stance (sword drawn, standing still) is the shared first frame of the
## combo, slash and block clips; holding it makes every attack start from its own first pose.
const KQ_READY_TIME := 0.0

## Sword_Draw: the right hand closes on the hilt at 0.50 s and the blade is out by 0.92 s.
## Sword_Sheathe: the blade is home and the hand lets go at 0.83 s; settled by 1.08 s.
const DRAW_GRAB_TIME := 0.5
const DRAW_READY_TIME := 0.917
const SHEATHE_RELEASE_TIME := 0.833
## Clip time over which the drawn blade eases to / from its sheathed pose at the hand-over.
const DRAW_EASE_TIME := 0.4
const SHEATHE_EASE_TIME := 0.25
const SHEATHE_DONE_TIME := 1.083

## Jump clip: take-off 0.75 s, touch-down 1.40 s, settled 2.17 s. The clip itself lifts the
## feet off the ground; physics already lifts the body, so the lift is subtracted from the
## model while airborne. Table: lowest-foot height above the standing height, every 1/24 s
## from JUMP_AIR_START (model units, measured from the GLB).
const JUMP_AIR_START := 0.667
const JUMP_LAND_TIME := 1.396
const JUMP_SETTLED_TIME := 2.167
const JUMP_FOOT_LIFT := [
	0.0, 0.001, 0.015, 0.052, 0.102, 0.165, 0.249, 0.349, 0.43, 0.498, 0.53, 0.512,
	0.451, 0.362, 0.271, 0.185, 0.099, 0.023, 0.0,
]

## Loaded at runtime: the GLB is a private asset kept out of git (see docs/CHARACTER_INTEGRATION.md).
@export_file("*.glb", "*.tscn") var model_path: String = "res://assets/models/kengeki/kengeki_character_animated.glb"
@export var katana_scene: PackedScene = preload("res://scenes/weapons/katana.tscn")
## Scales the 1.15 m tall GLB to the 1.8 m gameplay capsule (hips at ~0.91 m).
@export var model_scale: float = 1.55
## The GLB faces +Z; gameplay forward is -Z.
@export var model_yaw_degrees: float = 180.0
@export var hand_bone: StringName = &"CC_Base_R_Hand"
@export var hip_bone: StringName = &"CC_Base_Hip"
## The grip is computed from the hand's finger and thumb bones (see _grip_transform).
## hand_grip_offset is only used if those bones are missing.
@export var hand_grip_offset: Vector3 = Vector3(-0.015, 0.045, 0.0)
## How far into the palm the grip sits (model units).
@export var grip_palm_depth: float = 0.018
## Sheathed katana, in model space (model units): hilt in front of the left hip, blade back
## and down through the sash.
@export var sheath_grip_position: Vector3 = Vector3(0.09, 0.64, 0.13)
@export var sheath_blade_direction: Vector3 = Vector3(0.28, -0.38, -1.0)
## Worn katana-style: cutting edge up, back of the blade (and the saya's curve) down.
@export var sheath_edge_up: bool = true
## Blade clearance: while the katana is in the hand, the grip is turned about the palm just
## enough to keep the blade outside the torso and right thigh (capsules around the bones,
## world metres). Purely visual: hit detection uses the arc sweep, not the blade.
@export var blade_clearance: bool = true
@export var blade_clearance_margin: float = 0.02
@export var blade_max_deflect_degrees: float = 50.0
const BLADE_BODY_CAPSULES := [
	[&"CC_Base_Waist", &"CC_Base_NeckTwist01", 0.13],
	[&"CC_Base_R_Thigh", &"CC_Base_R_Calf", 0.08],
]
@export var start_drawn: bool = true
@export var equip_speed: float = 1.25
## Walk is a slow catwalk (1.8 m/s at this scale); gameplay walks at 4.6 m/s. The cadence is
## capped so it does not look frantic; the remaining difference shows as slight foot slide.
@export var max_walk_time_scale: float = 2.2
@export var locomotion_xfade: float = 0.18
@export var action_xfade: float = 0.08
@export var action_fade_in: float = 0.08
@export var action_fade_out: float = 0.18
## Fade time of the combat ready stance when the player stops / starts moving.
@export var ready_fade: float = 0.2

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var sword_drawn := true

var _pose_root: Node3D
var _katana: Katana
var _hand_attach: BoneAttachment3D
var _hip_attach: BoneAttachment3D
var _hand_xform: Transform3D
var _hand_bone_idx := -1
var _capsule_bones: Array = []  # [[bone a, bone b, radius], ...] as indices
var _deflect := Vector3.ZERO  # smoothed grip turn (rotation vector, hand-bone space)
var _hip_xform: Transform3D

var _speed := 0.0
var _max_speed := 4.6
var _loco_state := &"idle"
var _loco_phase := 0.0
var _guard := false
var _dead := false

var _action_weight := 0.0
var _action_slot := 0  # 0 = slot "a", 1 = slot "b"
var _action_key := ""
var _attack_ref: AttackData
var _has_combat_clips := false
var _guard_t := 0.0
var _ready_weight := 0.0
var _fade_in := 0.08

var _dodge_left := 0.0
var _dodge_time := 0.0
var _dodge_rate := 1.0

enum Jump { NONE, AIR, LAND }
var _jump := Jump.NONE
var _jump_air_time := 0.0
var _jump_expected_air := 0.55
var _jump_clip_t := 0.0

var _equip_active := false
var _equip_drawing := true
var _equip_t := 0.0
var _equip_swapped := false
var _upper_weight := 0.0

var _tilt := 0.0        # degrees, positive leans the body backwards (hit reactions, death)
var _flinch_t := -1.0
var _flinch_amp := 0.0
var _flinch_len := 0.25
var _knockdown_t := -1.0


func _ready() -> void:
	_pose_root = Node3D.new()
	_pose_root.name = "PoseRoot"
	add_child(_pose_root)
	var model_scene: PackedScene = load(model_path) if ResourceLoader.exists(model_path) else null
	if model_scene == null:
		push_error("KengekiCharacterVisual: character model missing at %s. Copy kengeki_character_animated.glb there (see docs/CHARACTER_INTEGRATION.md)." % model_path)
		_build_katana()
		return
	model = model_scene.instantiate() as Node3D
	model.rotation_degrees.y = model_yaw_degrees
	model.scale = Vector3.ONE * model_scale
	_pose_root.add_child(model)
	skeleton = model.get_node_or_null(RIG) as Skeleton3D
	anim_player = model.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN]:
		if anim_player and anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_load_combat_clips()
	_build_tree()
	_build_katana()
	sword_drawn = start_drawn
	set_sword_drawn(start_drawn)
	if skeleton:
		_hand_bone_idx = skeleton.find_bone(hand_bone)
		for c in BLADE_BODY_CAPSULES:
			var a := skeleton.find_bone(c[0])
			var b := skeleton.find_bone(c[1])
			if a >= 0 and b >= 0:
				_capsule_bones.append([a, b, c[2]])
		skeleton.skeleton_updated.connect(_update_blade_clearance)


# --- Construction --------------------------------------------------------------------

func _load_combat_clips() -> void:
	if anim_player == null or not ResourceLoader.exists(COMBAT_LIBRARY_PATH):
		push_warning("KengekiCharacterVisual: combat clips missing at %s; using Sword_Combo_OneHand." % COMBAT_LIBRARY_PATH)
		return
	var lib := load(COMBAT_LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		return
	if not anim_player.has_animation_library(&"kinemiq"):
		anim_player.add_animation_library(&"kinemiq", lib)
	_has_combat_clips = true
	for clip in [KQ_SLASH_A, KQ_COMBO, KQ_HEAVY_B, KQ_HEAVY_C, KQ_BLOCK]:
		_has_combat_clips = _has_combat_clips and anim_player.has_animation(clip)


## Clip and [start, hit_start, hit_end, end] segment for an AttackData animation key.
func attack_clip(key: StringName) -> Array:
	if _has_combat_clips:
		return KQ_ATTACKS.get(key, KQ_ATTACKS[&"slash_rl"])
	return [CLIP_COMBO, ATTACK_SEGMENTS.get(key, SEG_A)]


## Clip playing in the live action slot ("" while only locomotion plays).
func current_action_clip() -> StringName:
	if _action_key == "" or anim_tree == null or _action_weight < 0.05:
		return &""
	var node := anim_tree.tree_root.get_node(&"act_a" if _action_slot == 0 else &"act_b") as AnimationNodeAnimation
	return node.animation


func _build_tree() -> void:
	if anim_player == null:
		return
	var bt := AnimationNodeBlendTree.new()
	# Locomotion: Idle / Walk / Run cross-faded by a Transition, Walk and Run speed-matched.
	bt.add_node(&"idle", _anim_node(CLIP_IDLE))
	bt.add_node(&"walk", _anim_node(CLIP_WALK))
	bt.add_node(&"run", _anim_node(CLIP_RUN))
	bt.add_node(&"walk_speed", AnimationNodeTimeScale.new())
	bt.add_node(&"run_speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"walk_speed", 0, &"walk")
	bt.connect_node(&"run_speed", 0, &"run")
	var loco := AnimationNodeTransition.new()
	loco.xfade_time = locomotion_xfade
	loco.input_count = 3
	for i in 3:
		loco.set_input_name(i, ["idle", "walk", "run"][i])
	bt.add_node(&"loco", loco)
	bt.connect_node(&"loco", 0, &"idle")
	bt.connect_node(&"loco", 1, &"walk_speed")
	bt.connect_node(&"loco", 2, &"run_speed")
	# Two seekable action slots so one action can cross-fade into the next.
	var act := AnimationNodeTransition.new()
	act.xfade_time = action_xfade
	act.input_count = 2
	act.set_input_name(0, "a")
	act.set_input_name(1, "b")
	bt.add_node(&"act", act)
	for slot in ["a", "b"]:
		_add_seekable(bt, "act_" + slot, CLIP_COMBO)
		bt.connect_node(&"act", 0 if slot == "a" else 1, StringName("act_%s_seek" % slot))
	# Combat ready stance over idle while the katana is drawn.
	_add_seekable(bt, "ready", KQ_COMBO if _has_combat_clips else CLIP_COMBO)
	bt.add_node(&"ready_blend", AnimationNodeBlend2.new())
	bt.connect_node(&"ready_blend", 0, &"loco")
	bt.connect_node(&"ready_blend", 1, &"ready_seek")
	var full := AnimationNodeBlend2.new()
	bt.add_node(&"full", full)
	bt.connect_node(&"full", 0, &"ready_blend")
	bt.connect_node(&"full", 1, &"act")
	# Upper-body layer (draw / sheathe while the legs keep walking).
	_add_seekable(bt, "upper", CLIP_DRAW)
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	if skeleton:
		for i in skeleton.get_bone_count():
			var bone := skeleton.get_bone_name(i)
			if not _is_lower_body(bone):
				upper.set_filter_path(NodePath("%s:%s" % [RIG, bone]), true)
	bt.add_node(&"upper_blend", upper)
	bt.connect_node(&"upper_blend", 0, &"full")
	bt.connect_node(&"upper_blend", 1, &"upper_seek")
	bt.connect_node(&"output", 0, &"upper_blend")

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	model.add_child(anim_tree)
	anim_tree.root_node = NodePath("..")
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = bt
	anim_tree.root_motion_track = NodePath("%s:RL_BoneRoot" % RIG)
	anim_tree.active = true
	anim_tree.set("parameters/loco/transition_request", "idle")
	anim_tree.set("parameters/full/blend_amount", 0.0)
	anim_tree.set("parameters/upper_blend/blend_amount", 0.0)
	anim_tree.set("parameters/ready_blend/blend_amount", 0.0)
	for n in ["act_a", "act_b", "upper", "ready"]:
		anim_tree.set("parameters/%s_freeze/scale" % n, 0.0)
	anim_tree.set("parameters/ready_seek/seek_request", KQ_READY_TIME if _has_combat_clips else GUARD_TIME)


func _anim_node(clip: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


## Animation -> TimeScale(0) -> TimeSeek: the clip only moves when we seek it, so gameplay
## owns its timeline exactly.
func _add_seekable(bt: AnimationNodeBlendTree, prefix: String, clip: StringName) -> void:
	bt.add_node(StringName(prefix), _anim_node(clip))
	bt.add_node(StringName(prefix + "_freeze"), AnimationNodeTimeScale.new())
	bt.add_node(StringName(prefix + "_seek"), AnimationNodeTimeSeek.new())
	bt.connect_node(StringName(prefix + "_freeze"), 0, StringName(prefix))
	bt.connect_node(StringName(prefix + "_seek"), 0, StringName(prefix + "_freeze"))


static func _is_lower_body(bone: String) -> bool:
	for key in ["RL_BoneRoot", "_Hip", "Pelvis", "Thigh", "Calf", "Knee", "Foot", "Toe"]:
		if bone.contains(key):
			return true
	return false


func _build_katana() -> void:
	if katana_scene == null:
		return
	_katana = katana_scene.instantiate() as Katana
	if skeleton == null:
		add_child(_katana)
		return
	var inv_scale := 1.0 / model_scale
	_hand_xform = _grip_transform(inv_scale)
	# Hip: build the sheathed pose in model space, then express it relative to the hip bone.
	var blade := sheath_blade_direction.normalized()
	var z := -blade
	var y := (Vector3.UP - z * Vector3.UP.dot(z)).normalized()
	if sheath_edge_up:
		y = -y
	var x := y.cross(z)
	var sheath_model := Transform3D(Basis(x, y, z).scaled(Vector3.ONE * inv_scale), sheath_grip_position)
	var hip_rest := skeleton.get_bone_global_rest(skeleton.find_bone(hip_bone))
	_hip_xform = hip_rest.affine_inverse() * sheath_model
	_hand_attach = _attachment(hand_bone)
	_hip_attach = _attachment(hip_bone)
	# The saya stays on the hip, exactly where the sheathed blade sits inside it.
	var saya: Node3D = null
	if not _katana.scabbard_path.is_empty():
		saya = _katana.get_node_or_null(_katana.scabbard_path) as Node3D
	if saya:
		var saya_local := _relative_to(saya, _katana)
		saya.owner = null  # leaves the GLB instance
		saya.get_parent().remove_child(saya)
		saya.name = "KatanaSaya"
		_hip_attach.add_child(saya)
		saya.transform = _hip_xform * saya_local


## Katana grip in hand-bone space, derived from the hand's anatomy in the rest pose rather
## than from bone-axis conventions. A closed fist holds the handle along the knuckle line,
## so the blade runs from the little-finger knuckle towards the index knuckle (leaving the
## fist on the thumb side), its back faces the wrist (edge towards the knuckles), and the
## grip sits in the palm halfway along the hand.
func _grip_transform(inv_scale: float) -> Transform3D:
	var hand := skeleton.find_bone(hand_bone)
	var side := "R" if String(hand_bone).contains("_R_") else "L"
	var mid := skeleton.find_bone("CC_Base_%s_Mid1" % side)
	var index := skeleton.find_bone("CC_Base_%s_Index1" % side)
	var pinky := skeleton.find_bone("CC_Base_%s_Pinky1" % side)
	if hand < 0 or mid < 0 or index < 0 or pinky < 0:
		return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * inv_scale), hand_grip_offset)
	var to_local := skeleton.get_bone_global_rest(hand).affine_inverse()
	var knuckle := to_local * skeleton.get_bone_global_rest(mid).origin
	var across := to_local * skeleton.get_bone_global_rest(index).origin - to_local * skeleton.get_bone_global_rest(pinky).origin
	var fingers := knuckle.normalized()
	var blade := (across - fingers * across.dot(fingers)).normalized()
	var palm := blade.cross(fingers) if side == "R" else fingers.cross(blade)
	var z := -blade
	var y := -fingers  # sori / back of the blade towards the wrist
	var x := y.cross(z)
	var origin := knuckle * 0.55 + palm * grip_palm_depth
	return Transform3D(Basis(x, y, z).orthonormalized().scaled(Vector3.ONE * inv_scale), origin)


static func _relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _attachment(bone: StringName) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = "Attach_" + String(bone)
	a.bone_name = bone
	skeleton.add_child(a)
	return a


# --- CharacterVisual interface ---------------------------------------------------------

func get_katana() -> Katana:
	return _katana


func set_locomotion(local_velocity: Vector3, max_speed: float) -> void:
	_speed = Vector2(local_velocity.x, local_velocity.z).length()
	_max_speed = max_speed


func set_guard(blocking: bool) -> void:
	_guard = blocking


func play_dodge(_local_direction: Vector3, duration: float) -> void:
	_cancel_equip()
	_end_jump()
	_dodge_left = duration
	_dodge_time = 0.0
	var run_len := _clip_length(CLIP_RUN)
	_dodge_rate = 1.7 if run_len <= 0.0 else clampf(run_len * 1.2 / maxf(duration, 0.05), 1.0, 2.5)


func play_hit(power: int, _local_direction: Vector3) -> void:
	if power >= 3:
		_knockdown_t = 0.0
		return
	_flinch_t = 0.0
	_flinch_amp = [4.0, 9.0, 16.0][clampi(power, 0, 2)]
	_flinch_len = [0.18, 0.26, 0.4][clampi(power, 0, 2)]


func play_block_impact() -> void:
	_flinch_t = 0.0
	_flinch_amp = 5.0
	_flinch_len = 0.2


func play_parried(duration: float) -> void:
	_flinch_t = 0.0
	_flinch_amp = 14.0
	_flinch_len = maxf(duration, 0.3)


func play_death() -> void:
	_dead = true
	_cancel_equip()
	_end_jump()


func reset_pose() -> void:
	_dead = false
	_tilt = 0.0
	_flinch_t = -1.0
	_knockdown_t = -1.0
	_end_jump()
	_dodge_left = 0.0
	_cancel_equip()
	_action_weight = 0.0
	_action_key = ""
	_attack_ref = null
	_guard_t = 0.0
	_pose_root.rotation = Vector3.ZERO
	if model:
		model.position = Vector3.ZERO


func play_sword_equip(drawn: bool) -> float:
	if anim_tree == null:
		set_sword_drawn(drawn)
		return 0.0
	_equip_active = true
	_equip_drawing = drawn
	_equip_t = 0.0
	_equip_swapped = false
	anim_tree.tree_root.get_node(&"upper").animation = CLIP_DRAW if drawn else CLIP_SHEATHE
	return (DRAW_READY_TIME if drawn else SHEATHE_DONE_TIME) / equip_speed


## Runs after every skeleton pose update: turns the drawn katana about the grip so no blade
## point sits inside the body capsules (torso, right thigh). Solved fresh every pose update,
## so there is no lag; near the draw grab / sheathe release it blends toward the saya pose.
func _update_blade_clearance() -> void:
	if _katana == null or _hand_attach == null or _katana.get_parent() != _hand_attach:
		return
	if not blade_clearance or _hand_bone_idx < 0 or _katana.blade_base == null or _katana.blade_tip == null:
		_katana.transform = _hand_xform
		return
	var hand_g := skeleton.global_transform * skeleton.get_bone_global_pose(_hand_bone_idx)
	var hand_rot := hand_g.basis.orthonormalized()
	var base_g := hand_g * _hand_xform
	var pivot := base_g.origin
	var p0 := base_g * _katana.blade_base.position
	var p1 := base_g * _katana.blade_tip.position
	var caps: Array = []
	for c in _capsule_bones:
		caps.append([skeleton.global_transform * skeleton.get_bone_global_pose(c[0]).origin,
			skeleton.global_transform * skeleton.get_bone_global_pose(c[1]).origin, c[2] + blade_clearance_margin])
	# A few linearised push-out steps from the uncorrected grip.
	var rot := Basis.IDENTITY
	for _iter in 24:
		var push := Vector3.ZERO
		for c in caps:
			var worst := 0.0
			var worst_rv := Vector3.ZERO
			for i in 9:
				var p := pivot + rot * (p0.lerp(p1, i / 8.0) - pivot)
				var ab: Vector3 = c[1] - c[0]
				var q: Vector3 = c[0] + ab * clampf((p - c[0]).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var pen: float = c[2] - p.distance_to(q)
				var arm := p - pivot
				if pen > worst and arm.length() > 0.05:
					var n := (p - q).normalized()
					var axis := arm.cross(n)
					if axis.length() > 0.0001:
						worst = pen
						worst_rv = axis.normalized() * (pen / arm.length())
			push += worst_rv
		if push.length() < 0.0005:
			break
		# Half steps: when the blade is wedged between two capsules the opposing pushes
		# cancel and the remainder walks it out sideways instead of bouncing.
		rot = Basis(push.normalized(), push.length() * 0.5) * rot
	var target := hand_rot.inverse() * rot.get_rotation_quaternion().get_axis() * rot.get_rotation_quaternion().get_angle()
	var cap := deg_to_rad(blade_max_deflect_degrees)
	if target.length() > cap:
		target = target.normalized() * cap
	# The push-out is zero at first contact and grows with the overlap, so it is already
	# continuous frame to frame; no extra smoothing (which would lag behind the body).
	_deflect = target
	var new_g := base_g
	if _deflect.length() > 0.0001:
		var turn := Basis(hand_rot * _deflect.normalized(), _deflect.length())
		new_g = Transform3D(turn, pivot - turn * pivot) * base_g
	# Draw / sheathe: within 0.4 s / 0.25 s (clip time) of the grab / release the blade eases from /
	# into its sheathed pose on the hip, so it slides along the saya instead of cutting
	# through the waist and popping into place at the hand-over.
	if _equip_active and _hip_attach:
		var gap := (_equip_t - DRAW_GRAB_TIME) if _equip_drawing else (SHEATHE_RELEASE_TIME - _equip_t)
		var w := 1.0 - clampf(gap / (DRAW_EASE_TIME if _equip_drawing else SHEATHE_EASE_TIME), 0.0, 1.0)
		if w > 0.0:
			var hip_g := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(hip_bone)) * _hip_xform
			new_g = new_g.interpolate_with(hip_g, smoothstep(0.0, 1.0, w))
	_katana.transform = hand_g.affine_inverse() * new_g


func set_sword_drawn(drawn: bool) -> void:
	sword_drawn = drawn
	if _katana == null or _hand_attach == null:
		return
	var target := _hand_attach if drawn else _hip_attach
	if _katana.get_parent() != target:
		if _katana.get_parent():
			_katana.get_parent().remove_child(_katana)
		target.add_child(_katana)
	_katana.transform = _hand_xform if drawn else _hip_xform


func play_jump(expected_air_time: float) -> void:
	_cancel_equip()
	_jump = Jump.AIR
	_jump_air_time = 0.0
	_jump_expected_air = maxf(expected_air_time, 0.2)
	_jump_clip_t = JUMP_AIR_START


func play_land() -> void:
	if _jump == Jump.AIR:
		_jump = Jump.LAND
		_jump_clip_t = maxf(_jump_clip_t, JUMP_LAND_TIME)


# --- Per-frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if anim_tree == null or combatant == null:
		return
	_update_equip(delta)
	var action := _current_action(delta)
	var target_weight := 1.0 if action != "" else 0.0
	var rate := _fade_in if target_weight > _action_weight else action_fade_out
	_action_weight = move_toward(_action_weight, target_weight, delta / maxf(rate, 0.001))
	anim_tree.set("parameters/full/blend_amount", _action_weight)
	_update_ready(delta)
	_update_locomotion(delta)
	_update_tilt(delta)


## Picks this frame's full-body action, positions its clip and returns its key ("" = none).
func _current_action(delta: float) -> String:
	if _dead:
		return _action_key  # freeze whatever was playing; the body falls procedurally
	var runner := combatant.attack_runner
	if runner and runner.is_running():
		var mapped := attack_clip(runner.attack.animation)
		var seg: Array = mapped[1]
		if runner.attack != _attack_ref:
			_attack_ref = runner.attack
			_cancel_equip()
			_end_jump()
			_dodge_left = 0.0
			# The heavy clips start from a low stance: blend into it over half the startup
			# (at most 0.15 s) instead of popping there in 0.08 s.
			_fade_in = clampf(runner.attack.startup * 0.5, action_fade_in, 0.15) if mapped[0] in [KQ_HEAVY_B, KQ_HEAVY_C] else action_fade_in
			_switch_action("attack_%d" % runner.attack.get_instance_id(), mapped[0])
		var p := runner.phase_progress()
		var t: float = seg[0]
		match runner.phase:
			AttackRunner.Phase.STARTUP:
				t = lerpf(seg[0], seg[1], p)
			AttackRunner.Phase.ACTIVE:
				t = lerpf(seg[1], seg[2], p)
			AttackRunner.Phase.RECOVERY:
				t = lerpf(seg[2], seg[3], p)
		_seek_action(t)
		return _action_key
	_attack_ref = null
	_fade_in = action_fade_in
	if _dodge_left > 0.0:
		_dodge_left -= delta
		_dodge_time += delta * _dodge_rate
		_switch_action("dodge", CLIP_RUN)
		_seek_action(fmod(_dodge_time, maxf(_clip_length(CLIP_RUN), 0.01)))
		return _action_key
	if _jump != Jump.NONE:
		return _update_jump(delta)
	if _guard:
		if _action_key != "guard":
			_guard_t = 0.0
		if _has_combat_clips:
			# Raise the guard in real time, then hold it.
			_guard_t += delta
			_switch_action("guard", KQ_BLOCK)
			_seek_action(minf(_guard_t, KQ_BLOCK_RAISE) / KQ_BLOCK_RAISE * KQ_BLOCK_HOLD)
		else:
			_switch_action("guard", CLIP_COMBO)
			_seek_action(GUARD_TIME)
		return _action_key
	return ""


## The ready stance replaces the unarmed idle while the katana is drawn and the player stands.
func _update_ready(delta: float) -> void:
	var target := 0.0
	# Also held under attacks and the guard (which lunge / step the body), so the action
	# always blends against the same stance instead of a three-way mix with the idle clip.
	var under_action := _action_key == "guard" or _attack_ref != null
	if _has_combat_clips and sword_drawn and not _equip_active and not _dead \
			and (_speed < 0.3 or under_action) and _jump == Jump.NONE and _dodge_left <= 0.0:
		target = 1.0
	_ready_weight = move_toward(_ready_weight, target, delta / maxf(ready_fade, 0.001))
	anim_tree.set("parameters/ready_blend/blend_amount", _ready_weight)


func _update_jump(delta: float) -> String:
	if _jump == Jump.AIR:
		_jump_air_time += delta
		var p := clampf(_jump_air_time / _jump_expected_air, 0.0, 0.97)
		_jump_clip_t = lerpf(JUMP_AIR_START, JUMP_LAND_TIME, p)
	else:
		# Landing recovery; cut short as soon as the player moves.
		var rate := 1.3 if _speed < 0.5 else 3.0
		_jump_clip_t += delta * rate
		if _jump_clip_t >= JUMP_SETTLED_TIME or (_speed > 0.5 and _jump_clip_t > JUMP_LAND_TIME + 0.25):
			_end_jump()
			model.position.y = 0.0
			return ""
	_switch_action("jump", CLIP_JUMP)
	_seek_action(_jump_clip_t)
	model.position.y = -_foot_lift(_jump_clip_t) * model_scale if _jump == Jump.AIR else 0.0
	return _action_key


func _end_jump() -> void:
	_jump = Jump.NONE
	if model:
		model.position.y = 0.0


func _foot_lift(t: float) -> float:
	var f := (t - JUMP_AIR_START) * 24.0
	if f <= 0.0 or f >= JUMP_FOOT_LIFT.size() - 1:
		return 0.0
	var i := int(f)
	return lerpf(JUMP_FOOT_LIFT[i], JUMP_FOOT_LIFT[i + 1], f - i)


func _switch_action(key: String, clip: StringName) -> void:
	if key == _action_key:
		return
	_action_key = key
	_action_slot = 1 - _action_slot
	var slot := "a" if _action_slot == 0 else "b"
	anim_tree.tree_root.get_node(StringName("act_" + slot)).animation = clip
	# Cross-fade only between two live actions. Starting from locomotion, the other slot
	# still holds the last action's frozen pose; fading from it would make the body pop, so
	# switch instantly and let the locomotion -> action Blend2 fade do the smoothing.
	var act := anim_tree.tree_root.get_node(&"act") as AnimationNodeTransition
	act.xfade_time = maxf(action_xfade, _fade_in) if _action_weight > 0.05 else 0.0
	anim_tree.set("parameters/act/transition_request", slot)


func _seek_action(t: float) -> void:
	var slot := "a" if _action_slot == 0 else "b"
	anim_tree.set("parameters/act_%s_seek/seek_request" % slot, maxf(t, 0.0))


func _update_locomotion(delta: float) -> void:
	var state := &"idle"
	var walk_ts := clampf(_speed / (WALK_CLIP_SPEED * model_scale), 0.6, max_walk_time_scale)
	var run_ts := clampf(_speed / (RUN_CLIP_SPEED * model_scale), 0.7, 1.6)
	if _speed > 0.3:
		state = &"run" if _speed > 5.4 else &"walk"
	if state != _loco_state:
		_loco_state = state
		anim_tree.set("parameters/loco/transition_request", String(state))
	anim_tree.set("parameters/walk_speed/scale", walk_ts)
	anim_tree.set("parameters/run_speed/scale", run_ts)
	# Footsteps twice per cycle while the locomotion layer is visible.
	if state == &"idle" or _action_weight > 0.5 or _dead:
		return
	var cycle := _clip_length(CLIP_RUN if state == &"run" else CLIP_WALK)
	var ts := run_ts if state == &"run" else walk_ts
	if cycle <= 0.0:
		return
	var before := _loco_phase
	_loco_phase = fmod(_loco_phase + delta * ts / cycle, 1.0)
	if (before < 0.5 and _loco_phase >= 0.5) or _loco_phase < before:
		footstep.emit()


func _update_equip(delta: float) -> void:
	var target := 0.0
	if _equip_active:
		_equip_t += delta * equip_speed
		var swap_t := DRAW_GRAB_TIME if _equip_drawing else SHEATHE_RELEASE_TIME
		if not _equip_swapped and _equip_t >= swap_t:
			_equip_swapped = true
			set_sword_drawn(_equip_drawing)
		var length := _clip_length(CLIP_DRAW if _equip_drawing else CLIP_SHEATHE)
		if _equip_t >= length:
			_equip_active = false
		else:
			target = 1.0
			anim_tree.set("parameters/upper_seek/seek_request", _equip_t)
	_upper_weight = move_toward(_upper_weight, target, delta / 0.12)
	anim_tree.set("parameters/upper_blend/blend_amount", _upper_weight)


## Stops an equip animation; the katana ends up wherever it was at that moment.
func _cancel_equip() -> void:
	if _equip_active:
		_equip_active = false
		sword_drawn = _katana != null and _katana.get_parent() == _hand_attach


func _update_tilt(delta: float) -> void:
	var target := 0.0
	if _dead:
		target = 84.0
	elif _knockdown_t >= 0.0:
		_knockdown_t += delta
		# Fall back for 0.3 s, stay down, get up by 1.0 s (matches the knockdown hitstun).
		var k := _knockdown_t
		target = 70.0 * (clampf(k / 0.3, 0.0, 1.0) - clampf((k - 0.65) / 0.35, 0.0, 1.0))
		if k >= 1.0:
			_knockdown_t = -1.0
	if _flinch_t >= 0.0:
		_flinch_t += delta
		target += _flinch_amp * sin(PI * clampf(_flinch_t / _flinch_len, 0.0, 1.0))
		if _flinch_t >= _flinch_len:
			_flinch_t = -1.0
	_tilt = lerpf(_tilt, target, 1.0 - exp(-delta * (6.0 if _dead else 18.0)))
	_pose_root.rotation_degrees.x = _tilt


func _clip_length(clip: StringName) -> float:
	if anim_player and anim_player.has_animation(clip):
		return anim_player.get_animation(clip).length
	return 0.0
