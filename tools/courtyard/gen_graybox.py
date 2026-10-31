#!/usr/bin/env python3
"""Generates the Kengeki courtyard graybox from Agent 1 (Bill)'s blueprint
(/workspace/kengeki_design/layout_data.py, read in place): shared materials, one prefab per blueprint asset,
the courtyard arena scene and a prefab gallery, all under res://environment/courtyard/.

Run from the repo root:  python3 tools/courtyard/gen_graybox.py
Re-running overwrites only files this script owns (all under environment/courtyard/,
except README/plan docs and anything in assets/). Units are metres, Y-up, -Z forward.
Module convention: origin at bottom centre, length along local X, courtyard-facing side +Z.
"""
import math, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
BASE = "environment/courtyard"
RES = "res://" + BASE

MATS = {  # name: (albedo rgb, roughness, extra)
    "stone":   ((0.38, 0.37, 0.35), 0.9, ""),
    "plaster": ((0.74, 0.72, 0.67), 0.9, ""),
    "tile":    ((0.17, 0.19, 0.22), 0.6, ""),
    "wood":    ((0.27, 0.17, 0.11), 0.85, ""),
    "lacquer": ((0.52, 0.12, 0.08), 0.5, ""),
    "gravel":  ((0.50, 0.48, 0.43), 0.95, ""),
    "grass":   ((0.33, 0.40, 0.24), 0.95, ""),
    "path":    ((0.36, 0.35, 0.33), 0.9, ""),
    "bark":    ((0.24, 0.17, 0.13), 0.9, ""),
    "foliage": ((0.20, 0.32, 0.18), 0.9, ""),
    "water":   ((0.16, 0.28, 0.30), 0.08, "metallic_specular = 0.8\n"),
}


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def vec(v):
    return "Vector3(%s)" % ", ".join(fmt(x) for x in v)


def xform(pos=(0, 0, 0), rot=None, scale=(1, 1, 1)):
    """rot = (axis, degrees) with axis in 'x','y','z'."""
    xa, ya, za = [1, 0, 0], [0, 1, 0], [0, 0, 1]
    if rot:
        axis, deg = rot
        a = math.radians(deg); c, s = math.cos(a), math.sin(a)
        if axis == "y":
            xa, ya, za = [c, 0, -s], [0, 1, 0], [s, 0, c]
        elif axis == "z":
            xa, ya, za = [c, s, 0], [-s, c, 0], [0, 0, 1]
        elif axis == "x":
            xa, ya, za = [1, 0, 0], [0, c, s], [0, -s, c]
    xa = [v * scale[0] for v in xa]; ya = [v * scale[1] for v in ya]; za = [v * scale[2] for v in za]
    # xa/ya/za are the basis COLUMNS (images of the local axes). The .tscn Transform3D literal is
    # row-major (x.x, y.x, z.x, x.y, ...), so emit the rows. (Before Oct 30 6:45 PM this wrote the
    # columns, which silently negated every rotation: yaw and ramp tilt were mirrored.)
    rows = [xa[0], ya[0], za[0], xa[1], ya[1], za[1], xa[2], ya[2], za[2]]
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in rows + list(pos))


def write(rel, text):
    path = os.path.join(ROOT, BASE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def gen_materials():
    for name, (rgb, rough, extra) in MATS.items():
        write("materials/gb_%s.tres" % name,
              '[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n'
              'resource_name = "gb_%s"\nalbedo_color = Color(%s, %s, %s, 1)\nroughness = %s\n%s'
              % (name, fmt(rgb[0]), fmt(rgb[1]), fmt(rgb[2]), fmt(rough), extra))


class Scene:
    """Minimal .tscn writer for a prop/module wrapper scene."""

    def __init__(self, name, model_path="", script=True, notes=""):
        self.name = name
        self.ext = []      # (type, path)
        self.subs = []     # text blocks
        self.nodes = []    # text blocks
        self.model_path = model_path
        self.asset = name          # blueprint asset (differs from name for variant prefabs)
        self.model_scale = 1.0
        self.notes = notes
        self.sid = 0
        if script:
            self._ext("Script", RES + "/scripts/courtyard_prop.gd")

    def _ext(self, typ, path):
        for i, (t, p) in enumerate(self.ext):
            if p == path:
                return "%d" % (i + 1)
        self.ext.append((typ, path))
        return "%d" % len(self.ext)

    def mat(self, name):
        return 'ExtResource("%s")' % self._ext("Material", RES + "/materials/gb_%s.tres" % name)

    def sub(self, typ, props):
        self.sid += 1
        sid = "%s_%d" % (typ, self.sid)
        body = "".join("%s = %s\n" % kv for kv in props)
        self.subs.append('[sub_resource type="%s" id="%s"]\n%s' % (typ, sid, body))
        return 'SubResource("%s")' % sid

    def node(self, name, typ, parent, props=(), groups=None, instance=None):
        head = '[node name="%s"' % name
        if typ:
            head += ' type="%s"' % typ
        if parent is not None:
            head += ' parent="%s"' % parent
        if instance:
            head += ' instance=ExtResource("%s")' % self._ext("PackedScene", instance)
        if groups:
            head += " groups=[%s]" % ", ".join('"%s"' % g for g in groups)
        head += "]\n"
        self.nodes.append(head + "".join("%s = %s\n" % kv for kv in props))

    # --- helpers -----------------------------------------------------------------------
    def box(self, name, pos, size, mat, rot=None, parent="Graybox", shadow=True):
        m = self.sub("BoxMesh", [("size", vec(size))])
        props = [("transform", xform(pos, rot)), ("mesh", m), ("material_override", self.mat(mat))]
        if not shadow:
            props.append(("cast_shadow", "0"))
        self.node(name, "MeshInstance3D", parent, props)

    def cyl(self, name, pos, top, bottom, h, mat, seg=12, parent="Graybox", rot=None):
        m = self.sub("CylinderMesh", [("top_radius", fmt(top)), ("bottom_radius", fmt(bottom)),
                                       ("height", fmt(h)), ("radial_segments", str(seg)), ("rings", "1")])
        self.node(name, "MeshInstance3D", parent,
                  [("transform", xform(pos, rot)), ("mesh", m), ("material_override", self.mat(mat))])

    def sphere(self, name, pos, r, h, mat, parent="Graybox"):
        m = self.sub("SphereMesh", [("radius", fmt(r)), ("height", fmt(h)), ("radial_segments", "12"), ("rings", "6")])
        self.node(name, "MeshInstance3D", parent,
                  [("transform", xform(pos)), ("mesh", m), ("material_override", self.mat(mat))])

    def col_box(self, name, pos, size, rot=None):
        s = self.sub("BoxShape3D", [("size", vec(size))])
        self.node(name, "CollisionShape3D", "Collision", [("transform", xform(pos, rot)), ("shape", s)])

    def col_cyl(self, name, pos, r, h):
        s = self.sub("CylinderShape3D", [("radius", fmt(r)), ("height", fmt(h))])
        self.node(name, "CollisionShape3D", "Collision", [("transform", xform(pos)), ("shape", s)])

    def begin(self, collision=True):
        props = []
        if self.ext and self.ext[0][1].endswith("courtyard_prop.gd"):
            props.append(("script", 'ExtResource("1")'))
            if self.model_path:
                props.append(("model_path", '"%s"' % self.model_path))
            # Variant prefabs (<asset>_<variant>) use their own MODEL_FIT entry if any, else the asset's.
            fit = MODEL_FIT.get(self.name, MODEL_FIT.get(getattr(self, "asset", self.name), {}))
            if "offset" in fit:
                props.append(("model_offset", vec(fit["offset"])))
            if "scale_xyz" in fit:
                props.append(("model_scale_xyz", vec(fit["scale_xyz"])))
            if getattr(self, "model_scale", 1.0) != 1.0:
                props.append(("model_scale", fmt(self.model_scale)))
            if getattr(self, "authored_size", None):
                props.append(("authored_size", vec(self.authored_size)))
            if getattr(self, "asset", self.name) in SIZE_TOL:
                props.append(("size_tolerance_pct", "Vector2(%s, %s)" % tuple(fmt(v) for v in SIZE_TOL[self.asset])))
            lods = resolve_lods(self.name) if self.model_path and not self.model_path.endswith("graybox") else []
            if lods and os.path.isfile(os.path.join(ROOT, self.model_path[len("res://"):])):
                props.append(("model_lod_paths", "PackedStringArray(%s)" % ", ".join('"%s"' % p for p, _d, _s in lods)))
                props.append(("model_lod_distances", "PackedFloat32Array(%s)" % ", ".join(fmt(d) for _p, d, _s in lods)))
                props.append(("model_lod_share_materials", "PackedInt32Array(%s)" % ", ".join("1" if sh else "0" for _p, _d, sh in lods)))
                props.append(("model_lod_fade", fmt(LOD_FADE.get(self.name, LOD_FADE_DEFAULT))))
            rnd = MODEL_RENDER.get(getattr(self, "asset", self.name), {})
            if "lod_bias" in rnd:
                props.append(("model_lod_bias", "%g" % rnd["lod_bias"]))
            if "vis_end" in rnd:
                props.append(("model_visibility_range_end", "%g" % rnd["vis_end"]))
                props.append(("model_visibility_range_end_margin", "%g" % rnd.get("vis_margin", 0)))
        self.node(self.name, "Node3D", None, props)
        self.node("Graybox", "Node3D", ".")
        if collision:
            self.node("Collision", "StaticBody3D", ".", [("collision_layer", "1"), ("collision_mask", "0")])

    def save(self, rel):
        out = "[gd_scene load_steps=%d format=3]\n\n" % (len(self.ext) + len(self.subs) + 1)
        if self.notes:
            out = "; " + self.notes.replace("\n", "\n; ") + "\n" + out
        for i, (t, p) in enumerate(self.ext):
            out += '[ext_resource type="%s" path="%s" id="%d"]\n' % (t, p, i + 1)
        out += "\n" + "\n".join(self.subs) + "\n" + "\n".join(self.nodes)
        write(rel, out)


def asset_path(cat, name):
    # Expected location of the *optimised* GLB copied from BJORN's library (see plan).
    return "%s/assets/%s/%s/%s.glb" % (RES, cat, name, name)


# BJORN may file an asset under its type category (Walls, Rocks, ...), under Courtyard/, or under
# Decorations/, and may use his name or Bill's. Lookup order for both the library and the repo copy.
EXTRA_CATEGORIES = ("Courtyard", "Decorations")


def asset_candidates(asset):
    cat, lib = CATEGORY.get(asset, ("Misc", asset))
    cats = [cat] + [c for c in EXTRA_CATEGORIES if c != cat]
    names = [lib] + ([asset] if asset != lib else [])
    return [(c, n) for c in cats for n in names]


# Preferred variant file per blueprint asset (BJORN's LOD variants sit next to the main GLB).
# Bill's inventory asks for the lantern decimated to ~8k tris; BJORN delivered that as lod8k.
MODEL_VARIANT = {"stone_lantern_toro_2m": "stone_lantern_toro_lod8k",
                 # Batch 3: the deck2m variant's deck top is 2.0 m wide, matching Bill's deck collider
                 # and the rails at x +-1.075. Only the variant is copied (sync_assets.py --variant
                 # deck2m); the main bridge_stone_slab.glb (2.33 m deck) is not in the repo.
                 "bridge_stone_slab": "bridge_stone_slab_deck2m",
                 # Batch 4 (final): the wide gate (15.34 m, Bill 16 m) replaces the 14.67 m gate. Only the
                 # variant is in the repo; the old main_gate_yaguramon.glb was removed (DEVIATIONS.md #31).
                 "main_gate_yaguramon": "main_gate_yaguramon_wide"}

# Integration fit applied to the imported model only (graybox and collision unaffected unless noted).
# Every entry is a documented deviation (docs/courtyard/DEVIATIONS.md).
MODEL_FIT = {
    # Bridge v2 (BJORN, Oct 30 8:06 PM): y=0 is the pier bottoms. Sink 0.40 m so both deck ends
    # sit flush on the banks (deck-end top 0.393-0.407 in model space) and the piers end 0.10 m
    # under the water surface (-0.30). The arena colliders follow the sunk deck (ARCH_PROFILE).
    "bridge_arched_taikobashi": dict(offset=(0, -0.40, 0)),
    # Slab deck2m (batch 3): y=0 is the support bottoms, deck top 0.391-0.395. Sink 0.394 m so the
    # deck is flush with the banks (+-3 mm over its walkable length) and the supports end 0.094 m
    # under the water surface (-0.30).
    "bridge_stone_slab": dict(offset=(0, -0.394, 0)),
    # LOD pack (Oct 30, 9:35 PM): per-axis node scale on the tree models (BJORN's suggestion,
    # confirmed by Kirk). Pine: canopy depth 3.58 -> 4.66 m (Bill 6 x 7 x 6). Maple: 4.04 x 5 x 4.04
    # -> 5.0 x 5 x 5.0 (Bill 5 x 5 x 5). The trunk colliders follow (TREE_TRUNK). DEVIATIONS.md #26.
    "tree_pine_kuromatsu": dict(scale_xyz=(1, 1, 1.3)),
    "tree_maple_momiji": dict(scale_xyz=(1.237, 1, 1.238)),
    # Batch 4 final (DEVIATIONS.md #29). BJORN's pond stones are low (main 0.226 m, b 0.284 m tall,
    # 0.44-0.49 m deep; Bill 2 x 0.5 x 0.8). Bill's stones sit on an ellipse inside the pond
    # rectangle, i.e. over the water (surface y -0.30): sunk 0.32 m so every stone stands in the
    # water, with per-file Y scale to the same ~0.45 m total height (top ~0.13 m above the bank) and
    # Z x1.4 for depth. b: Kirk's (1, 1.6, 1.4); main needs 2.0 in Y for the same height.
    "pond_edge_stones_2m": dict(offset=(0, -0.32, 0), scale_xyz=(1, 2.0, 1.4)),
    "pond_edge_stones_2m_b": dict(offset=(0, -0.32, 0), scale_xyz=(1, 1.6, 1.4)),
    # Shrubs: node Y x1.2 (1.08 -> 1.30 m; Bill 1.6 x 1.0 x 1.6, BJORN's suggestion). The main file
    # has a brown stem cone under the foliage: sunk 0.08 m. DEVIATIONS.md #30.
    "shrub_azalea": dict(offset=(0, -0.08, 0), scale_xyz=(1, 1.2, 1)),
    "shrub_azalea_b": dict(scale_xyz=(1, 1.2, 1)),
    # rock_medium (BJORN's low boulder, flat filled underside): sunk 0.03 m. DEVIATIONS.md #32.
    "rock_medium": dict(offset=(0, -0.03, 0)),
}

# Render cost settings for the imported models (CourtyardProp exports). Every BJORN GLB is
# imported with meshes/generate_lods=true (Godot's default, kept explicit in the .import files).
# Godot's generator gives these meshes at most one extra LOD (UV seams lock most vertices), so:
#   lod_bias < 1 makes the wall modules (78 instances, 82% of the scene's triangles) use their
#   5.4k-triangle LOD sooner; vis_end culls small props beyond the given distance (m), with a
#   hysteresis margin. Measured with tools/courtyard/render_views.gd (INTEGRATION_PLAN.md).
MODEL_RENDER = {
    # LOD pack: the walls now switch to BJORN's hand-made lod1/lod2 (MODEL_LODS), so the 0.3 bias
    # on Godot's generated LOD (batch 2) is dropped; LOD0 is only drawn within 20 m.
    "stone_lantern_toro_2m": dict(vis_end=55.0, vis_margin=5.0),
    # Trees: batch 3 culled them beyond 100 m. With the 4k lod3k beyond 25 m they are drawn at any
    # distance again (no pop-out at the far corners).
    # Small rock clusters (batch 4): 1k-triangle decoration, culled beyond 45 m (+5 m hysteresis).
    "rock_small_cluster": dict(vis_end=45.0, vis_margin=5.0),
    # Shrubs (batch 4 final): 2k-triangle decoration; Bill (agent3_handoff 9) fades shrubs and small
    # rocks beyond ~45 m.
    "shrub_azalea": dict(vis_end=45.0, vis_margin=5.0),
}

# Hand-made LODs from BJORN's LOD pack (Oct 30, 9:35 PM): per blueprint asset, the MANIFEST variant,
# the camera distance (m, to the mesh AABB centre) where it takes over, and whether it is drawn with
# LOD0's materials (same UVs; its embedded textures are discarded on import by vram_textures.py). The
# switch is a dithered crossfade LOD_FADE m wide (visibility_range margins, FADE_SELF). Distances for
# the 80 m compound and the third-person camera (4.2 m arm): LOD0 covers the combat area around the
# player; lod1 the middle distance; lod2 the far side of the compound and the long views.
MODEL_LODS = {
    # LOD rework (Oct 30, 10:45 PM): wall/barracks/turret lod1 and the tree lod3k reference LOD0's
    # texture files (glTF URIs, no embedded images), so share=True; lod2 keeps its own 256 px textures.
    "wall_segment_4m": [("lod1", 20.0, True), ("lod2", 45.0, False)],
    "corner_turret": [("lod1", 30.0, True), ("lod2", 60.0, False)],
    "barracks_nagaya": [("lod1", 30.0, True), ("lod2", 55.0, False)],
    # Kura: BJORN's seam-preserving lod1 is 5,446 tris (91% of LOD0), so it is skipped: LOD0 -> lod2
    # directly, at 35 m (was lod1 25 m / lod2 50 m); kura lod1 is no longer in the repo.
    "storehouse_kura": [("lod2", 35.0, False)],
    "tree_pine_kuromatsu": [("lod3k", 25.0, True)],
    "tree_sakura": [("lod3k", 25.0, True)],
    "tree_maple_momiji": [("lod3k", 25.0, True)],
}
LOD_FADE = {"wall_segment_4m": 2.0}   # default 3 m
LOD_FADE_DEFAULT = 3.0

# Second variants delivered as separate GLBs (batch 4 rocks): each gets its own prefab
# (<asset>_<variant>.tscn) and alternates with the main model over Bill's instances (INSTANCE_VARIANT).
# scale: uniform node scale on the model (BJORN: 0.9 for rock_formation_large_b, 0.85-1.0 for the
# clusters). collider: one box (centre, size) in prefab space, measured from the model's vertices
# above y 0.3 m (the moss skirt below that is walk-through) at that scale, full model height.
VARIANTS = {
    "rock_formation_large": {
        None: dict(scale=1.0, collider=((0.05, 0.99, -0.005), (2.08, 1.98, 1.87))),
        "b": dict(scale=0.9, collider=((-0.014, 0.969, 0.176), (2.51, 1.938, 1.13))),
    },
    "rock_small_cluster": {
        None: dict(scale=0.9, collider=((0.0, 0.217, 0.0), (0.597, 0.435, 0.575))),
        "b": dict(scale=0.9, collider=((-0.009, 0.248, 0.013), (0.504, 0.496, 0.495))),
    },
    # Batch 4 final: rock_medium is BJORN's 1.5 x 1.0 x 1.2 m boulder (exactly Bill's size). One box
    # inside the model's bounds (x +-0.72, z +-0.55: the boulder's bulk at 30-60% of its height),
    # from the sunk base (-0.03) to 0.95 (the rounded crown reaches 0.97).
    "rock_medium": {None: dict(scale=1.0, collider=((0.0, 0.46, 0.0), (1.44, 0.98, 1.10)))},
    # Second files without a collider of their own (pond stones: arena colliders; shrubs: none).
    "pond_edge_stones_2m": {None: {}, "b": {}},
    "shrub_azalea": {None: {}, "b": {}},
}
# Bill's rocks, alternating main / b (every second instance in blueprint order).
INSTANCE_VARIANT = {"ROCKL2": "b", "ROCKL4": "b",
                    "ROCKS2": "b", "ROCKS4": "b", "ROCKS6": "b", "ROCKS8": "b", "ROCKS10": "b",
                    # Batch 4 final: pond stones and shrubs alternate the same way.
                    "PSTONE2": "b", "PSTONE4": "b", "PSTONE6": "b",
                    "SHRUB2": "b", "SHRUB4": "b", "SHRUB6": "b", "SHRUB8": "b", "SHRUB10": "b", "SHRUB12": "b"}
# Size-check tolerance (% per axis, min..max) where +-10% does not fit; checked by sync_assets.py and
# check_courtyard.gd (size_tolerance_pct export). Rocks are natural shapes: only "no more than 10%
# (clusters: 25%) larger than Bill's box" matters for the layout. DEVIATIONS.md #28.
SIZE_TOL = {"rock_formation_large": (-25.0, 10.0), "rock_small_cluster": (-40.0, 25.0),
            # Batch 4 final: pond stones are shallower than Bill's 0.8 m even at Z x1.4 (0.62 / 0.69 m);
            # shrubs are 30% taller than Bill's 1.0 m at BJORN's Y x1.2. DEVIATIONS.md #29, #30.
            "pond_edge_stones_2m": (-25.0, 10.0), "shrub_azalea": (-10.0, 31.0)}

# Placement overrides (x, z, yaw) where Bill's position makes a delivered model clip a bridge.
# Found with tools/courtyard/pond_fit.py. DEVIATIONS.md #29.
PLACE_OVERRIDE = {
    "PSTONE3": (28.40, 4.7, 162.0),    # Bill x 28.12: 0.03 m into the slab bridge's east side; now
                                       # 0.25 m from the slab, 0.34 m from the arch bridge
    "PSTONE4": (24.30, 1.29, 90.0),    # Bill (24.69, yaw 106): 0.47 m into the slab bridge (its west
                                       # edge and rail); now along the west bank, 0.14 m clear
    "PSTONE5": (24.30, -1.29, 90.0),   # Bill (24.69, yaw 74): 0.35 m into the slab bridge; mirrored
    "PSTONE6": (28.40, -4.7, 18.0),    # mirror of PSTONE3 (Bill: 0.01 m into the slab)
}
# Pond stones: one box collider each in the arena (Collision/PondStones), fitted to the model at its
# node scale: (half length x, bottom y, top y, half depth z) per file. Raw sizes: main 2.000 x 0.226
# x 0.443, b 2.000 x 0.284 x 0.490 (BJORN's HANDOFF batch 4).
POND_STONE_BOX = {None: (1.0, -0.32, -0.32 + 0.226 * 2.0, 0.2215 * 1.4),
                  "b": (1.0, -0.32, -0.32 + 0.284 * 1.6, 0.245 * 1.4)}

# Authored-size overrides used by the 10% checks (sync_assets.py, check_courtyard.gd) where the
# delivered asset legitimately differs from layout_data.py. Documented in DEVIATIONS.md.
AUTHORED_SIZE = {
    # Bill: 13 x 1.8 x 2.4. v2 adds 0.25 m of pier below the old base (hidden under the water),
    # so the model is 2.05 m tall; above the bank it is 1.65 m.
    "bridge_arched_taikobashi": (13, 2.05, 2.4),
    # Bill: 11 x 0.4 x 2.0 (the deck). deck2m: the deck top is 2.0 m wide; the supports below it
    # reach z +-1.333 (in the water, clear of the pond fence at x 24.2..24.5).
    "bridge_stone_slab": (11, 0.4, 2.667),
}

# Trees (batch 3) are scaled uniformly to Bill's height with the origin at the trunk base, so the
# size checks compare the height (within 10%) and only require the canopy footprint to be no
# larger than Bill's (+10%); the footprint is not centred on the origin. DEVIATIONS.md #23.
HEIGHT_FIT = {"tree_pine_kuromatsu", "tree_sakura", "tree_maple_momiji"}
# Trunk-only collider per species (model space: x, z of the cylinder axis, radius, height), from
# BJORN's batch 3 notes. Bill: pine r0.35 h3, maple/sakura r0.3 h2.5. Canopies do not collide.
# LOD pack: pine z x1.3 moves the trunk axis to z 0.195; maple x/z x1.237 widens the trunk to r 0.25.
TREE_TRUNK = {"tree_pine_kuromatsu": (-0.3, 0.195, 0.45, 2.5),
              "tree_sakura": (0.0, 0.0, 0.4, 2.3),
              "tree_maple_momiji": (0.0, 0.0, 0.25, 2.0)}
# Yaw overrides (degrees) where Bill's yaw makes a canopy clip a wall or turret; the trunk stays on
# Bill's position. Found with tools/courtyard/tree_fit.py. DEVIATIONS.md #23, #26.
# Batch 3 (uniform pine): 88 / 312 with >= 0.25 m clearance. LOD pack: the pine's z x1.3 node scale
# makes its canopy 4.66 m deep; at 88 / 312 it clipped WE11 by 0.01 m and TNE by 0.04 m. The yaws
# below are the best clearances over all 360 degrees (PINE3 0.10 m, PINE6 0.05 m against the
# conservative eave-inclusive AABBs).
YAW_OVERRIDE = {"PINE3": 92,    # Bill 134: canopy 0.54 m into the east wall (WE11)
                "PINE6": 304}   # Bill 335: canopy 0.29 m into the NE turret (TNE)
POND_X, POND_HZ = (24.5, 35.5), 5.0   # pond water x range and half depth in z (water box (30,-0.3,0), 11 x 10)


def resolve_model_path(asset):
    """res:// path of the GLB already copied into the repo for this asset, if any; otherwise the
    default expected path (which does not exist, so the prefab shows its graybox)."""
    for c, n in asset_candidates(asset):
        names = ([MODEL_VARIANT[asset]] if asset in MODEL_VARIANT else []) + [n]
        for fn in names:
            rel = "%s/assets/%s/%s/%s.glb" % (BASE, c, n, fn)
            if os.path.isfile(os.path.join(ROOT, rel)):
                return "res://" + rel
    c, n = asset_candidates(asset)[0]
    return asset_path(c, n)

def resolve_variant_path(asset, variant):
    """res:// path of a MANIFEST variant GLB (<name>_<variant>.glb next to the main model) if it is
    in the repo, else None (never written into a scene)."""
    for c, n in asset_candidates(asset):
        rel = "%s/assets/%s/%s/%s_%s.glb" % (BASE, c, n, n, variant)
        if os.path.isfile(os.path.join(ROOT, rel)):
            return "res://" + rel
    return None


def resolve_lods(asset):
    """[(res path, distance, share)] for the LOD files of this asset that are in the repo."""
    out = []
    for v, d, share in MODEL_LODS.get(asset, []):
        p = resolve_variant_path(asset, v)
        if p:
            out.append((p, d, share))
    return out


# ---------------------------------------------------------------------------------------
# Blueprint (Agent 1 / Bill). Read from Bill's file; see BLUEPRINT_SRC.
# ---------------------------------------------------------------------------------------
import sys, shutil, hashlib, datetime

# Bill's file is READ in place (never copied or edited). Override with KENGEKI_LAYOUT=/path/layout_data.py.
BLUEPRINT_SRC = os.environ.get("KENGEKI_LAYOUT", "/workspace/kengeki_design/layout_data.py")
BLUEPRINT_SHA = ""

# Bill's asset name -> (BJORN library category, library asset name). The GLB is expected at
# res://environment/courtyard/assets/<Category>/<asset>/<asset>.glb (optimised copy).
CATEGORY = {
    "wall_segment_4m": ("Walls", "wall_segment_4m"),
    "corner_turret": ("Walls", "corner_turret"),
    "main_gate_yaguramon": ("Gates", "main_gate_yaguramon"),
    "main_hall_goten": ("Architecture", "main_hall_goten"),
    "barracks_nagaya": ("Architecture", "barracks_nagaya"),
    "storehouse_kura": ("Architecture", "storehouse_kura"),
    "castle_keep_tenshu": ("Architecture", "castle_keep_tenshu"),
    "bridge_arched_taikobashi": ("Bridges", "bridge_arched_taikobashi"),
    "bridge_stone_slab": ("Bridges", "bridge_stone_slab"),
    "stone_lantern_toro_2m": ("Decorations", "stone_lantern_toro"),
    "tree_pine_kuromatsu": ("Vegetation", "tree_pine_kuromatsu"),
    "tree_maple_momiji": ("Vegetation", "tree_maple_momiji"),
    "tree_sakura": ("Vegetation", "tree_sakura"),
    "shrub_azalea": ("Vegetation", "shrub_azalea"),
    "rock_formation_large": ("Rocks", "rock_formation_large"),
    "rock_medium": ("Rocks", "rock_medium"),
    "rock_small_cluster": ("Rocks", "rock_small_cluster"),
    "pond_edge_stones_2m": ("Rocks", "pond_edge_stones_2m"),
}
# Architecture: visual-only prefabs; their collision is authored in the arena's Collision node
# (blueprint section 7). Props carry their own primitive collider and live under Collision/Props.
ARCH = {"wall_segment_4m", "corner_turret", "main_gate_yaguramon", "main_hall_goten", "barracks_nagaya",
        "storehouse_kura", "castle_keep_tenshu", "bridge_arched_taikobashi", "bridge_stone_slab", "pond_edge_stones_2m"}


# ---- Arch bridge walking surface (batch 2, Oct 30) ----
# Deck-top profile of BJORN's bridge_arched_taikobashi.glb v2 (local X = length, model space,
# y up; HANDOFF "Bridge v2 fix" / stats.json v2_fix, re-measured with glb_probe.py). The v2
# deck is symmetric. Ends are joined to the bank by lead-in chords from y=0 at |x| = 7 m
# (0.5 m onto the bank, under the deck end).
ARCH_PROFILE = [(-5.5, 0.423), (-5.0, 0.580), (-4.75, 0.651), (-3.5, 0.882), (-2.0, 1.033),
                (-0.75, 1.094), (0.0, 1.104), (0.75, 1.094), (2.0, 1.033), (3.5, 0.882),
                (4.75, 0.651), (5.0, 0.580), (5.5, 0.423)]
ARCH_LEADIN_X = 7.0
ARCH_DECK_T = 0.3     # collider / graybox deck thickness
ARCH_RAIL_H = 1.0     # rail top 1.0 m above the walking surface (addendum 6:40 PM)
ARCH_RAIL_T = 0.15
ARCH_RAIL_Z = 1.275   # rail centre line, either side of the 2.4 m deck


def arch_knots():
    sink = MODEL_FIT.get("bridge_arched_taikobashi", {}).get("offset", (0, 0, 0))[1]
    return [(-ARCH_LEADIN_X, 0.0)] + [(x, y + sink) for x, y in ARCH_PROFILE] + [(ARCH_LEADIN_X, 0.0)]


def arch_segments():
    """Deck boxes (centre x, centre y, length, tilt deg about local Z) whose top faces are the
    chords between consecutive knots (slightly overlapped so there is no seam)."""
    out = []
    k = arch_knots()
    for (x0, y0), (x1, y1) in zip(k[:-1], k[1:]):
        a = math.atan2(y1 - y0, x1 - x0)
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        ln = math.hypot(x1 - x0, y1 - y0) + 0.06
        out.append((mx + math.sin(a) * ARCH_DECK_T / 2, my - math.cos(a) * ARCH_DECK_T / 2, ln, math.degrees(a)))
    return out


def arch_rail_centre(cx, cy, deg):
    a = math.radians(deg)
    off = ARCH_DECK_T / 2 + ARCH_RAIL_H / 2  # from the deck box centre along the surface normal
    return cx - math.sin(a) * off, cy + math.cos(a) * off


def arch_deck_height(x):
    """Walking-surface height (top of the deck colliders) at local x."""
    k = arch_knots()
    for (x0, y0), (x1, y1) in zip(k[:-1], k[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return 0.0


def xform_basis(pos, cols):
    """Transform3D from basis columns (images of local x, y, z)."""
    xa, ya, za = cols
    rows = [xa[0], ya[0], za[0], xa[1], ya[1], za[1], xa[2], ya[2], za[2]]
    return "Transform3D(%s)" % ", ".join(fmt(round(v, 6)) for v in rows + list(pos))


def place(inst_pos, yaw, local_pos, tilt_z=0.0):
    """World position and basis of a box given in a yawed instance's local frame, tilted about
    local Z (blueprint convention: yaw about +Y, Godot rotation_degrees.y)."""
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    lx, ly, lz = local_pos
    wp = (inst_pos[0] + c * lx + s_ * lz, inst_pos[1] + ly, inst_pos[2] - s_ * lx + c * lz)
    ct, st = math.cos(math.radians(tilt_z)), math.sin(math.radians(tilt_z))
    loc = [(ct, st, 0.0), (-st, ct, 0.0), (0.0, 0.0, 1.0)]  # columns of R_z(tilt)
    ry = lambda v: (c * v[0] + s_ * v[2], v[1], -s_ * v[0] + c * v[2])
    return wp, [ry(v) for v in loc]


# Addendum, Oct 30 6:40 PM (Bill): nav bake y -0.6..2.0; late-afternoon sun ~35 deg from the SW.
NAV_BAKE_HEIGHT = 2.6
SUN_ELEVATION_DEG = 35.0
SUN_FROM_AZIMUTH_DEG = 225.0  # compass bearing the light comes FROM (0 = north/-Z, 90 = east/+X)


# Where a filler must stop short of the host's centre (m from the host centre along the wall line).
# BJORN's gate is hollow inside (an open room |x| < 5.6 behind the doors, visible from the courtyard),
# so its fillers run from the wall end to just inside the pier wall (inner face 5.6-6.0 m) and are
# shortened by scaling the 4 m module along its length. Turrets are closed shells: full modules.
# Batch 4 final, wide gate: its side walls are a battered shell (outer face x 7.09 at the ground,
# 6.17 at the wall top 4.74, hollow inside), still 0.9-1.8 m short of the wall run ends at x +-8, so
# both gate fillers stay, shortened to end 0.17 m inside the outer face at the wall top
# (8 -> 6.0 m: 2.0 m long, was 2.2 m). DEVIATIONS.md #31.
FILLER_INNER_EDGE = {"main_gate_yaguramon": 6.0}


def wall_fillers(L, pitch=4.0):
    """One extra wall module past every run end whose next slot lies inside a turret or gate
    footprint (Bill's sizes), so the module tucks into that building's body.
    Returns (id, x, y, z, yaw, length_scale)."""
    walls = [o for o in L.objs if o[1] == "wall_segment_4m"]
    hosts = []
    for o in L.objs:
        if o[1] in ("corner_turret", "main_gate_yaguramon"):
            sx, _, sz = o[6]
            if round(o[5]) % 180:
                sx, sz = sz, sx
            hosts.append((o[2], o[4], sx / 2, sz / 2, FILLER_INNER_EDGE.get(o[1])))
    out, seen = [], set()
    for (oid, _a, x, y, z, yaw, *_r) in walls:
        dx, dz = round(math.cos(math.radians(yaw)), 6), round(-math.sin(math.radians(yaw)), 6)
        for sgn, tag in ((1, "A"), (-1, "B")):
            px, pz = x + sgn * pitch * dx, z + sgn * pitch * dz
            if any(abs(w[2] - px) < 0.5 and abs(w[4] - pz) < 0.5 for w in walls):
                continue
            host = [h for h in hosts if abs(px - h[0]) <= h[2] + 1e-6 and abs(pz - h[1]) <= h[3] + 1e-6]
            if not host:
                continue
            hx, hz, _ex, _ez, inner = host[0]
            scale = 1.0
            if inner:
                ex_, ez_ = x + sgn * pitch / 2 * dx, z + sgn * pitch / 2 * dz  # run end
                ln = math.hypot(ex_ - hx, ez_ - hz) - inner
                scale = ln / pitch
                px, pz = ex_ + sgn * dx * ln / 2, ez_ + sgn * dz * ln / 2
            key = (round(px, 3), round(pz, 3))
            if key not in seen:
                seen.add(key)
                out.append(("%s_Fill%s" % (oid, tag), round(px, 4), y, round(pz, 4), yaw, round(scale, 4)))
    return out


def sun_transform(elev, az_from, origin):
    """DirectionalLight3D shines along its local -Z. Builds the basis so that -Z points away from
    the compass bearing `az_from` and downward at `elev` degrees."""
    e, a = math.radians(elev), math.radians(az_from)
    # unit vector toward the sun (north = -Z, east = +X)
    to_sun = (math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e))
    zb = to_sun  # local +Z points at the sun, so -Z is the light direction
    up = (0.0, 1.0, 0.0)
    xb = (up[1] * zb[2] - up[2] * zb[1], up[2] * zb[0] - up[0] * zb[2], up[0] * zb[1] - up[1] * zb[0])
    n = math.sqrt(sum(c * c for c in xb)); xb = tuple(c / n for c in xb)
    yb = (zb[1] * xb[2] - zb[2] * xb[1], zb[2] * xb[0] - zb[0] * xb[2], zb[0] * xb[1] - zb[1] * xb[0])
    # Transform3D(x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, ox, oy, oz) - columns are basis vectors
    vals = (xb[0], yb[0], zb[0], xb[1], yb[1], zb[1], xb[2], yb[2], zb[2]) + tuple(origin)
    return "Transform3D(%s)" % ", ".join(fmt(round(v, 5)) for v in vals)


def load_blueprint():
    """Executes Bill's layout_data.py from its own location without writing anything there
    (no import, so no __pycache__ is created in his folder)."""
    global BLUEPRINT_SHA
    src = open(BLUEPRINT_SRC, "rb").read()
    BLUEPRINT_SHA = hashlib.sha256(src).hexdigest()
    ns = {"__name__": "layout_data", "__file__": BLUEPRINT_SRC}
    exec(compile(src, BLUEPRINT_SRC, "exec"), ns)
    return type("Layout", (), ns)


def prefab_path(asset, variant=None):
    sub = "modules" if asset in ARCH else "props"
    return "%s/%s/%s%s.tscn" % (RES, sub, asset, "_" + variant if variant else "")


def instance_prefab(oid, asset):
    """Prefab for one blueprint instance: the variant prefab if INSTANCE_VARIANT picks one and its
    GLB is in the repo, else the asset's main prefab."""
    v = INSTANCE_VARIANT.get(oid)
    if v and resolve_variant_path(asset, v):
        return prefab_path(asset, v)
    return prefab_path(asset)


def build_prefab(asset, size, variant=None):
    if variant:
        vp = resolve_variant_path(asset, variant)
        if not vp:
            return
        s = Scene(asset + "_" + variant, vp)
    else:
        s = Scene(asset, resolve_model_path(asset))
    s.asset = asset
    s.model_scale = VARIANTS.get(asset, {}).get(variant, {}).get("scale", 1.0)
    s.authored_size = tuple(AUTHORED_SIZE.get(asset, size))
    sx, sy, sz = size
    # rock_small_cluster: Bill has no collider (MultiMesh decoration); batch 4 adds a fitted box once
    # BJORN's model is in (Kirk, Oct 30 9:35 PM: simple collision on the rocks). DEVIATIONS.md #28.
    cluster_box = asset == "rock_small_cluster" and os.path.isfile(os.path.join(ROOT, s.model_path[len("res://"):]))
    s.begin(collision=asset not in ARCH and (asset not in ("shrub_azalea", "rock_small_cluster") or cluster_box))
    if asset == "wall_segment_4m":
        s.box("Base", (0, 0.6, 0), (sx, 1.2, sz + 0.1), "stone")
        s.box("Plaster", (0, 2.8, 0), (sx, 3.2, sz), "plaster")
        s.box("Cap", (0, sy - 0.3, 0), (sx, 0.6, sz + 0.5), "tile")
    elif asset == "corner_turret":
        s.box("Base", (0, 2, 0), (sx, 4, sz), "stone")
        s.box("Body", (0, 6.25, 0), (sx - 1, 4.5, sz - 1), "plaster")
        s.box("Roof", (0, sy - 0.75, 0), (sx + 0.6, 1.5, sz + 0.6), "tile")
    elif asset == "main_gate_yaguramon":
        for x in (-6, 6):
            s.box("Pier%+d" % x, (x, 2.25, 0), (4, 4.5, sz), "stone")
        s.box("Doors", (0, 2.25, 0), (8, 4.5, 0.4), "lacquer")
        s.box("House", (0, 6.25, 0), (sx, 3.5, sz - 1), "plaster")
        s.box("Roof", (0, 9, 0), (sx + 1, 2, sz + 1), "tile")
    elif asset in ("main_hall_goten", "barracks_nagaya", "storehouse_kura"):
        base = 1.0 if asset == "main_hall_goten" else 0.5
        roof = 3.5 if asset == "main_hall_goten" else 2.0
        mat = "plaster" if asset == "storehouse_kura" else "wood"
        s.box("Base", (0, base / 2, 0), (sx, base, sz), "stone")
        s.box("Body", (0, base + (sy - base - roof) / 2, 0), (sx - 1, sy - base - roof, sz - 1), mat)
        s.box("Roof", (0, sy - roof / 2, 0), (sx + 0.8, roof, sz + 0.8), "tile")
    elif asset == "castle_keep_tenshu":
        s.box("Base", (0, 4, 0), (sx, 8, sz), "stone")
        y = 8
        for i, (w, d) in enumerate([(24, 17), (18, 13), (12, 9)]):
            s.box("Tier%d" % i, (0, y + 2.5, 0), (w, 5, d), "plaster")
            s.box("Roof%d" % i, (0, y + 5.5, 0), (w + 2, 1, d + 2), "tile")
            y += 6.5
    elif asset == "bridge_arched_taikobashi":
        # Local X = length (13 m), deck width on Z. Same boxes as the arena colliders: chords that
        # follow BJORN's deck profile (ARCH_PROFILE), each with a rail whose top is 1.0 m above it.
        for i, (cx, cy, ln, deg) in enumerate(arch_segments()):
            s.box("Deck%d" % i, (cx, cy, 0), (ln, ARCH_DECK_T, sz), "lacquer", rot=("z", deg))
            for z in (-ARCH_RAIL_Z, ARCH_RAIL_Z):
                rx, ry = arch_rail_centre(cx, cy, deg)
                s.box("Rail%d%+.2f" % (i, z), (rx, ry, z), (ln, ARCH_RAIL_H, ARCH_RAIL_T), "lacquer", rot=("z", deg))
    elif asset == "bridge_stone_slab":
        s.box("Slab", (0, -0.15, 0), (sx, sy, sz), "stone")
    elif asset == "pond_edge_stones_2m":
        s.box("Stones", (0, 0.15, 0), (sx, 0.3, sz), "stone")
    elif asset == "stone_lantern_toro_2m":
        s.box("Plinth", (0, 0.15, 0), (0.9, 0.3, 0.9), "stone")
        s.cyl("Pillar", (0, 0.8, 0), 0.16, 0.2, 1.0, "stone", 8)
        s.box("Firebox", (0, 1.48, 0), (0.6, 0.36, 0.6), "stone")
        s.cyl("Roof", (0, 1.8, 0), 0.08, 0.5, 0.28, "stone", 6)
        s.cyl("Finial", (0, 1.98, 0), 0.0, 0.07, 0.12, "stone", 6)
        s.col_cyl("Shape", (0, 1.0, 0), 0.45, 2.0)
    elif asset.startswith("tree_"):
        pine = asset == "tree_pine_kuromatsu"
        tx, tz, r, h = TREE_TRUNK[asset]
        leaf = "foliage" if pine else "lacquer" if "maple" in asset else "plaster"
        s.cyl("Trunk", (tx, sy * 0.3, tz), r * 0.7, r, sy * 0.6, "bark", 8)
        s.sphere("Canopy", (0, sy * 0.7, 0), sx / 2, sy * 0.55, leaf)
        s.col_cyl("Trunk", (tx, h / 2, tz), r, h)
    elif asset == "shrub_azalea":
        s.sphere("Body", (0, sy / 2, 0), sx / 2, sy, "foliage")
    elif asset.startswith("rock_"):
        s.sphere("Body", (0, sy / 2, 0), max(sx, sz) / 2, sy, "stone")
        var = VARIANTS.get(asset, {}).get(variant)
        model_in_repo = os.path.isfile(os.path.join(ROOT, s.model_path[len("res://"):]))
        if var and model_in_repo:
            # Batch 4: one box fitted to BJORN's model (VARIANTS); Bill's box was for the graybox.
            s.col_box("Shape", *var["collider"])
        elif asset == "rock_formation_large":
            s.col_box("Shape", (0, 0.9, 0), (2.6, 1.8, 2.1))
        elif asset == "rock_medium":
            s.col_box("Shape", (0, 0.45, 0), (1.3, 0.9, 1.0))
    else:  # unknown blueprint asset: authored-size box, no collision
        s.box("Box", (0, sy / 2, 0), size, "stone")
    s.save(prefab_path(asset, variant)[len(RES) + 1:])


# ---------------------------------------------------------------------------------------
# Arena
# ---------------------------------------------------------------------------------------

def courtyard_arena(L):
    s = Scene("Arena", script=False, notes="GENERATED by tools/courtyard/gen_graybox.py from %s (sha256 %s).\n"
              "Do not hand-edit; change the blueprint and re-run the generator." % (BLUEPRINT_SRC, BLUEPRINT_SHA))
    script = s._ext("Script", RES + "/scripts/courtyard_arena.gd")
    sky_mat = s.sub("ProceduralSkyMaterial", [
        ("sky_top_color", "Color(0.36, 0.5, 0.7, 1)"), ("sky_horizon_color", "Color(0.86, 0.74, 0.62, 1)"),
        ("ground_bottom_color", "Color(0.2, 0.18, 0.16, 1)"), ("ground_horizon_color", "Color(0.86, 0.74, 0.62, 1)"),
        ("sun_angle_max", "20.0")])
    sky = s.sub("Sky", [("sky_material", sky_mat)])
    env = s.sub("Environment", [
        ("background_mode", "2"), ("sky", sky), ("ambient_light_source", "3"),
        ("ambient_light_color", "Color(0.75, 0.72, 0.68, 1)"), ("ambient_light_sky_contribution", "0.7"),
        ("ambient_light_energy", "0.8"), ("tonemap_mode", "2"), ("tonemap_exposure", "0.9"),
        ("fog_enabled", "true"), ("fog_light_color", "Color(0.8, 0.72, 0.64, 1)"), ("fog_density", "0.004"),
        ("adjustment_enabled", "true"), ("adjustment_saturation", "0.92")])
    nav = s.sub("NavigationMesh", [])

    s.node("Arena", "Node3D", None, [("script", 'ExtResource("%s")' % script),
           ("nav_bake_aabb", "AABB(-40, -0.6, -47, 80, %s, 82)" % fmt(NAV_BAKE_HEIGHT))])

    # ---- Collision (blueprint section 7): layer 1, mask 0, group nav_source ----
    s.node("Collision", "Node3D", ".", groups=["nav_source"])
    bodies = set()

    def col(group, name, pos, size, rot=None, cyl=None, xf=None):
        if group not in bodies:
            s.node(group, "StaticBody3D", "Collision", [("collision_layer", "1"), ("collision_mask", "0")])
            bodies.add(group)
        if cyl:
            sh = s.sub("CylinderShape3D", [("radius", fmt(cyl[0])), ("height", fmt(cyl[1]))])
        else:
            sh = s.sub("BoxShape3D", [("size", vec(size))])
        s.node(name, "CollisionShape3D", "Collision/" + group, [("transform", xf or xform(pos, rot)), ("shape", sh)])

    col("Ground", "G1_West", (-7.75, -0.5, -6), (64.5, 1, 80))
    col("Ground", "G2_EastStrip", (37.75, -0.5, -6), (4.5, 1, 80))
    col("Ground", "G3_NorthOfPond", (30, -0.5, -25.5), (11, 1, 41))
    col("Ground", "G4_SouthOfPond", (30, -0.5, 19.5), (11, 1, 29))
    col("Ground", "PondBasin", (30, -1.3, 0), (11, 0.2, 10))
    # Simple boxes fitted to the measured BJORN mesh bounds (ground footprint, full height;
    # tools/courtyard/glb_probe.py, DEVIATIONS.md #20). One box per straight wall run, each
    # running 0.1 m into the turret / gate boxes at its ends so no gap opens at a seam.
    WALL_H, WALL_T = 4.74, 1.5            # wall_segment_4m: y 0..4.74, base z -0.75..0.74
    TUR_HX, TUR_HZ, TUR_H = 3.74, 3.73, 10.72
    # Batch 4 final: main_gate_yaguramon_wide ground footprint x -7.09..7.07, z -3.82..3.84, height
    # 10.43 (was 6.76, -3.08, 3.32, 10.91 for the 14.67 m gate). DEVIATIONS.md #31.
    GATE_HX, GATE_Z0, GATE_Z1, GATE_H = 7.08, -3.82, 3.84, 10.43   # local; placed at yaw 180
    n_x = 40 - TUR_HX + 0.1               # N run: turret face to turret face
    col("WallRuns", "N", (0, WALL_H / 2, -46), (2 * n_x, WALL_H, WALL_T))
    ew_z0, ew_z1 = -46 + TUR_HZ - 0.1, 34 - TUR_HZ + 0.1   # E/W runs: N turret face to S turret face
    for nm, x in (("E", 40), ("W", -40)):
        col("WallRuns", nm, (x, WALL_H / 2, (ew_z0 + ew_z1) / 2), (WALL_T, WALL_H, ew_z1 - ew_z0))
    s_x0, s_x1 = GATE_HX - 0.1, 40 - TUR_HX + 0.1          # S runs: gate side to turret face
    col("WallRuns", "SW", (-(s_x0 + s_x1) / 2, WALL_H / 2, 34), (s_x1 - s_x0, WALL_H, WALL_T))
    col("WallRuns", "SE", ((s_x0 + s_x1) / 2, WALL_H / 2, 34), (s_x1 - s_x0, WALL_H, WALL_T))
    for nm, x, z in (("NW", -40, -46), ("NE", 40, -46), ("SW", -40, 34), ("SE", 40, 34)):
        col("Turrets", nm, (x, TUR_H / 2, z), (2 * TUR_HX, TUR_H, 2 * TUR_HZ))
    # Gate at yaw 180: local +Z (BJORN's door side) is world -Z, so the courtyard face is at
    # z = 34 - 3.84 = 30.16. Doors closed: the box spans the whole gate.
    col("Gate", "Gate", (0, GATE_H / 2, 34 - (GATE_Z0 + GATE_Z1) / 2), (2 * GATE_HX, GATE_H, GATE_Z1 - GATE_Z0))
    # main_hall_goten at yaw 0: ground x +-11.20, z -5.78..6.00, height 9.42.
    col("Buildings", "Hall", (0, 9.42 / 2, -39 + (-5.78 + 6.00) / 2), (22.4, 9.42, 11.78))
    col("Buildings", "Barracks", (-36, 3, 0), (6, 6, 24))
    col("Buildings", "Kura", (-31, 3.5, -36), (6, 7, 8))
    col("Pond", "FenceW", (24.35, 0.45, 0), (0.3, 0.9, 10.6))
    col("Pond", "FenceE", (35.65, 0.45, 0), (0.3, 0.9, 10.6))
    for side, z in (("N", -5.15), ("S", 5.15)):
        for i, (x0, x1) in enumerate(((24.5, 25), (27, 29.8), (32.2, 35.5))):
            col("Pond", "Fence%s%d" % (side, i), ((x0 + x1) / 2, 0.45, z), (x1 - x0, 0.9, 0.3))
    # Arch bridge: deck chords following BJORN's arch (ARCH_PROFILE) + a rail box per chord on each
    # side, top 1.0 m above the walking surface. Placed through the blueprint instance transform.
    arch = [o for o in L.objs if o[1] == "bridge_arched_taikobashi"][0]
    for i, (cx, cy, ln, deg) in enumerate(arch_segments()):
        wp, basis = place(arch[2:5], arch[5], (cx, cy, 0), deg)
        col("Bridges", "ArchDeck%d" % i, None, (ln, ARCH_DECK_T, 2.4), xf=xform_basis(wp, basis))
        rx, ry = arch_rail_centre(cx, cy, deg)
        for side, z in (("R", -ARCH_RAIL_Z), ("L", ARCH_RAIL_Z)):
            wp, basis = place(arch[2:5], arch[5], (rx, ry, z), deg)
            col("Bridges", "ArchRail%s%d" % (side, i), None, (ln, ARCH_RAIL_H, ARCH_RAIL_T), xf=xform_basis(wp, basis))
    col("Bridges", "SlabDeck", (26, -0.15, 0), (2.0, 0.3, 11))
    col("Bridges", "SlabRailW", (24.925, 0.45, 0), (0.15, 0.9, 10))
    col("Bridges", "SlabRailE", (27.075, 0.45, 0), (0.15, 0.9, 10))
    # Pond stones (batch 4 final; Bill: no collision, the pond fence blocks): one box per stone,
    # fitted to the model (POND_STONE_BOX), at its PLACE_OVERRIDE position. DEVIATIONS.md #29.
    if os.path.isfile(os.path.join(ROOT, resolve_model_path("pond_edge_stones_2m")[len("res://"):])):
        for (oid, asset, x, y, z, yaw, *_r) in L.objs:
            if asset != "pond_edge_stones_2m":
                continue
            x, z, yaw = PLACE_OVERRIDE.get(oid, (x, z, yaw))
            v = INSTANCE_VARIANT.get(oid) if resolve_variant_path(asset, INSTANCE_VARIANT.get(oid) or "-") else None
            hx, y0, y1, hz = POND_STONE_BOX[v]
            col("PondStones", oid, (x, (y0 + y1) / 2, z), (2 * hx, y1 - y0, 2 * hz), rot=("y", yaw))

    # Props with their own colliders (lanterns, trees, rocks, shrubs) stay inside nav_source.
    s.node("Props", "Node3D", "Collision")
    groups_made = set()
    for (oid, asset, x, y, z, yaw, size, colnote, *_rest) in L.objs:
        if asset in ARCH:
            continue
        grp = {"stone": "Lanterns"}.get(asset.split("_")[0], asset.split("_")[0].capitalize() + "s")
        if grp not in groups_made:
            s.node(grp, "Node3D", "Collision/Props"); groups_made.add(grp)
        yaw = YAW_OVERRIDE.get(oid, yaw)
        s.node(oid, None, "Collision/Props/" + grp, [("transform", xform((x, y, z), ("y", yaw)))], instance=instance_prefab(oid, asset))

    # ---- Visual: no colliders ----
    s.node("Visual", "Node3D", ".")
    s.node("Ground", "Node3D", "Visual")
    for nm, pos, size in (("G1", (-7.75, -0.03, -6), (64.5, 0.06, 80)), ("G2", (37.75, -0.03, -6), (4.5, 0.06, 80)),
                          ("G3", (30, -0.03, -25.5), (11, 0.06, 41)), ("G4", (30, -0.03, 19.5), (11, 0.06, 29))):
        s.node(nm, "MeshInstance3D", "Visual/Ground", [("transform", xform(pos)), ("mesh", s.sub("BoxMesh", [("size", vec(size))])),
               ("material_override", s.mat("grass")), ("cast_shadow", "0")])
    # Grass outside the walls: a ring of four boxes around the courtyard ground (x -40..40,
    # z -46..34). A single 200 x 200 plane here covered the pond water (y -0.3) - found in the
    # windowed screenshots.
    for nm, pos, size in (("OuterGrassN", (0, -0.08, -96.5), (200, 0.05, 101)), ("OuterGrassS", (0, -0.08, 69), (200, 0.05, 70)),
                          ("OuterGrassW", (-70.25, -0.08, -6), (60.5, 0.05, 80)), ("OuterGrassE", (70.25, -0.08, -6), (60.5, 0.05, 80))):
        s.node(nm, "MeshInstance3D", "Visual/Ground", [("transform", xform(pos)), ("mesh", s.sub("BoxMesh", [("size", vec(size))])),
               ("material_override", s.mat("grass")), ("cast_shadow", "0")])
    s.node("Gravel", "MeshInstance3D", "Visual/Ground", [("transform", xform((0, 0.005, 0))),
           ("mesh", s.sub("BoxMesh", [("size", "Vector3(40, 0.01, 40)")])), ("material_override", s.mat("gravel")), ("cast_shadow", "0")])
    s.node("Paths", "Node3D", "Visual")
    for (nm, x0, z0, x1, z1, w) in L.PATHS:
        # The bridge spur paths (P5, P6) run straight across the pond; the strip over the water is
        # skipped (it covered the slab deck 2 cm above it and floated over the water under the
        # arch). Split at the pond edges z = +-5 (DEVIATIONS.md #24). Visual only.
        segs = [(nm.split(" ")[0], x0, z0, x1, z1)]
        if x0 == x1 and POND_X[0] < x0 < POND_X[1] and min(z0, z1) < -POND_HZ and max(z0, z1) > POND_HZ:
            lo, hi = min(z0, z1), max(z0, z1)
            segs = [(segs[0][0] + "N", x0, lo, x0, -POND_HZ), (segs[0][0] + "S", x0, POND_HZ, x0, hi)]
        for (pn, a0, b0, a1, b1) in segs:
            size = (abs(a1 - a0), 0.02, w) if b0 == b1 else (w, 0.02, abs(b1 - b0))
            s.node(pn, "MeshInstance3D", "Visual/Paths", [("transform", xform(((a0 + a1) / 2, 0.01, (b0 + b1) / 2))),
                   ("mesh", s.sub("BoxMesh", [("size", vec(size))])), ("material_override", s.mat("path")), ("cast_shadow", "0")])
    s.node("Pond", "Node3D", "Visual")
    s.node("Water", "MeshInstance3D", "Visual/Pond", [("transform", xform((30, -0.3, 0))),
           ("mesh", s.sub("BoxMesh", [("size", "Vector3(11, 0.02, 10)")])), ("material_override", s.mat("water")), ("cast_shadow", "0")])
    s.node("Basin", "MeshInstance3D", "Visual/Pond", [("transform", xform((30, -1.25, 0))),
           ("mesh", s.sub("BoxMesh", [("size", "Vector3(11, 0.1, 10)")])), ("material_override", s.mat("stone")), ("cast_shadow", "0")])
    vis_groups = {"wall_segment_4m": "Walls", "corner_turret": "Turrets", "main_gate_yaguramon": "Gate",
                  "castle_keep_tenshu": "Keep", "bridge_arched_taikobashi": "Bridges", "bridge_stone_slab": "Bridges",
                  "pond_edge_stones_2m": "Pond"}
    made = {"Pond"}
    for (oid, asset, x, y, z, yaw, size, colnote, *_rest) in L.objs:
        if asset not in ARCH:
            continue
        grp = vis_groups.get(asset, "Buildings")
        if grp not in made:
            s.node(grp, "Node3D", "Visual"); made.add(grp)
        x, z, yaw = PLACE_OVERRIDE.get(oid, (x, z, yaw))
        s.node(oid, None, "Visual/" + grp, [("transform", xform((x, y, z), ("y", yaw)))], instance=instance_prefab(oid, asset))
    # Visual-only filler wall modules hidden inside the turret / gate bodies (DEVIATIONS.md #13):
    # BJORN's turret has a battered base and the gate body is narrower than Bill's footprint, so
    # the wall runs ending at the footprint edge would leave see-through gaps. Collision unchanged.
    for (fid, x, y, z, yaw, k) in wall_fillers(L):
        s.node(fid, None, "Visual/Walls", [("transform", xform((x, y, z), ("y", yaw), (k, 1, 1)))], instance=prefab_path("wall_segment_4m"))

    # ---- Gameplay interface (names main.gd / arena.gd rely on) ----
    s.node("NavigationRegion3D", "NavigationRegion3D", ".", [("navigation_mesh", nav)])
    s.node("PlayerStart", "Marker3D", ".", [("transform", xform(L.PLAYER))])
    s.node("SpawnPoints", "Node3D", ".")
    for (nm, x, z) in L.SPAWNS:
        s.node(nm.split("/")[-1], "Marker3D", "SpawnPoints", [("transform", xform((x, 0.1, z)))])
    s.node("Sun", "DirectionalLight3D", ".", [
        ("transform", sun_transform(SUN_ELEVATION_DEG, SUN_FROM_AZIMUTH_DEG, (0, 12, 0))),
        ("light_color", "Color(1, 0.86, 0.7, 1)"), ("light_energy", "1.05"), ("shadow_enabled", "true"),
        ("shadow_opacity", "0.8"), ("shadow_blur", "1.5"), ("directional_shadow_max_distance", "80.0"),
        # 2 PSSM splits instead of 4: the shadow passes were ~74% of the rendered primitives.
        ("directional_shadow_mode", "1")])
    s.node("WorldEnvironment", "WorldEnvironment", ".", [("environment", env)])
    s.save("scenes/castle_courtyard.tscn")


def prefab_gallery(L):
    s = Scene("PrefabGallery", script=False)
    s.node("PrefabGallery", "Node3D", None)
    seen = {}
    for o in L.objs:
        seen.setdefault(o[1], o[6])
    x = 0.0
    for asset, size in seen.items():
        for v in [None] + [k for k in VARIANTS.get(asset, {}) if k and resolve_variant_path(asset, k)]:
            x += size[0] / 2 + 2
            s.node(asset + ("_" + v if v else ""), None, ".", [("transform", xform((x, 0, 0)))], instance=prefab_path(asset, v))
            x += size[0] / 2
    s.node("Sun", "DirectionalLight3D", ".", [("rotation", "Vector3(-0.85, 0.65, 0)"), ("shadow_enabled", "true")])
    s.save("scenes/prefab_gallery.tscn")


if __name__ == "__main__":
    L = load_blueprint()
    gen_materials()
    for asset in sorted({o[1] for o in L.objs}):
        build_prefab(asset, next(o[6] for o in L.objs if o[1] == asset))
        for v in VARIANTS.get(asset, {}):
            if v:
                build_prefab(asset, next(o[6] for o in L.objs if o[1] == asset), v)
    courtyard_arena(L)
    prefab_gallery(L)
    print("graybox generated from %s (sha256 %s): %d objects, %d prefabs" % (BLUEPRINT_SRC, BLUEPRINT_SHA[:12], len(L.objs), len({o[1] for o in L.objs})))
