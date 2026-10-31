extends SceneTree
## Windowed (NOT headless) render of fixed courtyard views: saves a JPG per view and prints the
## renderer's Performance monitors (draw calls, primitives, objects) for each view.
## Usage (Linux, software Vulkan):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##       -s res://tools/courtyard/render_views.gd -- OUT_DIR [LABEL] [--no-shots]
## Measurement overrides (to reproduce the pre-tuning state): --lod-bias=1 (also clears visibility
## ranges) --shadow-mode=2 --shadow-dist=90 ; --no-shadows ; --lod-threshold=PX.
## The numbers are renderer counts, not FPS; llvmpipe FPS is not representative of a real GPU.

const VIEWS := [
	# name, camera position, look-at target
	["01_overview_from_gate", Vector3(0, 9.5, 27), Vector3(0, 1, -22)],
	["02_combat_centre_eye", Vector3(0, 1.6, 9), Vector3(0, 2.2, -20)],
	["03_pond_arch_bridge", Vector3(23.5, 2.6, -9.5), Vector3(31, 0.3, 0)],
	["04_wall_turret_seam", Vector3(35.5, 1.8, -34.0), Vector3(39.0, 2.8, -42.5)],
	["05_gate_interior", Vector3(0, 1.7, 22), Vector3(0, 3.2, 33)],
	["06_keep_backdrop", Vector3(6, 1.7, -22), Vector3(0, 11, -68)],
]

var out_dir := ""
var label := "run"
var shots := true
var views: Array = VIEWS
var lod_bias_override := -1.0
var no_shadows := false
var shadow_mode := -1
var shadow_dist := -1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://shots"
	if args.size() > 1 and not args[1].begins_with("--"):
		label = args[1]
	shots = not args.has("--no-shots")
	for a in args:  # experiment overrides (measurement only; the shipped values live in the scenes)
		if a.begins_with("--lod-bias="):
			lod_bias_override = float(a.get_slice("=", 1))
		elif a.begins_with("--shadow-mode="):
			shadow_mode = int(a.get_slice("=", 1))
		elif a.begins_with("--shadow-dist="):
			shadow_dist = float(a.get_slice("=", 1))
		elif a.begins_with("--view="):  # --view=name,px,py,pz,tx,ty,tz (replaces the fixed views)
			var f := a.get_slice("=", 1).split(",")
			if views == VIEWS:
				views = []
			views.append([f[0], Vector3(float(f[1]), float(f[2]), float(f[3])), Vector3(float(f[4]), float(f[5]), float(f[6]))])
		elif a == "--no-shadows":
			no_shadows = true
		elif a.begins_with("--lod-threshold="):
			get_root().mesh_lod_threshold = float(a.get_slice("=", 1))
	# A script error in a -s script leaves Godot running; never hang a batch run.
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("RENDER timeout")
		quit(3))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var arena := (load("res://environment/courtyard/scenes/castle_courtyard.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	_run.call_deferred(arena)


func _run(arena: Node) -> void:
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.1
	cam.far = 300.0
	root.add_child(cam)
	cam.current = true
	print("RENDER adapter=%s | %s | api=%s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	print("RENDER method=%s size=%s" % [ProjectSettings.get_setting("rendering/renderer/rendering_method"), root.size])
	for i in 20:
		await process_frame
	if lod_bias_override >= 0.0:
		for g in arena.find_children("*", "GeometryInstance3D", true, false):
			g.lod_bias = lod_bias_override
			g.visibility_range_end = 0.0
	var sun := arena.get_node(^"Sun") as DirectionalLight3D
	if no_shadows:
		sun.shadow_enabled = false
	if shadow_mode >= 0:
		sun.directional_shadow_mode = shadow_mode
	if shadow_dist > 0.0:
		sun.directional_shadow_max_distance = shadow_dist
	print("RENDER settings lod_bias_override=%s no_shadows=%s mesh_lod_threshold=%s" % [lod_bias_override, no_shadows, root.mesh_lod_threshold])
	var tot := [0, 0, 0]
	for v in views:
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		for i in 8:  # settle (LOD selection, shadows, TAA-free so a few frames suffice)
			await process_frame
		await RenderingServer.frame_post_draw
		var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var obj := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		tot[0] += dc; tot[1] += prim; tot[2] += obj
		print("VIEW %s %s draw_calls=%d primitives=%d objects=%d" % [label, v[0], dc, prim, obj])
		if shots:
			var img := root.get_texture().get_image()
			img.save_jpg(out_dir.path_join(v[0] + ".jpg"), 0.82)
	print("TOTAL %s draw_calls=%d primitives=%d objects=%d (sum of %d views)" % [label, tot[0], tot[1], tot[2], views.size()])
	print("VRAM video_mem_used=%.1f MB texture_mem=%.1f MB buffer_mem=%.1f MB" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	quit(0)
