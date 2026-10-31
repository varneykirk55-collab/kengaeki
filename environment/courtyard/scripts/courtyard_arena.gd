class_name CourtyardArena
extends Arena
## Courtyard version of the gameplay arena. Keeps the Arena interface the game uses
## (PlayerStart, SpawnPoints, NavigationRegion3D, get_spawn_points) and only makes the
## navmesh bake bounds configurable so a different blueprint footprint does not need
## arena.gd edits. Bakes from StaticBody3D collision on layer 1 in the "nav_source" group.

## Walkable area to bake (keep it inside the walls so the grass outside is excluded).
@export var nav_bake_aabb: AABB = AABB(Vector3(-21, -1, -21), Vector3(42, 6, 42))
## After baking, drop navmesh polygons that lie entirely above this height. Tops of tall
## colliders that fit inside the bake box (e.g. 1.8 m rock formations) otherwise become small
## unreachable islands the enemy nav could snap to. The arch bridge deck bakes at ~1.4 m.
## Set to a negative value to disable.
@export var nav_max_walk_height: float = 1.8
## After baking, keep only the navmesh polygons connected (by shared edges) to the polygon nearest
## this point (the combat centre). Recast voxelises collider surfaces, not volumes, so the ground
## inside tall boxes whose roof the bake box clips (turrets, hall, barracks, kura, large rocks)
## and the tops of ~1 m colliders (rock_medium) otherwise bake as small unreachable islands that
## enemy nav could snap to. DEVIATIONS.md #34.
@export var nav_cull_islands: bool = true
@export var nav_main_seed: Vector3 = Vector3.ZERO


func bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_source"
	nm.filter_baking_aabb = nav_bake_aabb
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	if nav_max_walk_height >= 0.0:
		_prune_high_polygons(nm, nav_max_walk_height)
	if nav_cull_islands:
		_prune_disconnected(nm, nav_main_seed)


func _prune_disconnected(nm: NavigationMesh, seed_point: Vector3) -> void:
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	if n == 0:
		return
	# Polygons sharing an edge (same two vertex indices) are connected.
	var by_edge := {}
	var adj: Array = []
	for i in n:
		adj.append([])
	var start := 0
	var best := INF
	for i in n:
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly.size():
			var a: int = poly[k]
			var b: int = poly[(k + 1) % poly.size()]
			c += verts[a]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if by_edge.has(key):
				var j: int = by_edge[key]
				adj[i].append(j)
				adj[j].append(i)
			else:
				by_edge[key] = i
		c /= poly.size()
		var d := c.distance_squared_to(seed_point)
		if d < best:
			best = d
			start = i
	var seen := PackedByteArray()
	seen.resize(n)
	seen[start] = 1
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for j in adj[i]:
			if seen[j] == 0:
				seen[j] = 1
				stack.append(j)
	var keep: Array[PackedInt32Array] = []
	for i in n:
		if seen[i] == 1:
			keep.append(nm.get_polygon(i))
	if keep.size() == n:
		return
	_rebuild(nm, verts, keep)


func _prune_high_polygons(nm: NavigationMesh, max_y: float) -> void:
	var verts := nm.get_vertices()
	var keep: Array[PackedInt32Array] = []
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var low := false
		for idx in poly:
			if verts[idx].y <= max_y:
				low = true
				break
		if low:
			keep.append(poly)
	if keep.size() == nm.get_polygon_count():
		return
	_rebuild(nm, verts, keep)


func _rebuild(nm: NavigationMesh, verts: PackedVector3Array, keep: Array[PackedInt32Array]) -> void:
	var remap := {}
	var new_verts := PackedVector3Array()
	nm.clear_polygons()
	for poly in keep:
		var np := PackedInt32Array()
		for idx in poly:
			if not remap.has(idx):
				remap[idx] = new_verts.size()
				new_verts.append(verts[idx])
			np.append(remap[idx])
		nm.add_polygon(np)
	nm.vertices = new_verts
	# Re-assign so the NavigationServer region picks up the edited mesh.
	nav_region.navigation_mesh = null
	nav_region.navigation_mesh = nm
