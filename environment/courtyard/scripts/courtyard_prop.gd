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
				holder.scale = Vector3.ONE * model_scale
				holder.rotation_degrees.y = model_yaw_degrees
				holder.add_child(inst)
				add_child(holder)  # not owned: never saved into the scene file
				has_model = true
	var gb := get_node_or_null(^"Graybox") as Node3D
	if gb:
		gb.visible = not has_model
