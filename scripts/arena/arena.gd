class_name Arena
extends Node3D
## Gameplay-facing arena. Exposes spawn points / player start and bakes the navigation
## mesh at runtime from collision geometry in the "nav_source" group, so swapping the
## visual courtyard never requires touching combat or AI code.

@export var bake_navigation_on_ready: bool = true

@onready var spawn_root: Node3D = $SpawnPoints
@onready var player_start: Marker3D = $PlayerStart
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	if bake_navigation_on_ready:
		bake_navigation()


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
	# Only bake the walkable courtyard, not the grass outside the walls.
	nm.filter_baking_aabb = AABB(Vector3(-21, -1, -21), Vector3(42, 6, 42))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


func get_spawn_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in spawn_root.get_children():
		if c is Node3D:
			out.append(c)
	return out
