extends SceneTree
## Resource checks always run. --require-model additionally requires the private samurai.
## godot --headless --path . --script tools/locomotion/validate.gd -- --require-model

const MODEL := "res://assets/models/kengeki/kengeki_character_animated.glb"
const BONES := ["CC_Base_Hip", "CC_Base_L_Thigh", "CC_Base_L_Calf", "CC_Base_L_Foot",
	"CC_Base_R_Thigh", "CC_Base_R_Calf", "CC_Base_R_Foot"]
var failures := 0

func _initialize() -> void:
	call_deferred("validate")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func validate() -> void:
	var model: Node3D
	var skeleton: Skeleton3D
	if ResourceLoader.exists(MODEL):
		var scene := load(MODEL) as PackedScene
		if scene:
			model = scene.instantiate() as Node3D
			root.add_child(model)
			skeleton = model.get_node_or_null("Kengeki_Rig/Skeleton3D") as Skeleton3D
		check(skeleton != null, "Original samurai skeleton not found")
		if skeleton:
			check(skeleton.get_bone_count() == 101, "Original skeleton must have 101 bones")
	else:
		print("MODEL VALIDATION BLOCKED: private samurai GLB is absent")
		if "--require-model" in OS.get_cmdline_user_args():
			failures += 1
	# Cross-check bone names against the current combat library, independently of the upload.
	var known_bones := {"RL_BoneRoot": true}
	var combat := load("res://assets/animations/kinemiq/kinemiq_combat.res") as AnimationLibrary
	for name in combat.get_animation_list():
		var animation := combat.get_animation(name)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if path.get_subname_count() == 1:
				known_bones[String(path.get_subname(0))] = true
	for name in ["walk", "run", "jump"]:
		var clip := load("res://assets/animations/locomotion/%s.res" % name) as Animation
		check(clip != null, "Cannot load " + name)
		if clip == null:
			continue
		check(clip.length > 0.0 and is_finite(clip.length), name + ": invalid duration")
		check(clip.loop_mode == (Animation.LOOP_NONE if name == "jump" else Animation.LOOP_LINEAR), name + ": incorrect looping")
		var paths := {}
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			var type := clip.track_get_type(track)
			check(path.get_concatenated_names() == "Kengeki_Rig/Skeleton3D" and path.get_subname_count() == 1, name + ": invalid target " + str(path))
			if path.get_subname_count() != 1:
				continue
			var bone := String(path.get_subname(0))
			check(known_bones.has(bone), name + ": unknown bone " + bone)
			if skeleton:
				check(skeleton.find_bone(bone) >= 0, name + ": missing skeleton bone " + bone)
			check(type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D], name + ": unexpected track type")
			var key_id := str(path) + ":" + str(type)
			check(not paths.has(key_id), name + ": duplicate track " + key_id)
			paths[key_id] = true
			var count := clip.track_get_key_count(track)
			check(count > 0, name + ": empty track")
			var previous := -1.0
			for key in count:
				var time := clip.track_get_key_time(track, key)
				check(is_finite(time) and time >= previous and time <= clip.length + 0.001, name + ": invalid key time")
				previous = time
				var value: Variant = clip.track_get_key_value(track, key)
				if value is Vector3:
					check(value.is_finite(), name + ": nonfinite vector")
				elif value is Quaternion:
					check(value.is_finite() and absf(value.length() - 1.0) < 0.001, name + ": invalid quaternion")
			if name != "jump" and bone in BONES and count > 0:
				check(clip.track_get_key_value(track, 0).is_equal_approx(clip.track_get_key_value(track, count - 1)), name + ": edited leg track has a loop seam")
		for bone in BONES:
			check(clip.find_track(NodePath("Kengeki_Rig/Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D) >= 0, name + ": missing leg animation " + bone)
		print("VALIDATED ", name, " tracks=", clip.get_track_count())
	if model:
		model.free()
	print("RESOURCE_VALIDATION failures=", failures, "; model checked=", skeleton != null)
	quit(1 if failures > 0 else 0)
