extends SceneTree
## Headless structural check for the courtyard arena (NOT a visual or gameplay test).
## Usage: godot --headless --path . -s res://tools/courtyard/check_courtyard.gd [-- arena_scene_path]
## Bakes the navmesh, then checks markers, ground under markers, and nav paths from every
## spawn point to the player start and to the arena centre. Exit code 0 = all checks pass.

var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://environment/courtyard/scenes/courtyard_arena.tscn"
	print("==== courtyard check: %s ====" % path)
	var packed := load(path) as PackedScene
	check(packed != null, "scene loads")
	if packed == null:
		quit(1)
		return
	var arena := packed.instantiate()
	root.add_child(arena)
	_run.call_deferred(arena)


func _run(arena: Node) -> void:
	for i in 10:
		await physics_frame
	check(arena is Arena, "root is an Arena (main.gd interface)")
	var ps := arena.get_node_or_null(^"PlayerStart") as Node3D
	check(ps != null, "PlayerStart present")
	var spawns: Array = arena.get_spawn_points()
	check(spawns.size() >= 6, "spawn points: %d (>= 6)" % spawns.size())
	var nav: NavigationRegion3D = arena.get_node(^"NavigationRegion3D")
	var nm := nav.navigation_mesh
	var polys := nm.get_polygon_count() if nm else 0
	check(polys > 0, "navmesh baked: %d polygons, %d vertices" % [polys, nm.get_vertices().size() if nm else 0])
	for i in 5:
		await physics_frame
	var map := nav.get_navigation_map()
	NavigationServer3D.map_force_update(map)
	var space := (arena as Node3D).get_world_3d().direct_space_state
	var shapes := 0
	var bodies := 0
	var props := 0
	var with_model := 0
	for n in _all(arena):
		if n is CollisionShape3D:
			shapes += 1
		elif n is StaticBody3D:
			bodies += 1
		if n is CourtyardProp:
			props += 1
			if n.has_model:
				with_model += 1
	print("  INFO  static bodies %d, collision shapes %d, module/prop instances %d (real model loaded: %d)" % [bodies, shapes, props, with_model])
	var targets := {"player start": ps.global_position, "centre": Vector3(0, 0, 0)}
	var pts: Array = [ps] + spawns
	for p in pts:
		var pos: Vector3 = p.global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0, 1)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and absf(hit.position.y - 0.0) < 0.3, "%s: ground under marker" % p.name)
		var blocked := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45
		cap.height = 1.75
		blocked.shape = cap
		blocked.transform = Transform3D(Basis(), pos + Vector3.UP * 0.95)
		blocked.collision_mask = 1
		check(space.intersect_shape(blocked, 4).is_empty(), "%s: marker clear of world collision" % p.name)
	for p in spawns:
		for tname in targets:
			var from := NavigationServer3D.map_get_closest_point(map, p.global_position)
			var to := NavigationServer3D.map_get_closest_point(map, targets[tname])
			var route := NavigationServer3D.map_get_path(map, from, to, true)
			var ok := route.size() > 0 and route[route.size() - 1].distance_to(to) < 0.6 and from.distance_to(p.global_position) < 1.0
			check(ok, "nav path %s -> %s (%d points)" % [p.name, tname, route.size()])
	print("==== courtyard check: %s ====" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
