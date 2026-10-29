class_name Katana
extends Node3D
## Modular katana. Origin = grip point (where the leading hand holds it); blade extends
## along local -Z. To use a Hunyuan katana model: set build_placeholder = false, add the
## model as a child aligned to this convention, and move the BladeBase/BladeTip markers to
## the real blade. Trail, sparks and blade-area hit detection all read those markers.

@export var build_placeholder: bool = true
@export var blade_length: float = 0.74
@export var handle_length: float = 0.27

var blade_base: Marker3D
var blade_tip: Marker3D
var blade_area: Area3D
var trail: BladeTrail


func _ready() -> void:
	blade_base = get_node_or_null("BladeBase") as Marker3D
	blade_tip = get_node_or_null("BladeTip") as Marker3D
	if blade_base == null:
		blade_base = Marker3D.new()
		blade_base.name = "BladeBase"
		blade_base.position = Vector3(0, 0, -0.12)
		add_child(blade_base)
	if blade_tip == null:
		blade_tip = Marker3D.new()
		blade_tip.name = "BladeTip"
		blade_tip.position = Vector3(0, 0.035, -0.12 - blade_length)
		add_child(blade_tip)
	if build_placeholder:
		_build_placeholder_mesh()
	_build_blade_area()
	trail = BladeTrail.new()
	trail.name = "Trail"
	add_child(trail)
	trail.base_path = trail.get_path_to(blade_base)
	trail.tip_path = trail.get_path_to(blade_tip)
	trail._base = blade_base
	trail._tip = blade_tip


func set_trail_emitting(on: bool) -> void:
	if trail:
		trail.emitting = on


func _build_placeholder_mesh() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.83)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.08, 0.07, 0.07)
	wrap.roughness = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.55, 0.43, 0.2)
	gold.metallic = 0.7
	gold.roughness = 0.4

	var handle := _box(Vector3(0.032, 0.036, handle_length), wrap)
	handle.position = Vector3(0, 0, handle_length * 0.5 - 0.09)
	var tsuba := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.045
	disc.bottom_radius = 0.045
	disc.height = 0.012
	disc.radial_segments = 12
	disc.material = gold
	tsuba.mesh = disc
	tsuba.rotation_degrees.x = 90
	tsuba.position = Vector3(0, 0, -0.1)
	add_child(tsuba)
	# Blade in three slightly rotated segments to suggest the curve (sori).
	var seg := blade_length / 3.0
	var start := Vector3(0, 0, -0.11)
	for i in 3:
		var b := _box(Vector3(0.008, 0.03 - i * 0.004, seg + 0.01), steel)
		var angle := deg_to_rad(1.5 + i * 1.5)
		var dir := Vector3(0, sin(angle), -cos(angle))
		b.position = start + dir * seg * 0.5
		b.rotation.x = angle
		start += dir * seg


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	add_child(mi)
	return mi


func _build_blade_area() -> void:
	blade_area = Area3D.new()
	blade_area.name = "BladeArea"
	blade_area.collision_layer = 0
	blade_area.collision_mask = 1 << 3
	blade_area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.1, blade_length)
	cs.shape = box
	cs.position = Vector3(0, 0.02, -0.12 - blade_length * 0.5)
	blade_area.add_child(cs)
	add_child(blade_area)
