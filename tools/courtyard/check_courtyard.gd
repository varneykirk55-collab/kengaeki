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
	# Slab bridge (batch 3, BJORN's deck2m, deck top at y ~0): the route between its two ends goes
	# over the deck, and the rails stand ~0.9 m above it (Bill: 2 rail colliders, 0.9 m).
	var sn := NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, -8))
	var ss := NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, 8))
	var slab := NavigationServer3D.map_get_path(map, sn, ss, true)
	var slow := INF
	var slen := 0.0
	var smaxdx := 0.0
	for i in slab.size():
		slow = minf(slow, slab[i].y)
		if absf(slab[i].z) < 5.0:
			smaxdx = maxf(smaxdx, absf(slab[i].x - 26.0))
		if i > 0:
			slen += slab[i].distance_to(slab[i - 1])
	check(slab.size() > 0 and slow > -0.1 and slen < 18.0 and smaxdx < 1.0, "slab bridge crossable end to end over the deck (path low y %.2f, length %.1f m, max |x-26| over the pond %.2f m)" % [slow, slen, smaxdx])
	for z in [0.0, -3.0, 3.0, -4.8, 4.8]:
		for x in [24.925, 27.075]:
			var rail := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 4, z), Vector3(x, -1, z), 1))
			var deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(26, 4, z), Vector3(26, -1, z), 1))
			var ok := not rail.is_empty() and not deck.is_empty()
			var dh: float = (rail.position.y - deck.position.y) if ok else -1.0
			check(ok and absf(deck.position.y) < 0.02 and dh > 0.8 and dh < 1.0, "slab rail x=%.3f z=%.1f top %.2f m above deck surface (deck y %.3f)" % [x, z, dh, deck.position.y if ok else -9.0])
	# Trees (batch 3): one trunk-only cylinder collider each, none inside the 40 x 40 m combat
	# square or within 2.5 m of a spawn / the player start.
	var trees := 0
	for n in _all(arena):
		if n is CourtyardProp and String(n.scene_file_path).get_file().begins_with("tree_"):
			trees += 1
			var cyl := 0
			for c in _all(n):
				if c is CollisionShape3D and (c as CollisionShape3D).shape is CylinderShape3D:
					cyl += 1
			var tp: Vector3 = n.global_position
			var near := INF
			for p in spawns:
				near = minf(near, Vector2(p.global_position.x - tp.x, p.global_position.z - tp.z).length())
			var ps := (arena.get_node(^"PlayerStart") as Node3D).global_position
			near = minf(near, Vector2(ps.x - tp.x, ps.z - tp.z).length())
			check(cyl == 1 and not (absf(tp.x) < 20.0 and absf(tp.z) < 20.0) and near > 2.5,
				"%s: 1 trunk collider (%d), outside the combat square, nearest spawn %.1f m" % [n.name, cyl, near])
	check(trees == 14, "14 trees placed (%d)" % trees)
	# Gate closed (blocking); keep has no collision.
	var gate := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 26), Vector3(0, 1, 42), 1))
	# Collider fitted to BJORN's wide gate base (courtyard face at z = 34 - 3.84 = 30.16; DEVIATIONS #20, #31).
	check(not gate.is_empty() and absf(gate.position.z - 30.16) < 0.15, "main gate closed: blocking collider at z %s" % (gate.position.z if not gate.is_empty() else "none"))
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
	_small_rock_checks(arena, map)
	_batch4_final_checks(arena, map, space)
	_nav_connectivity_checks(arena, map, space)
	_camera_clearance(arena, space, spawns)
	# Routes that must exist.
	for pair in [["pond north -> south", Vector3(31, 0, -9), Vector3(31, 0, 9)],
			["gate forecourt -> hall forecourt", Vector3(0, 0, 25), Vector3(0, 0, -25)],
			["barracks lane -> kura yard", Vector3(-26, 0, 0), Vector3(-26, 0, -40)],
			["east-north path (sakura / pines)", Vector3(20, 0, -10), Vector3(34, 0, -10)],
			["east-south path (maples)", Vector3(20, 0, 10), Vector3(34, 0, 10)],
			["west path (pine 4 / maple 3)", Vector3(-20, 0, 2), Vector3(-30, 0, 2)],
			["gate forecourt -> sakura lawn west", Vector3(0, 0, 25), Vector3(-20, 0, 25)],
			["gate forecourt -> sakura lawn east", Vector3(0, 0, 25), Vector3(20, 0, 25)]]:
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
		if key.begins_with("tree_"):
			# Trees (DEVIATIONS.md #23): uniform scale to Bill's height, origin at the trunk base,
			# canopy footprint off-centre and no larger than Bill's (+10%).
			check(absf(dev.y) <= 10.0 and dev.x <= 10.0 and dev.z <= 10.0,
				"%s: model %.2f x %.2f x %.2f m vs Bill %.2f x %.2f x %.2f m (height %+.1f%%, footprint %+.1f%% %+.1f%%)" % [key, ab.size.x, ab.size.y, ab.size.z, want.x, want.y, want.z, dev.y, dev.x, dev.z])
			check(absf(ab.position.y - first.model_offset.y) < 0.05 and ab.position.x < 0.0 and ab.end.x > 0.0 and ab.position.z < 0.0 and ab.end.z > 0.0,
				"%s: model base at y %.2f, trunk origin inside the canopy footprint x %.2f..%.2f z %.2f..%.2f" % [key, ab.position.y, ab.position.x, ab.end.x, ab.position.z, ab.end.z])
			var meshes := {}
			for n in nodes:
				for c in _all(n.get_model_lod(0)):
					if c is MeshInstance3D:
						meshes[(c as MeshInstance3D).mesh.get_instance_id()] = true
			check(meshes.size() == 1, "%s: %d instances share %d imported mesh resource(s)" % [key, nodes.size(), meshes.size()])
			_lod_checks(key, nodes)
			continue
		var tol: Vector2 = first.size_tolerance_pct
		check(dev.x >= tol.x and dev.x <= tol.y and dev.y >= tol.x and dev.y <= tol.y and dev.z >= tol.x and dev.z <= tol.y,
			"%s: model %.2f x %.2f x %.2f m vs Bill %.2f x %.2f x %.2f m (%+.1f%% %+.1f%% %+.1f%%, allowed %+.0f..%+.0f%%)" % [key, ab.size.x, ab.size.y, ab.size.z, want.x, want.y, want.z, dev.x, dev.y, dev.z, tol.x, tol.y])
		check(absf(ab.position.y - first.model_offset.y) < 0.05 and absf(ab.get_center().x) < 0.5 and absf(ab.get_center().z) < 0.5,
			"%s: model base at y %.2f (offset %.2f), footprint centred (%.2f, %.2f)" % [key, ab.position.y, first.model_offset.y, ab.get_center().x, ab.get_center().z])
		_lod_checks(key, nodes)
		if key.begins_with("rock_"):
			_rock_collider_check(key, first, ab)
	if per_scene.has("wall_segment_4m"):
		var walls: Array = per_scene["wall_segment_4m"]
		var meshes := {}
		for n in walls:
			if n.has_model:
				for c in _all(n.get_model_lod(0)):
					if c is MeshInstance3D:
						meshes[(c as MeshInstance3D).mesh.get_instance_id()] = true
		check(walls.size() == 78 and meshes.size() == 1, "wall modules: %d instances (68 Bill + 10 fillers) share %d imported mesh resource(s)" % [walls.size(), meshes.size()])


## Hand-made LODs (BJORN's LOD pack): every listed LOD file is instanced on every instance; the
## levels' visibility ranges are contiguous (each begin = the previous end, same fade margin, dithered
## fade); each level's bounding box is within 5% of LOD0's (trees 15%) (same origin, scale, orientation); every
## instance shares one imported mesh per level; levels marked as sharing materials draw with LOD0's
## material (and were imported without their own textures).
func _lod_checks(key: String, nodes: Array) -> void:
	var first: CourtyardProp = nodes[0]
	var want := 0
	for p in first.model_lod_paths:
		if ResourceLoader.exists(p):
			want += 1
	if first.model_lod_paths.size() == 0:
		return
	check(want == first.model_lod_paths.size(), "%s: all %d LOD files exist (%d found)" % [key, first.model_lod_paths.size(), want])
	var lod0_ab := _level_aabb(first, 0)
	var prev_end := -1.0
	for level in want + 1:
		var count := 0
		var meshes := {}
		var ranges := {}
		for n in nodes:
			var lod: Node3D = n.get_model_lod(level)
			if lod == null:
				continue
			count += 1
			for c in _all(lod):
				if c is MeshInstance3D:
					var mi := c as MeshInstance3D
					meshes[mi.mesh.get_instance_id()] = true
					ranges["%.2f/%.2f/%.2f/%.2f/%d" % [mi.visibility_range_begin, mi.visibility_range_begin_margin, mi.visibility_range_end, mi.visibility_range_end_margin, mi.visibility_range_fade_mode]] = true
		check(count == nodes.size() and meshes.size() == 1 and ranges.size() == 1,
			"%s LOD%d: on %d/%d instances, %d shared mesh resource(s), %d distinct range setting(s)" % [key, level, count, nodes.size(), meshes.size(), ranges.size()])
		var lod: Node3D = first.get_model_lod(level)
		if lod == null:
			continue
		var mi0: MeshInstance3D = null
		for c in _all(lod):
			if c is MeshInstance3D:
				mi0 = c
				break
		if mi0 == null:
			continue
		if level > 0:
			var ab := _level_aabb(first, level)
			var d := (ab.size - lod0_ab.size) / lod0_ab.size * 100.0
			# Trees: decimated foliage cards trim the canopy's outer tips (maple -3.7%, sakura -1.7%);
			# the reworked pine lod3k now matches LOD0's bounds (was 12% shallower, DEVIATIONS.md #27),
			# so trees are back to 5% like the architecture (batch 3: 15%).
			var lt := 5.0
			check(absf(d.x) <= lt and absf(d.y) <= lt and absf(d.z) <= lt and ab.get_center().distance_to(lod0_ab.get_center()) < 0.15,
				"%s LOD%d: %.2f x %.2f x %.2f m vs LOD0 %.2f x %.2f x %.2f m (%+.1f%% %+.1f%% %+.1f%%), centre offset %.3f m" % [key, level, ab.size.x, ab.size.y, ab.size.z, lod0_ab.size.x, lod0_ab.size.y, lod0_ab.size.z, d.x, d.y, d.z, ab.get_center().distance_to(lod0_ab.get_center())])
			check(absf(mi0.visibility_range_begin - prev_end) < 0.01 and mi0.visibility_range_begin_margin == first.model_lod_fade and mi0.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
				"%s LOD%d: drawn from %.1f m (previous level ends %.1f m), crossfade %.1f m" % [key, level, mi0.visibility_range_begin, prev_end, mi0.visibility_range_begin_margin])
			var share: bool = first.model_lod_share_materials.size() >= level and first.model_lod_share_materials[level - 1] != 0
			if share:
				var src: MeshInstance3D = null
				for c in _all(first.get_model_lod(0)):
					if c is MeshInstance3D:
						src = c
						break
				# BJORN's reworked LODs (Oct 30, 10:45 PM) reference LOD0's texture files by glTF URI, so
				# the imported material may carry LOD0's texture: allowed, as long as it is LOD0's file.
				var own := mi0.mesh.surface_get_material(0) as BaseMaterial3D
				var lod0_mat := src.get_active_material(0) as BaseMaterial3D if src else null
				var own_tex := "" if own == null or own.albedo_texture == null else own.albedo_texture.resource_path
				var lod0_tex := "" if lod0_mat == null or lod0_mat.albedo_texture == null else lod0_mat.albedo_texture.resource_path
				check(src != null and mi0.get_active_material(0) == src.get_active_material(0) and (own_tex == "" or own_tex == lod0_tex),
					"%s LOD%d: drawn with LOD0's material (imported albedo: %s; LOD0's: %s)" % [key, level, own_tex.get_file() if own_tex != "" else "none", lod0_tex.get_file()])
		prev_end = mi0.visibility_range_end


func _level_aabb(prop: Node3D, level: int) -> AABB:
	var out := AABB()
	var first := true
	var holder := prop.get_node(^"Model") as Node3D
	for c in _all(prop.get_model_lod(level)):
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var ab := (holder.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			out = ab if first else out.merge(ab)
			first = false
	return out


## Batch 4 rocks: one box collider, top within 5% of the model's height, footprint inside the
## model's bounding box (fitted to the stones; the low moss skirt is walk-through).
func _rock_collider_check(key: String, prop: Node3D, ab: AABB) -> void:
	var body := prop.get_node_or_null(^"Collision") as StaticBody3D
	var shapes: Array = []
	if body:
		for c in body.get_children():
			if c is CollisionShape3D:
				shapes.append(c)
	if shapes.size() != 1 or not (shapes[0].shape is BoxShape3D):
		check(false, "%s: one box collider (%d shapes)" % [key, shapes.size()])
		return
	var cs: CollisionShape3D = shapes[0]
	var sz := (cs.shape as BoxShape3D).size
	var lo := cs.position - sz / 2.0
	var hi := cs.position + sz / 2.0
	check(absf(hi.y - ab.end.y) <= 0.05 * ab.size.y and absf(lo.y - ab.position.y) < 0.02 and lo.x >= ab.position.x - 0.01 and hi.x <= ab.end.x + 0.01 and lo.z >= ab.position.z - 0.01 and hi.z <= ab.end.z + 0.01,
		"%s: box collider %.2f x %.2f x %.2f m (top %.2f) inside the model's %.2f x %.2f x %.2f m (top %.2f)" % [key, sz.x, sz.y, sz.z, hi.y, ab.size.x, ab.size.y, ab.size.z, ab.end.y])


## AABB of a prop's loaded model (LOD0 only) in the prop's own frame (graybox excluded).
func _holder_aabb(prop: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in _all(prop.get_model_lod(0)):
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
	pts["slab bridge deck"] = Vector3(26, 0.0, 0)
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


## Batch 4: rock_small_cluster now has a small box collider (Bill had none). Each cluster must be
## walk-around: the navmesh points (reachable from the centre) on a 1.5 m ring around it are connected to each other by short
## paths (< 10 m, i.e. around the rock, not a detour), outside the combat square.
func _small_rock_checks(arena: Node, map: RID) -> void:
	var centre := NavigationServer3D.map_get_closest_point(map, Vector3.ZERO)
	for n in _all(arena):
		if not (n is CourtyardProp and String(n.scene_file_path).get_file().begins_with("rock_small_cluster")):
			continue
		var c: Vector3 = (n as Node3D).global_position
		var ring: Array = []
		for i in 8:
			var a := TAU * i / 8.0
			var q := c + Vector3(cos(a), 0, sin(a)) * 1.5
			var on := NavigationServer3D.map_get_closest_point(map, q)
			if Vector2(on.x - q.x, on.z - q.z).length() < 0.3:
				# Only points reachable from the courtyard (skips navmesh slivers in closed pockets,
				# e.g. inside the SE turret's footprint next to ROCKS9).
				var pc := NavigationServer3D.map_get_path(map, centre, on, true)
				if pc.size() > 0 and pc[pc.size() - 1].distance_to(on) < 0.3:
					ring.append(on)
		var worst := 0.0
		var unreached := 0
		var ok := ring.size() >= 2
		for i in range(1, ring.size()):
			var path := NavigationServer3D.map_get_path(map, ring[0], ring[i], true)
			var ln := 0.0
			for k in range(1, path.size()):
				ln += path[k].distance_to(path[k - 1])
			if path.size() == 0 or path[path.size() - 1].distance_to(ring[i]) > 0.3:
				ok = false
				unreached += 1
			worst = maxf(worst, ln)
		ok = ok and worst < 10.0 and (absf(c.x) > 20.0 or absf(c.z) > 20.0)
		check(ok, "%s at (%.1f, %.1f): walk-around, %d/8 ring points on the reachable navmesh (%d not reached), longest path round it %.1f m" % [n.name, c.x, c.z, ring.size(), unreached, worst])


## Batch 4 final (pond stones, shrubs, wide gate, rock_medium). DEVIATIONS.md #29-#32.
func _batch4_final_checks(arena: Node, map: RID, space: PhysicsDirectSpaceState3D) -> void:
	# Pond stones: 7 placed, each with the real model standing in the water (bottom below the water
	# surface at -0.30, top above the bank at 0: no face coplanar with the water or the ground).
	var stones: Array = []
	for n in _all(arena):
		if n is CourtyardProp and String(n.scene_file_path).get_file().begins_with("pond_edge_stones_2m"):
			stones.append(n)
	var b_count := 0
	for n in stones:
		if String(n.scene_file_path).ends_with("_b.tscn"):
			b_count += 1
		var ab := _holder_aabb(n)
		var top := ab.end.y + (n as Node3D).global_position.y
		var bot := ab.position.y + (n as Node3D).global_position.y
		check(n.has_model and bot < -0.31 and top > 0.05,
			"%s: model in the water and above the bank (y %.2f..%.2f; water -0.30, bank 0.00; no coplanar faces)" % [n.name, bot, top])
	check(stones.size() == 7 and b_count == 3, "pond stones: %d placed (%d use the _b file)" % [stones.size(), b_count])
	# One box collider per stone (Collision/PondStones), clear of the bridges' colliders, the paths
	# and the bridge ends; no navmesh on top of a stone.
	var body := arena.get_node_or_null(^"Collision/PondStones") as StaticBody3D
	var boxes: Array = []
	if body:
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				boxes.append(c)
	check(boxes.size() == 7, "pond stones: %d box colliders (Collision/PondStones)" % boxes.size())
	var bridges := arena.get_node_or_null(^"Collision/Bridges") as StaticBody3D
	for c in boxes:
		var cs := c as CollisionShape3D
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.collision_mask = 1
		q.exclude = [body.get_rid()]
		var hit_bridge := 0
		for h in space.intersect_shape(q, 32):
			if h.collider == bridges:
				hit_bridge += 1
		var top := cs.global_position + Vector3.UP * (cs.shape as BoxShape3D).size.y / 2.0
		var cp := NavigationServer3D.map_get_closest_point(map, top)
		var flat := Vector2(cp.x - top.x, cp.z - top.z).length()
		check(hit_bridge == 0 and flat > 0.3,
			"%s collider: clear of the bridge colliders (%d overlaps), no navmesh on the stone (nearest %.2f m away)" % [cs.name, hit_bridge, flat])
	# Bridge ends and the bridge spur paths beyond the pond edge (P5 x 31 w 2.4, P6 x 26 w 2.0):
	# no pond stone collider in their footprint.
	for item in [["slab bridge ends + path P6", Vector3(26, 0.5, 0), Vector3(2.0, 1.0, 20.0)],
			["arch bridge ends + path P5", Vector3(31, 0.5, 0), Vector3(2.4, 1.0, 20.0)]]:
		for zc in [-7.5, 7.5]:
			var q := PhysicsShapeQueryParameters3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(item[2].x, 1.0, 5.0)
			q.shape = bx
			q.transform = Transform3D(Basis(), Vector3(item[1].x, 0.5, zc))
			q.collision_mask = 1
			var n_st := 0
			for h in space.intersect_shape(q, 32):
				if h.collider == body:
					n_st += 1
			check(n_st == 0, "%s (z %.1f..%.1f): no pond stone collider (%d)" % [item[0], zc - 2.5, zc + 2.5, n_st])
	# Shrubs: 12 placed, real model, Bill's "no collision", faded beyond ~45 m.
	var shrubs := 0
	var sb := 0
	var shrub_cols := 0
	var vis_ok := true
	for n in _all(arena):
		if n is CourtyardProp and String(n.scene_file_path).get_file().begins_with("shrub_azalea"):
			shrubs += 1
			if String(n.scene_file_path).ends_with("_b.tscn"):
				sb += 1
			for c in _all(n):
				if c is CollisionShape3D:
					shrub_cols += 1
				if c is MeshInstance3D and (c as MeshInstance3D).get_parent() != n.get_node(^"Graybox"):
					vis_ok = vis_ok and absf((c as MeshInstance3D).visibility_range_end - 45.0) < 0.01
			check(n.has_model, "%s: real shrub model shown" % n.name)
	check(shrubs == 12 and sb == 6 and shrub_cols == 0 and vis_ok,
		"shrubs: %d placed (%d _b), %d collision shapes (Bill: none), faded beyond 45 m: %s" % [shrubs, sb, shrub_cols, vis_ok])
	# rock_medium: 8 placed, outside the combat square (collider fit is checked in _model_checks).
	var rm := 0
	var rm_out := true
	for n in _all(arena):
		if n is CourtyardProp and String(n.scene_file_path).get_file() == "rock_medium.tscn":
			rm += 1
			var p := (n as Node3D).global_position
			rm_out = rm_out and (absf(p.x) > 20.0 or absf(p.z) > 20.0) and n.has_model
	check(rm == 8 and rm_out, "rock_medium: %d boulders with the real model, all outside the combat square" % rm)
	# Wide gate: real model, gate-side fillers end inside its shell (x 6.0 from the centre).
	var gate := arena.find_child("GATE", true, false) as CourtyardProp
	check(gate != null and gate.has_model and gate.model_path.ends_with("main_gate_yaguramon_wide.glb"), "gate uses main_gate_yaguramon_wide.glb")
	for nm in ["WS07_FillB", "WS08_FillA"]:
		var f := arena.find_child(nm, true, false) as Node3D
		check(f != null, "gate filler %s present" % nm)
		if f:
			var inner := absf(f.global_position.x) - 2.0 * absf(f.scale.x)
			check(absf(inner - 6.0) < 0.02 and f.global_position.z == 34.0, "%s: gate filler from the wall end (x 8) to x %.2f (inside the gate shell)" % [nm, inner])
	_gate_seal_checks(arena, map, space)


## Bill (Oct 30, 10:58 PM EDT): the gate-side fillers must close the wall line with no gaps, as
## blocking colliders in nav_source. The fillers are visual modules; their footprint is covered by
## the S wall-run boxes (which run 0.1 m into the gate box) and the closed-gate box, all children of
## Collision (group nav_source). Checked here: every point of each filler's volume is inside a
## nav_source collider, a player capsule can't pass between the gate and the wall on either side,
## and the navmesh does not reach the outside.
func _gate_seal_checks(arena: Node, map: RID, space: PhysicsDirectSpaceState3D) -> void:
	var col_root := arena.get_node_or_null(^"Collision")
	check(col_root != null and col_root.is_in_group("nav_source"), "gate seal: Collision root is in group nav_source")
	for nm in ["WS07_FillB", "WS08_FillA"]:
		var f := arena.find_child(nm, true, false) as Node3D
		if f == null:
			check(false, "gate seal: filler %s present" % nm)
			continue
		var cx := f.global_position.x
		var half := 2.0 * absf(f.scale.x)
		var miss := 0
		var not_nav := 0
		var total := 0
		for ix in 11:
			var x := cx - half + 0.02 + (2.0 * half - 0.04) * ix / 10.0
			for iz in 5:
				var z := 34.0 - 0.7 + 1.4 * iz / 4.0
				for iy in 6:
					var y := 0.05 + 4.6 * iy / 5.0
					var pq := PhysicsPointQueryParameters3D.new()
					pq.position = Vector3(x, y, z)
					pq.collision_mask = 1
					var hits := space.intersect_point(pq, 4)
					total += 1
					if hits.is_empty():
						miss += 1
					else:
						var in_nav := false
						for h in hits:
							var c: Object = h.collider
							var p: Node = c as Node
							while p != null:
								if p.is_in_group("nav_source"):
									in_nav = true
									break
								p = p.get_parent()
						if not in_nav:
							not_nav += 1
		check(miss == 0 and not_nav == 0, "gate seal: %s volume (x %.2f..%.2f, z 33.3..34.7, y 0.05..4.65) fully inside nav_source colliders (%d/%d points, %d outside nav_source)" % [nm, cx - half, cx + half, total - miss, total, not_nav])
	# Player capsule (r 0.38, h 1.8, scenes/characters/player.tscn) swept from the courtyard (z 27)
	# to outside the wall (z 41) at every x across the gate side, filler and wall end.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	for side in [-1.0, 1.0]:
		var passed := 0
		var n := 0
		var worst := 0.0
		for i in 41:
			var x: float = side * (5.0 + 0.1 * i)   # |x| 5.0 .. 9.0
			for y in [0.92, 2.5, 4.0]:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cap
				q.transform = Transform3D(Basis(), Vector3(x, y, 27.0))
				q.motion = Vector3(0, 0, 14.0)
				q.collision_mask = 1
				var frac := space.cast_motion(q)
				n += 1
				worst = maxf(worst, 27.0 + 14.0 * frac[0])
				if frac[0] >= 1.0:
					passed += 1
		check(passed == 0, "gate seal %s: player capsule blocked between gate and wall at all %d sweeps (|x| 5..9, y 0.92/2.5/4.0; furthest reach z %.2f, wall inner face 33.25)" % ["west" if side < 0 else "east", n, worst])
		# Navmesh: the closest navmesh point to spots just outside the wall stays inside, and a path
		# from inside to outside ends inside the wall line.
		var leak := 0
		var far := 0.0
		for i in 9:
			var x: float = side * (5.0 + 0.5 * i)
			var cp := NavigationServer3D.map_get_closest_point(map, Vector3(x, 0, 38.5))
			far = maxf(far, cp.z)
			if cp.z > 33.0:
				leak += 1
				print("  INFO  gate seal: closest navmesh to (%.1f, 0, 38.5) is %s" % [x, cp])
			var a := NavigationServer3D.map_get_closest_point(map, Vector3(x, 0, 27))
			var route := NavigationServer3D.map_get_path(map, a, Vector3(x, 0, 38.5), true)
			if route.size() > 0 and route[route.size() - 1].z > 33.0:
				leak += 1
				print("  INFO  gate seal: path to (%.1f, 0, 38.5) ends at %s" % [x, route[route.size() - 1]])
		check(leak == 0, "gate seal %s: no navmesh through the gate/wall seam (closest navmesh to outside points reaches z %.2f, paths end inside)" % ["west" if side < 0 else "east", far])


## Every navmesh polygon must belong to the walkable region around the combat centre: no islands
## inside collider volumes (Recast voxelises surfaces, so the ground inside turrets, the hall,
## barracks, kura or large rocks can bake when the bake box clips their roofs) and none on top of low
## colliders (rock_medium). Intentional exceptions: none. DEVIATIONS.md #34.
func _nav_connectivity_checks(arena: Node, map: RID, space: PhysicsDirectSpaceState3D) -> void:
	var nm: NavigationMesh = (arena.get_node(^"NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	var v := nm.get_vertices()
	var n := nm.get_polygon_count()
	var parent: Array = range(n)
	var by_edge := {}
	var cents: Array[Vector3] = []
	for i in n:
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly.size():
			var a: int = poly[k]
			var b: int = poly[(k + 1) % poly.size()]
			c += v[a]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if by_edge.has(key):
				parent[_uf_find(parent, i)] = _uf_find(parent, by_edge[key])
			else:
				by_edge[key] = i
		cents.append(c / poly.size())
	var sizes := {}
	for i in n:
		var r := _uf_find(parent, i)
		sizes[r] = sizes.get(r, 0) + 1
	var centre_poly := 0
	for i in n:
		if cents[i].distance_squared_to(Vector3.ZERO) < cents[centre_poly].distance_squared_to(Vector3.ZERO):
			centre_poly = i
	var main_root := _uf_find(parent, centre_poly)
	var stray := n - int(sizes.get(main_root, 0))
	check(sizes.size() == 1 and stray == 0, "navmesh connectivity: %d polygons in %d edge-connected region(s); %d outside the combat-centre region (allowed exceptions: none)" % [n, sizes.size(), stray])
	# Same thing through the NavigationServer: a path from the combat centre reaches every polygon.
	var start := NavigationServer3D.map_get_closest_point(map, Vector3.ZERO)
	var unreached := 0
	for i in n:
		var target := NavigationServer3D.map_get_closest_point(map, cents[i])
		var route := NavigationServer3D.map_get_path(map, start, target, true)
		var end: Vector3 = route[route.size() - 1] if route.size() > 0 else start
		if Vector2(end.x - target.x, end.z - target.z).length() > 0.3:
			unreached += 1
			if unreached <= 5:
				print("  INFO  navmesh polygon %d at %s not reached from the centre (path ends %s)" % [i, cents[i], end])
	check(unreached == 0, "navmesh connectivity: a path from the combat centre reaches all %d polygon centres (%d unreached)" % [n, unreached])
	# No polygon inside a collider volume (centroid probed 5 cm above the navmesh, which sits ~0.4 m
	# above the ground it was baked on).
	var inside := 0
	for i in n:
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = cents[i] + Vector3.UP * 0.05
		pq.collision_mask = 1
		var hits := space.intersect_point(pq, 4)
		if not hits.is_empty():
			inside += 1
			if inside <= 5:
				print("  INFO  navmesh polygon %d at %s is inside %s" % [i, cents[i], (hits[0].collider as Node).name])
	check(inside == 0, "navmesh connectivity: no polygon centre inside a collider volume (%d inside)" % inside)
	# The islands found on Oct 30 (11:15 PM EDT) are gone: interiors of the 4 turrets, hall, barracks,
	# kura, ROCKL1/ROCKL3, and the tops of ROCKM1/2/3/6/7/8.
	var spots := {"turret NW": Vector3(-38.3, 0, -44.3), "turret NE": Vector3(38.3, 0, -44.3),
		"turret SW": Vector3(-38.3, 0, 32.3), "turret SE": Vector3(38.3, 0, 32.3),
		"hall": Vector3(0, 0, -39), "barracks": Vector3(-36, 0, 0), "kura": Vector3(-31, 0, -36)}
	for key in spots:
		var cp := NavigationServer3D.map_get_closest_point(map, spots[key])
		var d := Vector2(cp.x - spots[key].x, cp.z - spots[key].z).length()
		check(d > 1.0, "navmesh connectivity: no navmesh inside %s (nearest %.2f m from its interior)" % [key, d])


func _uf_find(p: Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i
