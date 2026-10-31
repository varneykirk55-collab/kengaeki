@tool
class_name CourtyardProp
extends Node3D
## Wrapper for one courtyard module or prop.
##   Graybox   - placeholder meshes, shown until the real model is available.
##   Collision - hand-authored simple shapes (layer 1 "world"). Always kept; the imported
##               mesh never provides gameplay collision.
##   Model     - created at load time from `model_path` (BJORN's optimised GLB) if that file
##               exists in the project. If it does not, the graybox stays visible, so a scene
##               never holds a broken resource reference.

@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = "":
	set(v):
		model_path = v
		if is_node_ready():
			_refresh()
## Applied to the imported model only (use when a GLB is not authored at real-world scale).
@export var model_scale: float = 1.0:
	set(v):
		model_scale = v
		if is_node_ready():
			_refresh()
@export var model_yaw_degrees: float = 0.0:
	set(v):
		model_yaw_degrees = v
		if is_node_ready():
			_refresh()
## Per-axis fit applied on top of model_scale (integration fit only; documented in DEVIATIONS.md).
@export var model_scale_xyz: Vector3 = Vector3.ONE:
	set(v):
		model_scale_xyz = v
		if is_node_ready():
			_refresh()
## Offset of the imported model inside the wrapper (e.g. sink a bridge so its ends sit flush).
@export var model_offset: Vector3 = Vector3.ZERO:
	set(v):
		model_offset = v
		if is_node_ready():
			_refresh()
## Bill's authored size for this module (x, y, z before yaw), for the integration checks.
@export var authored_size: Vector3 = Vector3.ZERO
## Allowed deviation from authored_size per axis in percent (min, max) for the integration checks
## where the default +-10% does not apply (natural shapes such as rocks; DEVIATIONS.md).
@export var size_tolerance_pct: Vector2 = Vector2(-10, 10)
## Mesh LOD bias for the imported model (GeometryInstance3D.lod_bias). Below 1 switches to the
## import-generated LOD meshes sooner; 1.0 is Godot's default.
@export var model_lod_bias: float = 1.0:
	set(v):
		model_lod_bias = v
		if is_node_ready():
			_refresh()
## Visibility range for the imported model (0 = always drawn). The margin adds hysteresis
## so the model does not flicker at the boundary.
@export var model_visibility_range_end: float = 0.0:
	set(v):
		model_visibility_range_end = v
		if is_node_ready():
			_refresh()
@export var model_visibility_range_end_margin: float = 0.0:
	set(v):
		model_visibility_range_end_margin = v
		if is_node_ready():
			_refresh()
## Hand-made LOD levels: BJORN's _lod GLBs, which share LOD0's origin, scale and orientation, so
## they are instanced as siblings of the model under the same holder. Missing files are skipped
## (the scene never references a file that is not in the project).
@export var model_lod_paths: PackedStringArray = PackedStringArray():
	set(v):
		model_lod_paths = v
		if is_node_ready():
			_refresh()
## Camera distance (m) at which each model_lod_paths entry takes over from the previous level
## (ascending, one per entry). Godot measures from the camera to each mesh's AABB centre.
@export var model_lod_distances: PackedFloat32Array = PackedFloat32Array():
	set(v):
		model_lod_distances = v
		if is_node_ready():
			_refresh()
## Width (m) of the dithered crossfade at each LOD switch (visibility range margins with
## VISIBILITY_RANGE_FADE_SELF). 0 = hard switch.
@export var model_lod_fade: float = 0.0:
	set(v):
		model_lod_fade = v
		if is_node_ready():
			_refresh()
## Per model_lod_paths entry: 1 = draw that level with LOD0's materials (same UV layout; its own
## embedded textures are not imported, see the .glb.import files), 0 = keep its own materials.
@export var model_lod_share_materials: PackedInt32Array = PackedInt32Array():
	set(v):
		model_lod_share_materials = v
		if is_node_ready():
			_refresh()
## Force the graybox even when a model is available (debugging / comparing scale).
@export var force_graybox: bool = false:
	set(v):
		force_graybox = v
		if is_node_ready():
			_refresh()

var has_model := false


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	var old := get_node_or_null(^"Model")
	if old:
		old.free()
	has_model = false
	if not force_graybox and model_path != "" and ResourceLoader.exists(model_path):
		var packed := load(model_path) as PackedScene
		var inst: Node3D = packed.instantiate() as Node3D if packed else null
		if inst:
			var holder := Node3D.new()
			holder.name = "Model"
			holder.scale = model_scale_xyz * model_scale
			holder.position = model_offset
			holder.rotation_degrees.y = model_yaw_degrees
			# Levels that exist: [path, switch-in distance, share LOD0 materials].
			var levels: Array = []
			for i in model_lod_paths.size():
				var p := model_lod_paths[i]
				if p != "" and ResourceLoader.exists(p) and i < model_lod_distances.size():
					levels.append([p, model_lod_distances[i], i < model_lod_share_materials.size() and model_lod_share_materials[i] != 0])
			inst.name = "LOD0"
			inst.set_meta(&"courtyard_lod", 0)
			holder.add_child(inst)
			var lod0_meshes := _meshes(inst)
			var begin := 0.0
			for li in levels.size() + 1:
				var node: Node3D = inst
				if li > 0:
					var lp := load(levels[li - 1][0]) as PackedScene
					node = lp.instantiate() as Node3D if lp else null
					if node == null:
						continue
					node.name = "LOD%d" % li
					node.set_meta(&"courtyard_lod", li)
					holder.add_child(node)
					if levels[li - 1][2]:
						_share_materials(node, lod0_meshes)
				var last := li == levels.size()
				var end := model_visibility_range_end if last else float(levels[li][1])
				var end_margin := model_visibility_range_end_margin if last else model_lod_fade
				_apply_render_settings(node, begin, model_lod_fade if li > 0 else 0.0, end, end_margin, levels.size() > 0 and model_lod_fade > 0.0)
				if not last:
					begin = float(levels[li][1])
			add_child(holder)  # not owned: never saved into the scene file
			has_model = true
	var gb := get_node_or_null(^"Graybox") as Node3D
	if gb:
		gb.visible = not has_model


## Top-level node of one model LOD level under the "Model" holder (0 = model_path), or null.
func get_model_lod(level: int) -> Node3D:
	var holder := get_node_or_null(^"Model")
	if holder:
		for c in holder.get_children():
			if int(c.get_meta(&"courtyard_lod", -1)) == level:
				return c as Node3D
	return null


func get_model_lod_count() -> int:
	var holder := get_node_or_null(^"Model")
	return holder.get_child_count() if holder else 0


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


## Draw a LOD level with LOD0's materials (surface by surface; BJORN's tree LODs and the turret
## lod1 keep LOD0's UV layout, so LOD0's textures map unchanged).
func _share_materials(node: Node, lod0: Array[MeshInstance3D]) -> void:
	if lod0.is_empty():
		return
	var mine := _meshes(node)
	for k in mine.size():
		var src := lod0[mini(k, lod0.size() - 1)]
		var mi := mine[k]
		if mi.mesh == null or src.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := src.get_active_material(mini(s, src.mesh.get_surface_count() - 1))
			if m:
				mi.set_surface_override_material(s, m)


func _apply_render_settings(node: Node, begin: float, begin_margin: float, end: float, end_margin: float, fade: bool) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		g.lod_bias = model_lod_bias
		g.visibility_range_begin = begin
		g.visibility_range_begin_margin = begin_margin if begin > 0.0 else 0.0
		g.visibility_range_end = end
		g.visibility_range_end_margin = end_margin if end > 0.0 else 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in node.get_children():
		_apply_render_settings(c, begin, begin_margin, end, end_margin, fade)
