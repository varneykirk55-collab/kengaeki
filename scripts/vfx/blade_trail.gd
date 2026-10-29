class_name BladeTrail
extends MeshInstance3D
## Subtle ribbon following the blade edge during the hit window ("air cut" streak).
## Deliberately pale and translucent: a motion cue, not a glowing magic effect.

@export var base_path: NodePath
@export var tip_path: NodePath
@export var lifetime: float = 0.14
@export var color: Color = Color(0.92, 0.94, 1.0, 0.32)
@export var max_samples: int = 24

var emitting := false
var _base: Node3D
var _tip: Node3D
var _samples: Array = []  # [base: Vector3, tip: Vector3, age: float]
var _mesh: ImmediateMesh


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	_base = get_node_or_null(base_path)
	_tip = get_node_or_null(tip_path)


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for s in _samples:
		s[2] += delta
	while not _samples.is_empty() and _samples[0][2] > lifetime:
		_samples.pop_front()
	if emitting and _base and _tip:
		_samples.append([_base.global_position, _tip.global_position, 0.0])
		if _samples.size() > max_samples:
			_samples.pop_front()
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var a := 1.0 - clampf(s[2] / lifetime, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * a)
		var inner := Color(c.r, c.g, c.b, 0.0)
		# Fade toward the hilt so the ribbon reads as the edge's path.
		_mesh.surface_set_color(inner)
		_mesh.surface_add_vertex(s[0].lerp(s[1], 0.35))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(s[1])
	_mesh.surface_end()
