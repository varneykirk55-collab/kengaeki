# Courtyard: deviations from Agent 1's blueprint

Blueprint: `/workspace/kengeki_design/agent3_handoff.md` + `layout_data.py`
(sha256 `ab13ae0c…89c0d1`, Oct 30, 2026, 6:29 PM EDT). **DRAFT, not yet reviewed by Kirk.**
The graybox is generated from `layout_data.py`, which is read in place (never copied or
edited) by `tools/courtyard/gen_graybox.py`. Every placement, spawn, path and prefab comes
from that file; re-run the generator after the blueprint changes.

Layout, coordinates, colliders, spawns, nav AABB and Sun distance follow the blueprint.
The deviations below are about file locations and graybox detail only.

| # | Blueprint says | Built | Why |
|---|---|---|---|
| 1 | `scenes/arena/castle_courtyard.tscn` | `environment/courtyard/scenes/castle_courtyard.tscn` | Kirk's brief fixes the courtyard folder convention `res://environment/courtyard/{assets,props,modules,scenes}`. Same scene name. |
| 2 | `scenes/main_courtyard.tscn` | `environment/courtyard/scenes/main_courtyard.tscn` | Same reason. It is still a copy of `main.tscn` with only the Arena instance changed. |
| 3 | `scripts/arena/courtyard_arena.gd`, `class_name CastleCourtyardArena`, AABB hard-coded in `bake_navigation()` | `environment/courtyard/scripts/courtyard_arena.gd`, `class_name CourtyardArena extends Arena`, AABB is an `@export nav_bake_aabb` set in the scene to the blueprint's `AABB(-40, -0.6, -47, 80, 8, 82)` | Same bake settings. Exported so a blueprint change does not need a script edit. `arena.gd` is untouched. |
| 4 | `assets/environment/courtyard/<asset>/<asset>.glb`, prefabs in `scenes/environment/courtyard/<asset>.tscn` | GLBs: `environment/courtyard/assets/<Category>/<asset>/<asset>.glb` (BJORN's library categories). Prefabs: `environment/courtyard/modules/` (architecture) and `.../props/` | Folder convention, plus matching BJORN's `library/<Category>/<asset>/` layout. Name map in `CATEGORY` in the generator. `stone_lantern_toro_2m` maps to BJORN's `Decorations/stone_lantern_toro`. |
| 5 | Props: "primitive colliders, or instanced prefab bodies, all inside this group" | Lantern, tree and rock prefabs (visual + own StaticBody3D) sit under `Collision/Props/*`, so their graybox visuals are under `Collision`, not `Visual` | Uses the blueprint's "instanced prefab bodies" option. It keeps one prefab per asset for the GLB swap. Shrubs and small rocks have no collider. |
| 6 | Walls as MultiMeshInstance3D ×68 "or 68 instances" | 68 prefab instances | Allowed by the blueprint. Switch to MultiMesh with the real GLB once draw calls have been measured. |
| 7 | Pond is an ellipse (rx 5.5, rz 5.0) | Rectangular graybox water plane (11 × 10 m at y −0.3) and basin. The 7 `pond_edge_stones_2m` sit on the ellipse as listed. | Graybox only. Collision is exactly the blueprint's rectangular hole and fences. |
| 8 | Arch bridge visual | Graybox ramps and deck match the colliders. Visual rails are a single bar at 1.6 m, not 2 m. | Visual only. The collision rails are 2 m as specified. |

## Open issues found while building (not changed; for Bill and Kirk)
- **Navmesh islands on roofs and wall tops.** The bake AABB is 8 m tall (y −0.6..7.4), so wall tops (5 m), barracks (6 m) and kura (7 m) get small disconnected navmesh islands. The headless check counts 44 navmesh vertices above y = 2 m. They are unreachable, but an agent or `map_get_closest_point` could snap to them. Suggest an AABB height of about 2.6 (y −0.6..2.0). The arch deck top is 1.0 m, so that still covers it. Not changed because the blueprint specifies 8.
- **Navmesh height offset.** The navmesh sits up to about 0.4–0.5 m above the collider tops at cell_height 0.25 (deck top 1.0 → navmesh 1.4). This is normal for the bake settings.
- **No visual or gameplay verification yet.** Everything above was checked headless only (see INTEGRATION_PLAN.md §8).
