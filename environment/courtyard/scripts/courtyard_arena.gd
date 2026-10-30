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
