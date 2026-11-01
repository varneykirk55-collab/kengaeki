extends Node
## Tests the production animation graph and gait timing without substituting a game model.
## Synthetic empty original clips are used only in this fixture. No visual quality claim.
## godot --headless --path . res://tests/locomotion_tests.tscn

var passes := 0
var failures := 0

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		passes += 1
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func fixture(refined: bool) -> KengekiCharacterVisual:
	var visual := KengekiCharacterVisual.new()
	visual.refined_locomotion = refined
	visual.model = Node3D.new()
	visual.anim_player = AnimationPlayer.new()
	visual.anim_player.name = "AnimationPlayer"
	visual.model.add_child(visual.anim_player)
	var originals := AnimationLibrary.new()
	for name in [visual.CLIP_IDLE, visual.CLIP_WALK, visual.CLIP_RUN, visual.CLIP_JUMP, visual.CLIP_COMBO, visual.CLIP_DRAW, visual.CLIP_SHEATHE]:
		var animation := Animation.new()
		animation.length = 1.0
		originals.add_animation(name, animation)
	visual.anim_player.add_animation_library(&"", originals)
	visual._load_combat_clips()
	if refined:
		check(visual._install_locomotion(), "refined resource library loads")
	visual._build_tree()
	visual.anim_tree.active = false
	visual.combatant = Combatant.new()
	visual.combatant.attack_runner = AttackRunner.new()
	return visual

func dispose(visual: KengekiCharacterVisual) -> void:
	visual.combatant.attack_runner.free()
	visual.combatant.free()
	visual.model.free()
	visual.free()

func step(visual: KengekiCharacterVisual, speed: float, count: int = 1) -> void:
	visual.set_locomotion(Vector3(0, 0, -speed), 7.4)
	for i in count:
		visual._update_locomotion(1.0 / 60.0)

func run() -> void:
	var v := fixture(true)
	var original := v.anim_player.get_animation(v.CLIP_RUN)
	check(v.anim_player.has_animation_library(&"kinemiq"), "current combat library retained")
	for key in v.KQ_ATTACKS:
		check(v.attack_clip(key) == v.KQ_ATTACKS[key], "combat mapping retained: " + str(key))
	check(v.anim_tree.tree_root.get_node(&"walk").animation == &"locomotion/walk", "walk uses refined clip")
	check(v.anim_tree.tree_root.get_node(&"run").animation == &"locomotion/run", "sprint uses refined clip")
	step(v, 0.29)
	check(v._loco_state == &"idle", "idle ignores small velocity noise")
	step(v, 0.4)
	check(v._loco_state == &"walk", "acceleration enters walk")
	step(v, 0.22)
	check(v._loco_state == &"walk", "deceleration retains walk above idle exit threshold")
	step(v, 4.6, 30)
	var walk_phase := v._gait_phase
	step(v, 5.5)
	check(v._loco_state == &"walk", "walk does not flicker into run near threshold")
	step(v, 7.4, 30)
	check(v._loco_state == &"run" and not is_equal_approx(walk_phase, v._gait_phase), "sprint cycle advances")
	step(v, 5.3)
	check(v._loco_state == &"run", "run hysteresis prevents threshold flicker")
	step(v, 4.6)
	check(v._loco_state == &"walk", "deceleration returns to walk")
	step(v, 0.1)
	check(v._loco_state == &"idle", "stopping returns to idle")
	var stopped_phase := v._gait_phase
	step(v, 0.0, 30)
	check(is_equal_approx(stopped_phase, v._gait_phase), "idle does not advance foot contacts")
	step(v, -3.9, 30)
	check(v._gait_direction == -1.0, "backpedal reverses gait smoothly")
	var phase := v._gait_phase
	step(v, -3.9)
	check(fposmod(phase - v._gait_phase, 1.0) < 0.1, "backpedal advances backward without a phase reset")
	step(v, 3.9, 30)
	check(v._gait_direction == 1.0 and is_finite(v._gait_phase), "direction reversal resumes forward gait")
	var position := float(v.anim_tree.get("parameters/walk_seek/seek_request"))
	check(position >= 0.0 and position < v._clip_length(&"locomotion/walk"), "phase uses refined duration, independent of original duration")
	v.play_jump(0.55)
	v._update_jump(0.02)
	check(v.anim_tree.tree_root.get_node(&"act_a" if v._action_slot == 0 else &"act_b").animation == &"locomotion/jump" and v._jump_clip_t >= 0.60 and v._jump_clip_t < 0.75, "jump starts with brief compression")
	v._update_jump(0.3)
	v.play_land()
	v._update_jump(0.1)
	check(v._jump == v.Jump.LAND, "moving landing retains compression")
	v._update_jump(0.2)
	check(v._jump == v.Jump.NONE and v.model.position.y == 0.0, "landing returns to locomotion without model offset")
	v.play_dodge(Vector3.FORWARD, 0.42)
	v._current_action(0.05)
	check(v.anim_tree.tree_root.get_node(&"act_a" if v._action_slot == 0 else &"act_b").animation == &"locomotion/run", "dash uses refined run posture")
	check(v.anim_player.get_animation(v.CLIP_RUN) == original, "original run resource is untouched")
	var runner := v.combatant.attack_runner
	runner.attack = load("res://resources/attacks/player/light_1.tres") as AttackData
	runner.phase = AttackRunner.Phase.STARTUP
	runner.phase_time = 0.0
	v._current_action(1.0 / 60.0)
	check(v._attack_ref == runner.attack and v._dodge_left == 0.0, "attack takes priority over dash playback")
	check(v.anim_tree.tree_root.get_node(&"act_a" if v._action_slot == 0 else &"act_b").animation == v.KQ_SLASH_A, "attack still selects current KinemIQ clip")
	runner.phase = AttackRunner.Phase.NONE
	v.set_guard(true)
	v._current_action(1.0 / 60.0)
	check(v.anim_tree.tree_root.get_node(&"act_a" if v._action_slot == 0 else &"act_b").animation == v.KQ_BLOCK, "guard retains current KinemIQ block clip")
	dispose(v)
	var legacy := fixture(false)
	check(legacy.anim_tree.tree_root.get_node(&"walk").animation == legacy.CLIP_WALK, "A/B toggle restores original walk")
	step(legacy, 7.4)
	check(legacy._loco_state == &"run", "legacy locomotion remains functional")
	dispose(legacy)
	print("LOCOMOTION TESTS: ", passes, " passed, ", failures, " failed")
	get_tree().quit(1 if failures else 0)
