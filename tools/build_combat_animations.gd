extends SceneTree
## Builds res://assets/animations/kinemiq/kinemiq_combat.res (an AnimationLibrary) from the
## KinemIQ combat GLBs. Only the animation data is kept: no meshes, skins or textures.
##
##   godot --headless --path . -s res://tools/build_combat_animations.gd -- <folder with the GLBs>
##
## The KinemIQ files were exported onto the Kengeki samurai's own 101-bone CC_Base rig (same
## joint names, same order, identical inverse bind matrices), so retargeting is a direct
## per-bone copy of the local rotations. Every channel in the file is kept, including the ones
## that never change (finger grip, toes): Godot's runtime glTF importer would drop those as
## "equal to rest", but their rest is the KinemIQ file's pose, not the Kengeki GLB's.
##
## Root motion: KinemIQ puts the ground travel on CC_Base_Hip (RL_BoneRoot never moves). The
## horizontal part of that travel is removed (height and sway kept), so the clips play in place
## like the existing ones and only the controller moves the body (AttackData.lunge_distance).

const RIG := "Kengeki_Rig/Skeleton3D"
const OUT := "res://assets/animations/kinemiq/kinemiq_combat.res"
const CLIPS := {
	"Light_Slash_A": "Sword_-_light_slash_A.glb",
	"Light_Combo": "Sword_-_light_combo (1).glb",
	"Heavy_Slash_B": "Sword_-_heavy_slash_B.glb",
	"Heavy_Slash_C": "Sword_-_heavy_slash_C.glb",
	"Block": "Block_-_with_the_sword.glb",
}
## Alternative file names accepted for the same clip (e.g. after copying without spaces).
const ALIASES := {"Sword_-_light_combo (1).glb": ["Sword_-_light_combo_1.glb"]}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if args.size() > 0 else "."
	var lib := AnimationLibrary.new()
	for clip_name in CLIPS:
		var path := dir.path_join(CLIPS[clip_name])
		if not FileAccess.file_exists(path):
			for alt in ALIASES.get(CLIPS[clip_name], []):
				if FileAccess.file_exists(dir.path_join(alt)):
					path = dir.path_join(alt)
		var anim := _build(path)
		if anim == null:
			push_error("build_combat_animations: could not read %s" % path)
			quit(1)
			return
		lib.add_animation(StringName(clip_name), anim)
		print("%-14s %5.3f s  %d tracks  <- %s" % [clip_name, anim.length, anim.get_track_count(), path.get_file()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, " err ", err)
	quit(err)


func _build(path: String) -> Animation:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != 0x46546C67:  # "glTF"
		return null
	f.get_32()  # version
	f.get_32()  # total length
	var json_len := f.get_32()
	f.get_32()  # "JSON"
	var gltf: Dictionary = JSON.parse_string(f.get_buffer(json_len).get_string_from_utf8())
	var bin_len := f.get_32()
	f.get_32()  # "BIN\0"
	var bin := f.get_buffer(bin_len)
	var nodes: Array = gltf["nodes"]
	var src: Dictionary = gltf["animations"][0]
	var anim := Animation.new()
	anim.step = 1.0 / 30.0
	var length := 0.0
	for ch in src["channels"]:
		var target: Dictionary = ch["target"]
		var bone: String = nodes[int(target["node"])].get("name", "")
		var sampler: Dictionary = src["samplers"][int(ch["sampler"])]
		var times := _floats(gltf, bin, int(sampler["input"]))
		var values := _floats(gltf, bin, int(sampler["output"]))
		var kind: String = target["path"]
		if bone == "RL_BoneRoot":
			continue  # constant at rest in every KinemIQ clip; it is the tree's root motion track
		length = maxf(length, times[times.size() - 1])
		var track_path := NodePath("%s:%s" % [RIG, bone])
		if kind == "rotation":
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, track_path)
			for i in times.size():
				anim.rotation_track_insert_key(t, times[i], Quaternion(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3]).normalized())
		elif kind == "translation" and bone == "CC_Base_Hip":
			# Hip translation is in RL_BoneRoot space (rotated -90 deg about X): local x and y are
			# the ground plane, local z is height. Keep frame 0's ground offset for every key.
			var t := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(t, track_path)
			var x0 := values[0]
			var y0 := values[1]
			for i in times.size():
				anim.position_track_insert_key(t, times[i], Vector3(x0, y0, values[i * 3 + 2]))
		elif kind == "translation":
			var t := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(t, track_path)
			for i in times.size():
				anim.position_track_insert_key(t, times[i], Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2]))
	anim.length = length
	anim.loop_mode = Animation.LOOP_NONE
	return anim


func _floats(gltf: Dictionary, bin: PackedByteArray, accessor_index: int) -> PackedFloat32Array:
	var acc: Dictionary = gltf["accessors"][accessor_index]
	var view: Dictionary = gltf["bufferViews"][int(acc["bufferView"])]
	var comps: int = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
	assert(int(acc["componentType"]) == 5126)
	var start := int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	var count := int(acc["count"]) * comps
	return bin.slice(start, start + count * 4).to_float32_array()
