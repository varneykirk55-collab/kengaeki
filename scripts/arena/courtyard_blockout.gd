@tool
class_name CourtyardBlockout
extends Node3D
## Placeholder castle courtyard. Generates two independent layers:
##   Collision - invisible StaticBody3D volumes (ground, walls, obstacles). Gameplay +
##               navigation use only these.
##   Visual    - primitive meshes for the look of the courtyard.
## When the Hunyuan courtyard arrives: set show_visuals = false, drop the imported scene
## under Arena/Visual, and keep (or re-fit) these collision volumes. See docs.

@export var show_visuals: bool = true:
	set(v):
		show_visuals = v
		if is_node_ready():
			_rebuild()
@export var build_collision: bool = true
@export var half_size: float = 20.0
@export var wall_height: float = 3.6

const NAV_GROUP := &"nav_source"

var _collision_root: Node3D
var _visual_root: Node3D
var _mats: Dictionary = {}


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.free()
	_collision_root = Node3D.new()
	_collision_root.name = "Collision"
	add_child(_collision_root)
	_collision_root.add_to_group(NAV_GROUP)
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)
	_visual_root.visible = show_visuals
	if build_collision:
		_build_collision()
	_build_visuals()


# --- Collision ---------------------------------------------------------------------

func _build_collision() -> void:
	var h := half_size
	_col_box(Vector3(0, -0.5, 0), Vector3(h * 3.0, 1.0, h * 3.0))
	_col_box(Vector3(0, wall_height * 0.5, -h - 0.5), Vector3(h * 2 + 2, wall_height, 1.0))
	_col_box(Vector3(0, wall_height * 0.5, h + 0.5), Vector3(h * 2 + 2, wall_height, 1.0))
	_col_box(Vector3(h + 0.5, wall_height * 0.5, 0), Vector3(1.0, wall_height, h * 2 + 2))
	_col_box(Vector3(-h - 0.5, wall_height * 0.5, 0), Vector3(1.0, wall_height, h * 2 + 2))
	for p in _lantern_positions():
		_col_cylinder(p + Vector3(0, 0.9, 0), 0.42, 1.8)
	_col_cylinder(_tree_position() + Vector3(0, 1.5, 0), 0.45, 3.0)
	for p in _rack_positions():
		_col_box(p + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 0.5))


func _lantern_positions() -> Array[Vector3]:
	return [Vector3(8, 0, 8), Vector3(-8, 0, 8), Vector3(8, 0, -8), Vector3(-8, 0, -8)]


func _tree_position() -> Vector3:
	return Vector3(-half_size + 3.0, 0, -half_size + 3.0)


func _rack_positions() -> Array[Vector3]:
	return [Vector3(half_size - 0.6, 0, 8.0), Vector3(-half_size + 0.6, 0, 8.0)]


func _col_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	_collision_root.add_child(body)


func _col_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	_collision_root.add_child(body)


# --- Visuals -----------------------------------------------------------------------

func _mat(key: String, color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]


func _vbox(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	_visual_root.add_child(mi)
	return mi


func _vcyl(pos: Vector3, top: float, bottom: float, height: float, mat: Material, segments: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_visual_root.add_child(mi)
	return mi


func _roof(pos: Vector3, width: float, depth: float, mat: Material, height: float = 0.8) -> void:
	# Hip roof: a 4-sided cylinder (pyramid frustum) rotated 45 degrees, then scaled to the
	# footprint by its parent so the scale applies along the world axes.
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3(width * 0.7071, height, depth * 0.7071)
	_visual_root.add_child(holder)
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.35
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 4
	mi.mesh = m
	mi.material_override = mat
	mi.rotation_degrees.y = 45.0
	holder.add_child(mi)


func _build_visuals() -> void:
	var h := half_size
	var gravel := _mat("gravel", Color(0.5, 0.48, 0.43))
	var stone := _mat("stone", Color(0.38, 0.37, 0.35))
	var path := _mat("path", Color(0.36, 0.35, 0.33))
	var plaster := _mat("plaster", Color(0.72, 0.7, 0.65))
	var tile := _mat("tile", Color(0.17, 0.19, 0.22), 0.6)
	var wood := _mat("wood", Color(0.27, 0.17, 0.11))
	var lacquer := _mat("lacquer", Color(0.52, 0.12, 0.08), 0.5)
	var bark := _mat("bark", Color(0.24, 0.17, 0.13))
	var blossom := _mat("blossom", Color(0.95, 0.72, 0.8))
	var grass := _mat("grass", Color(0.33, 0.4, 0.24))

	# Ground: outer grass, inner raked gravel, stone paths to the four gates.
	_vbox(Vector3(0, -0.06, 0), Vector3(h * 6.0, 0.1, h * 6.0), grass)
	_vbox(Vector3(0, -0.02, 0), Vector3(h * 2, 0.04, h * 2), gravel)
	_vbox(Vector3(0, 0.005, 0), Vector3(2.4, 0.02, h * 2), path)
	_vbox(Vector3(0, 0.006, 0), Vector3(h * 2, 0.02, 2.4), path)
	_vcyl(Vector3(0, 0.01, 0), 3.2, 3.2, 0.02, path, 24)
	# Raked gravel lines.
	for i in range(-18, 19, 2):
		if absi(i) > 2:
			_vbox(Vector3(i, 0.003, -10.5), Vector3(0.05, 0.01, 15.0), stone)
			_vbox(Vector3(i, 0.003, 10.5), Vector3(0.05, 0.01, 15.0), stone)

	# Walls: stone base, white plaster, dark tiled cap.
	var walls := [
		[Vector3(0, 0, -h - 0.5), Vector3(h * 2 + 2, 0, 1.0)],
		[Vector3(0, 0, h + 0.5), Vector3(h * 2 + 2, 0, 1.0)],
		[Vector3(h + 0.5, 0, 0), Vector3(1.0, 0, h * 2 + 2)],
		[Vector3(-h - 0.5, 0, 0), Vector3(1.0, 0, h * 2 + 2)],
	]
	for w in walls:
		var pos: Vector3 = w[0]
		var size: Vector3 = w[1]
		_vbox(pos + Vector3(0, 0.5, 0), Vector3(size.x + 0.2, 1.0, size.z + 0.2), stone)
		_vbox(pos + Vector3(0, 0.5 + (wall_height - 1.0) * 0.5 + 0.5, 0), Vector3(size.x, wall_height - 1.0, size.z), plaster)
		_vbox(pos + Vector3(0, wall_height + 0.15, 0), Vector3(size.x + 0.9, 0.3, size.z + 0.9), tile)

	# Gatehouses on each wall (closed doors; enemies "enter" from just inside them).
	for g in [[Vector3(0, 0, -h), 0.0], [Vector3(0, 0, h), 0.0], [Vector3(h, 0, 0), 90.0], [Vector3(-h, 0, 0), 90.0]]:
		_gate(g[0], g[1], wood, lacquer, tile)

	# Stone lanterns (toro).
	for p in _lantern_positions():
		_vbox(p + Vector3(0, 0.15, 0), Vector3(0.9, 0.3, 0.9), stone)
		_vcyl(p + Vector3(0, 0.75, 0), 0.16, 0.2, 0.9, stone, 8)
		_vbox(p + Vector3(0, 1.32, 0), Vector3(0.6, 0.36, 0.6), stone)
		_vcyl(p + Vector3(0, 1.62, 0), 0.08, 0.55, 0.3, stone, 4)

	# Sakura tree in the corner.
	var t := _tree_position()
	_vcyl(t + Vector3(0, 1.6, 0), 0.25, 0.42, 3.2, bark, 8)
	for offset in [Vector3(0, 3.6, 0), Vector3(1.2, 3.3, 0.4), Vector3(-0.9, 3.4, 0.9), Vector3(0.4, 3.9, -1.0), Vector3(-0.6, 3.0, -0.6)]:
		var leaf := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.3
		s.height = 2.0
		leaf.mesh = s
		leaf.material_override = blossom
		leaf.position = t + offset
		_visual_root.add_child(leaf)

	# Weapon racks (decor + small obstacles).
	for p in _rack_positions():
		_vbox(p + Vector3(0, 0.6, 0), Vector3(2.0, 0.08, 0.3), wood)
		_vbox(p + Vector3(-0.9, 0.6, 0), Vector3(0.1, 1.2, 0.4), wood)
		_vbox(p + Vector3(0.9, 0.6, 0), Vector3(0.1, 1.2, 0.4), wood)

	# Castle keep beyond the north wall (backdrop only, no collision).
	var keep := Vector3(0, 0, -h - 22.0)
	_vbox(keep + Vector3(0, 3.0, 0), Vector3(30, 6, 22), stone)
	var tiers := [[Vector3(0, 9.0, 0), Vector3(20, 6, 15)], [Vector3(0, 15.0, 0), Vector3(14, 5, 10)], [Vector3(0, 20.0, 0), Vector3(9, 4, 7)]]
	for tier in tiers:
		_vbox(keep + tier[0], tier[1], plaster)
		_roof(keep + tier[0] + Vector3(0, tier[1].y * 0.5 + 0.6, 0), tier[1].x + 4.0, tier[1].z + 4.0, tile, 1.4)
	_vbox(keep + Vector3(0, 23.6, 0), Vector3(1.0, 1.2, 4.0), tile)


func _gate(pos: Vector3, yaw: float, wood: Material, lacquer: Material, tile: Material) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	_visual_root.add_child(root)
	var saved := _visual_root
	_visual_root = root
	_vbox(Vector3(-2.2, 2.4, 0), Vector3(0.45, 4.8, 0.45), lacquer)
	_vbox(Vector3(2.2, 2.4, 0), Vector3(0.45, 4.8, 0.45), lacquer)
	_vbox(Vector3(0, 4.6, 0), Vector3(5.6, 0.4, 0.5), lacquer)
	_vbox(Vector3(0, 1.9, 0), Vector3(4.0, 3.8, 1.15), wood)
	_roof(Vector3(0, 5.4, 0), 7.0, 2.6, tile, 1.0)
	_visual_root = saved
