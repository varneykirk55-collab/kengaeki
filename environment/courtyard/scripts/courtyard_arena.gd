class_name CourtyardArena
extends Arena
## Courtyard version of the gameplay arena. Keeps the Arena interface the game uses
## (PlayerStart, SpawnPoints, NavigationRegion3D, get_spawn_points) and only makes the
## navmesh bake bounds configurable so a different blueprint footprint does not need
## arena.gd edits. Bakes from StaticBody3D collision on layer 1 in the "nav_source" group.

## Walkable area to bake (keep it inside the walls so the grass outside is excluded).
@export var nav_bake_aabb: AABB = AABB(Vector3(-21, -1, -21), Vector3(42, 6, 42))


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
