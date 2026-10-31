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
	var path := args[0] if args.size() > 0 else "res://environment/courtyard/scenes/castle_courtyard.tscn"
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
	if arena is CourtyardArena:
		_blueprint_checks(arena, map, space, spawns)
	print("==== courtyard check: %s ====" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)


func _model_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in _all(n):
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var gt := (n as Node3D).global_transform.affine_inverse() * mi.global_transform
			var ab := gt * mi.get_aabb()
			out = ab if first else out.merge(ab)
			first = false
	return out


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


## Extra checks from Agent 1's blueprint (agent3_handoff.md sections 3, 4, 5, 9).
func _blueprint_checks(arena: Node, map: RID, space: PhysicsDirectSpaceState3D, spawns: Array) -> void:
	# Combat area x/z -20..20 has no colliders above the ground.
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(40, 3.9, 40)
	q.shape = b
	q.transform = Transform3D(Basis(), Vector3(0, 2.05, 0))
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 8)
	check(hits.is_empty(), "combat area 40x40 clear of colliders (%d hits)" % hits.size())
	# Spawns: clear 3.5 m line toward the origin (enter state walks inward).
	for p in spawns:
		var from: Vector3 = p.global_position + Vector3.UP * 0.9
		var dir := (Vector3(0, from.y, 0) - from).normalized()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 3.5, 1))
		check(hit.is_empty(), "%s: clear 3.5 m toward origin" % p.name)
	# Bridges navigable, pond basin not.
	for item in [["arch bridge deck", Vector3(31, 0.7, 0)], ["slab bridge deck", Vector3(26, 0.0, 0)]]:
		var cp := NavigationServer3D.map_get_closest_point(map, item[1])
		var flat := Vector2(cp.x - item[1].x, cp.z - item[1].z).length()
		check(flat < 0.35 and absf(cp.y - item[1].y) < 0.6, "%s on navmesh (closest %s; navmesh sits up to ~0.5 m above colliders at cell_height 0.25)" % [item[0], cp])
	var basin := Vector3(29.0, -1.2, 2.5)
	var cpb := NavigationServer3D.map_get_closest_point(map, basin)
	check(cpb.y > -0.6, "pond basin not navigable (closest navmesh point %s)" % cpb)
	var high := 0
	for v in arena.get_node(^"NavigationRegion3D").navigation_mesh.get_vertices():
		if v.y > 2.0:
			high += 1
			if high <= 20:
				print("  INFO  high navmesh vertex %s" % v)
	check(high == 0, "no navmesh on roofs or wall tops (vertices above y=2 m: %d)" % high)
	for item in [["main hall roof", Vector3(0, 9, -39)], ["barracks roof", Vector3(-36, 6, 0)], ["kura roof", Vector3(-31, 7, -36)],
			["north wall top", Vector3(0, 5, -46)], ["east wall top", Vector3(40, 5, 0)], ["gate roof", Vector3(0, 10, 34)]]:
		var cp := NavigationServer3D.map_get_closest_point(map, item[1])
		check(cp.y < 2.0, "%s not walkable (closest navmesh point %s)" % [item[0], cp])
	# Arch bridge: the route between its two ends goes over the deck (BJORN's arch, crown ~0.7 m;
	# a route through the pond basin would dip below 0).
	var an := NavigationServer3D.map_get_closest_point(map, Vector3(31, 0, -7.5))
	var asn := NavigationServer3D.map_get_closest_point(map, Vector3(31, 0, 7.5))
	var arch := NavigationServer3D.map_get_path(map, an, asn, true)
	var top := -INF
	var low := INF
	var length := 0.0
	for i in arch.size():
		top = maxf(top, arch[i].y)
		low = minf(low, arch[i].y)
		if i > 0:
			length += arch[i].distance_to(arch[i - 1])
	check(arch.size() > 0 and top > 0.5 and low > -0.3 and length < 18.0, "arch bridge crossable end to end over the deck (path y %.2f..%.2f, length %.1f m)" % [low, top, length])
	# Arch rails: top about 1.0 m above the walking surface at each point (addendum).
	for z in [0.0, -3.0, 3.0, -5.5, 5.5]:
		for x in [29.725, 32.275]:
			var rail := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 4, z), Vector3(x, -1, z), 1))
			var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(31, 4, z), Vector3(31, -1, z), 1))
			var ok := not rail.is_empty() and not deck.is_empty()
			var dh: float = (rail.position.y - deck.position.y) if ok else -1.0
			check(ok and dh > 0.85 and dh < 1.15, "arch rail x=%.2f z=%.1f top %.2f m above deck surface" % [x, z, dh])
	# Gate closed (blocking); keep has no collision.
	var gate := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 26), Vector3(0, 1, 42), 1))
	# Collider fitted to BJORN's gate base (courtyard face at z = 34 - 3.32 = 30.68; DEVIATIONS #20).
	check(not gate.is_empty() and absf(gate.position.z - 30.68) < 0.15, "main gate closed: blocking collider at z %s" % (gate.position.z if not gate.is_empty() else "none"))
	var kq := PhysicsShapeQueryParameters3D.new()
	var kb := BoxShape3D.new()
	kb.size = Vector3(30, 28, 22)
	kq.shape = kb
	kq.collision_mask = 0xFFFFFFFF
	var keep := arena.find_child("KEEP", true, false) as Node3D
	if keep:
		kq.transform = Transform3D(Basis(), keep.global_position + Vector3(0, 14.5, 0))
		check(space.intersect_shape(kq, 4).is_empty(), "castle keep is backdrop only (no colliders in its volume)")
	else:
		check(false, "castle keep instance found")
	# Sun: late afternoon, ~35 deg up, from the south-west.
	var sun := arena.get_node(^"Sun") as DirectionalLight3D
	var d := -sun.global_basis.z
	var elev := rad_to_deg(asin(-d.y))
	check(absf(elev - 35.0) < 1.0 and d.x > 0.5 and d.z < -0.5, "sun ~35 deg elevation from the SW (light dir %s, elevation %.1f)" % [d, elev])
	# Delivered GLBs: every instance of a prop whose model file exists shows the model (and only then).
	var lanterns := 0
	var with_model := 0
	for n in _all(arena):
		if n is CourtyardProp and String(n.scene_file_path).ends_with("stone_lantern_toro_2m.tscn"):
			lanterns += 1
			if n.has_model:
				with_model += 1
				var m := n.get_node(^"Model") as Node3D
				var ab := _model_aabb(m)
				check(absf(ab.size.y - 2.0) < 0.1 and absf(ab.position.y) < 0.05 and ab.size.x < 1.2 and ab.size.z < 1.2,
					"%s: lantern model ~2 m, base at origin (aabb %s)" % [n.name, ab])
	check(lanterns == 10 and with_model == lanterns, "all %d lanterns use the real GLB (%d with model)" % [lanterns, with_model])
	_model_checks(arena)
	_camera_clearance(arena, space, spawns)
	# Routes that must exist.
	for pair in [["pond north -> south", Vector3(31, 0, -9), Vector3(31, 0, 9)],
			["gate forecourt -> hall forecourt", Vector3(0, 0, 25), Vector3(0, 0, -25)],
			["barracks lane -> kura yard", Vector3(-26, 0, 0), Vector3(-26, 0, -40)]]:
		var a := NavigationServer3D.map_get_closest_point(map, pair[1])
		var c := NavigationServer3D.map_get_closest_point(map, pair[2])
		var route := NavigationServer3D.map_get_path(map, a, c, true)
		check(route.size() > 0 and route[route.size() - 1].distance_to(c) < 0.6 and a.distance_to(pair[1]) < 1.0 and c.distance_to(pair[2]) < 1.0,
			"nav route %s (%d points)" % [pair[0], route.size()])


## Delivered GLBs (BJORN's library): per asset, every instance shows the model, its bounding box is
## within 10% of Bill's authored size per axis (before yaw) and sits on its base (plus model_offset);
## wall modules all share one imported mesh (instanced, not duplicated).
func _model_checks(arena: Node) -> void:
	var per_scene := {}
	for n in _all(arena):
		if n is CourtyardProp and n.authored_size != Vector3.ZERO:
			var key := String(n.scene_file_path).get_file().get_basename()
			if not per_scene.has(key):
				per_scene[key] = []
			per_scene[key].append(n)
	for key in per_scene:
		var nodes: Array = per_scene[key]
		var first: CourtyardProp = nodes[0]
		if not ResourceLoader.exists(first.model_path):
			continue
		var shown := 0
		for n in nodes:
			if n.has_model:
				shown += 1
		check(shown == nodes.size(), "%s: real GLB shown on %d/%d instances (%s)" % [key, shown, nodes.size(), first.model_path.get_file()])
		if shown == 0:
			continue
		var ab := _holder_aabb(first)
		var want: Vector3 = first.authored_size
		var dev := (ab.size - want) / want * 100.0
		check(absf(dev.x) <= 10.0 and absf(dev.y) <= 10.0 and absf(dev.z) <= 10.0,
			"%s: model %.2f x %.2f x %.2f m vs Bill %.2f x %.2f x %.2f m (%+.1f%% %+.1f%% %+.1f%%)" % [key, ab.size.x, ab.size.y, ab.size.z, want.x, want.y, want.z, dev.x, dev.y, dev.z])
		check(absf(ab.position.y - first.model_offset.y) < 0.05 and absf(ab.get_center().x) < 0.5 and absf(ab.get_center().z) < 0.5,
			"%s: model base at y %.2f (offset %.2f), footprint centred (%.2f, %.2f)" % [key, ab.position.y, first.model_offset.y, ab.get_center().x, ab.get_center().z])
	if per_scene.has("wall_segment_4m"):
		var walls: Array = per_scene["wall_segment_4m"]
		var meshes := {}
		for n in walls:
			if n.has_model:
				for c in _all(n.get_node(^"Model")):
					if c is MeshInstance3D:
						meshes[(c as MeshInstance3D).mesh.get_instance_id()] = true
		check(walls.size() == 78 and meshes.size() == 1, "wall modules: %d instances (68 Bill + 10 fillers) share %d imported mesh resource(s)" % [walls.size(), meshes.size()])


## AABB of a prop's loaded model in the prop's own frame (graybox excluded).
func _holder_aabb(prop: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in _all(prop.get_node(^"Model")):
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var ab := (prop.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			out = ab if first else out.merge(ab)
			first = false
	return out


## Third-person camera clearance (scripts/camera/camera_controller.gd: SpringArm3D, sphere
## probe radius 0.25, follow height 1.55 m, pitch -12 deg, distance 4.2, min 2.2, mask 1).
## From each marker and a few tight spots, sweep the probe sphere backwards along the arm in 8
## yaw directions and require at least the arm's minimum length (2.2 m) to be free.
func _camera_clearance(arena: Node, space: PhysicsDirectSpaceState3D, spawns: Array) -> void:
	const RADIUS := 0.25
	const FOLLOW_H := 1.55
	const PITCH := 12.0
	const MIN_ARM := 2.2
	const ARM := 4.2
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	var pts := {}
	pts["PlayerStart"] = (arena.get_node(^"PlayerStart") as Node3D).global_position
	for p in spawns:
		pts[p.name] = p.global_position
	pts["centre"] = Vector3.ZERO
	pts["gate interior"] = Vector3(0, 0, 27.5)
	pts["hall forecourt"] = Vector3(0, 0, -30)
	pts["arch bridge crown"] = Vector3(31, 0.704, 0)
	pts["barracks lane"] = Vector3(-30, 0, 0)
	for key in pts:
		var origin: Vector3 = pts[key] + Vector3.UP * FOLLOW_H
		var worst := INF
		var full := 0
		for i in 8:
			var yaw := deg_to_rad(45.0 * i)
			var dir := Vector3(sin(yaw) * cos(deg_to_rad(PITCH)), sin(deg_to_rad(PITCH)), cos(yaw) * cos(deg_to_rad(PITCH)))
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sphere
			q.transform = Transform3D(Basis(), origin)
			q.motion = dir * ARM
			q.collision_mask = 1
			var frac := space.cast_motion(q)
			var free := ARM * frac[0]
			worst = minf(worst, free)
			if frac[0] >= 1.0:
				full += 1
		check(worst >= MIN_ARM, "camera clearance at %s: arm free >= %.1f m in all 8 directions (worst %.2f m, full %.1f m in %d/8)" % [key, MIN_ARM, worst, ARM, full])
