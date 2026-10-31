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
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				var holder := Node3D.new()
				holder.name = "Model"
				holder.scale = model_scale_xyz * model_scale
				holder.position = model_offset
				holder.rotation_degrees.y = model_yaw_degrees
				holder.add_child(inst)
				_apply_render_settings(inst)
				add_child(holder)  # not owned: never saved into the scene file
				has_model = true
	var gb := get_node_or_null(^"Graybox") as Node3D
	if gb:
		gb.visible = not has_model


func _apply_render_settings(node: Node) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		g.lod_bias = model_lod_bias
		g.visibility_range_end = model_visibility_range_end
		g.visibility_range_end_margin = model_visibility_range_end_margin
	for c in node.get_children():
		_apply_render_settings(c)
