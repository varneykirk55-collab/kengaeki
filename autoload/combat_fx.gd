extends Node
## Combat presentation helpers: hit-stop, slow motion, camera shake requests and
## lightweight particle effects (sparks, impacts, dust). Purely cosmetic; hit
## detection and damage never depend on anything in here.

signal camera_shake_requested(amount: float)

## Set false to disable time-scale effects (used by automated tests and accessibility).
var time_effects_enabled := true

var _time_effects: Dictionary = {}  # id -> {scale, until_msec}
var _next_effect_id := 0
var _spark_material: StandardMaterial3D
var _impact_material: StandardMaterial3D
var _dust_material: StandardMaterial3D
var _spark_mesh: BoxMesh
var _droplet_mesh: SphereMesh
var _dust_mesh: SphereMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spark_material = _make_material(Color(1.0, 0.78, 0.38), true)
	_impact_material = _make_material(Color(0.42, 0.04, 0.04), false)
	_dust_material = _make_material(Color(0.62, 0.56, 0.46, 0.55), false)
	_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.015, 0.015, 0.09)
	_spark_mesh.material = _spark_material
	_droplet_mesh = SphereMesh.new()
	_droplet_mesh.radius = 0.025
	_droplet_mesh.height = 0.05
	_droplet_mesh.radial_segments = 6
	_droplet_mesh.rings = 3
	_droplet_mesh.material = _impact_material
	_dust_mesh = SphereMesh.new()
	_dust_mesh.radius = 0.12
	_dust_mesh.height = 0.24
	_dust_mesh.radial_segments = 8
	_dust_mesh.rings = 4
	_dust_mesh.material = _dust_material


func _make_material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _process(_delta: float) -> void:
	if _time_effects.is_empty():
		return
	var now := Time.get_ticks_msec()
	var scale := 1.0
	for id in _time_effects.keys():
		var e: Dictionary = _time_effects[id]
		if now >= e.until:
			_time_effects.erase(id)
		else:
			scale = minf(scale, e.scale)
	Engine.time_scale = scale


## Briefly freezes the action to emphasise an impact (duration in real seconds).
func hitstop(duration: float, scale: float = 0.03) -> void:
	_add_time_effect(scale, duration)


## Slows time for a cinematic beat (duration in real seconds).
func slow_motion(scale: float, duration: float) -> void:
	_add_time_effect(scale, duration)


func _add_time_effect(scale: float, duration: float) -> void:
	if not time_effects_enabled or duration <= 0.0:
		return
	_next_effect_id += 1
	_time_effects[_next_effect_id] = {"scale": scale, "until": Time.get_ticks_msec() + int(duration * 1000.0)}
	Engine.time_scale = minf(Engine.time_scale, scale)


func clear_time_effects() -> void:
	_time_effects.clear()
	Engine.time_scale = 1.0


func shake(amount: float) -> void:
	camera_shake_requested.emit(amount)


func spawn_sparks(position: Vector3, normal: Vector3 = Vector3.UP, amount: int = 22, speed: float = 6.0) -> void:
	var p := _make_burst(_spark_mesh, amount, 0.32, position)
	p.direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12, 0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.emitting = true


func spawn_impact(position: Vector3, direction: Vector3) -> void:
	var p := _make_burst(_droplet_mesh, 16, 0.5, position)
	p.direction = direction if direction.length_squared() > 0.001 else Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.emitting = true


func spawn_dust(position: Vector3, amount: int = 8) -> void:
	var p := _make_burst(_dust_mesh, amount, 0.7, position)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.emitting = true


func _make_burst(mesh: Mesh, amount: int, lifetime: float, position: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.local_coords = false
	var scene := get_tree().current_scene
	(scene if scene else self).add_child(p)
	p.global_position = position
	get_tree().create_timer(lifetime + 0.5, false).timeout.connect(p.queue_free)
	return p
