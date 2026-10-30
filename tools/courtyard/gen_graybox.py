#!/usr/bin/env python3
"""Generates the Kengeki courtyard graybox modules, props, shared materials and the
courtyard skeleton scenes under res://environment/courtyard/.

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
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in xa + ya + za + list(pos))


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


# ---------------------------------------------------------------------------------------
# Architectural modules
# ---------------------------------------------------------------------------------------

def wall(length):
    name = "wall_straight_%dm" % length
    s = Scene(name, asset_path("Architecture", "castle_wall_%dm" % length))
    s.begin()
    # 1.2 m stone base, 3.8 m plaster, tiled cap = 5.4 m total; 1.2 m thick.
    s.box("StoneBase", (0, 0.6, 0), (length, 1.2, 1.3), "stone")
    s.box("Plaster", (0, 3.1, 0), (length, 3.8, 1.0), "plaster")
    s.box("Beam", (0, 4.85, 0), (length, 0.3, 1.1), "wood")
    s.box("RoofCap", (0, 5.2, 0), (length + 0.02, 0.4, 1.9), "tile")
    s.col_box("Shape", (0, 2.7, 0), (length, 5.4, 1.2))
    s.save("modules/%s.tscn" % name)


def wall_corner():
    s = Scene("wall_corner", asset_path("Architecture", "castle_wall_corner"))
    s.begin()
    s.box("StoneBase", (0, 0.75, 0), (1.6, 1.5, 1.6), "stone")
    s.box("Plaster", (0, 3.25, 0), (1.4, 3.5, 1.4), "plaster")
    s.box("RoofCap", (0, 5.25, 0), (2.2, 0.5, 2.2), "tile")
    s.col_box("Shape", (0, 2.75, 0), (1.6, 5.5, 1.6))
    s.save("modules/wall_corner.tscn")


def gate_main():
    # Yakuimon / kabukimon style gate: 8 m wide, 4 m x 4.2 m opening, ~7.2 m tall. Doors closed
    # (the area outside the walls is not playable); enemies spawn just inside.
    s = Scene("gate_main", asset_path("Architecture", "main_gate"))
    s.begin()
    for side in (-1, 1):
        s.box("SideWall%s" % ("L" if side < 0 else "R"), (side * 3.0, 2.7, 0), (2.0, 5.4, 1.2), "plaster")
        s.box("SideBase%s" % ("L" if side < 0 else "R"), (side * 3.0, 0.6, 0), (2.0, 1.2, 1.3), "stone")
        s.box("Post%s" % ("L" if side < 0 else "R"), (side * 2.15, 2.6, 0.2), (0.45, 5.2, 0.45), "lacquer")
    s.box("Lintel", (0, 4.9, 0.2), (5.4, 0.45, 0.5), "lacquer")
    s.box("Doors", (0, 2.1, -0.1), (3.9, 4.2, 0.25), "wood")
    s.box("RoofBase", (0, 5.6, 0), (8.6, 0.6, 2.8), "tile")
    s.box("RoofRidge", (0, 6.6, 0), (6.0, 0.9, 1.4), "tile")
    s.box("RoofRidgeCap", (0, 7.15, 0), (6.6, 0.2, 0.3), "tile")
    s.col_box("SideL", (-3.0, 2.7, 0), (2.0, 5.4, 1.2))
    s.col_box("SideR", (3.0, 2.7, 0), (2.0, 5.4, 1.2))
    s.col_box("Doors", (0, 2.7, 0), (4.0, 5.4, 1.2))
    s.save("modules/gate_main.tscn")


def bridge_arched():
    # Taiko-bashi style bridge approximated by ramp / flat / ramp. 8 m long (X), 2.2 m walkable
    # width, 0.6 m crown height. Ramp slope 11.3 deg: within CharacterBody3D floor_max_angle (45)
    # and climbable by the nav agent (slope, not step). Rails 1 m tall block falling into the pond.
    s = Scene("bridge_arched_8m", asset_path("Architecture", "arched_bridge"))
    s.begin()
    run, rise, flat, th, w = 3.0, 0.6, 2.0, 0.2, 2.2
    a = math.degrees(math.atan2(rise, run))
    slope_len = math.hypot(run, rise)
    sa, ca = math.sin(math.radians(a)), math.cos(math.radians(a))
    for sign, nm in ((-1, "Up"), (1, "Down")):
        # top surface centre of the ramp, then push down half the thickness along its normal
        cx, cy = sign * (flat / 2 + run / 2), rise / 2
        nx, ny = (-sa if sign < 0 else sa), ca
        c = (cx - nx * th / 2, cy - ny * th / 2, 0)
        rot = ("z", a if sign < 0 else -a)
        s.box("Ramp%s" % nm, c, (slope_len, th, w), "wood", rot)
        s.col_box("Ramp%s" % nm, c, (slope_len, th, w), rot)
        for side in (-1, 1):
            rc = (cx, cy + 0.5, side * (w / 2 + 0.06))
            s.box("Rail%s%s" % (nm, "L" if side < 0 else "R"), rc, (slope_len, 0.12, 0.12), "lacquer", rot)
            s.col_box("Rail%s%s" % (nm, "L" if side < 0 else "R"), (cx, cy + 0.5, side * (w / 2 + 0.06)), (slope_len, 1.0, 0.12), rot)
    s.box("Crown", (0, rise - th / 2, 0), (flat, th, w), "wood")
    s.col_box("Crown", (0, rise - th / 2, 0), (flat, th, w))
    for side in (-1, 1):
        s.box("CrownRail%s" % ("L" if side < 0 else "R"), (0, rise + 0.5, side * (w / 2 + 0.06)), (flat, 0.12, 0.12), "lacquer")
        s.col_box("CrownRail%s" % ("L" if side < 0 else "R"), (0, rise + 0.5, side * (w / 2 + 0.06)), (flat, 1.0, 0.12))
        for px in (-3.6, -1.0, 1.0, 3.6):
            y_top = rise * min(1.0, (4.0 - abs(px)) / run) if abs(px) > 1.0 else rise
            s.box("Post%s%d" % ("L" if side < 0 else "R", int(px * 10)), (px, (y_top + 1.0) / 2 - 0.2, side * (w / 2 + 0.06)), (0.14, y_top + 1.0 + 0.4, 0.14), "lacquer")
    s.save("modules/bridge_arched_8m.tscn")


def pond():
    # 12 m (X) x 7 m (Z) decorative pond, shallow water visual, stone rim, and an invisible 1 m
    # barrier on layer 1 so neither the player nor the navmesh enters the water. Gaps 2.4 m wide
    # at the middle of both long sides (local +-Z) let bridge_arched_8m (rotated 90 deg) cross.
    s = Scene("pond_12x7", asset_path("Landscape", "koi_pond"))
    s.begin()
    L, W, gap, rim = 12.0, 7.0, 2.4, 0.5
    s.box("Water", (0, 0.03, 0), (L, 0.02, W), "water")
    s.box("RimN", (0, 0.15, -W / 2 - rim / 2), (L + 2 * rim, 0.3, rim), "stone")
    s.box("RimS", (0, 0.15, W / 2 + rim / 2), (L + 2 * rim, 0.3, rim), "stone")
    s.box("RimW", (-L / 2 - rim / 2, 0.15, 0), (rim, 0.3, W), "stone")
    s.box("RimE", (L / 2 + rim / 2, 0.15, 0), (rim, 0.3, W), "stone")
    seg = (L + 2 * rim - gap) / 2
    for zs, nm in ((-1, "N"), (1, "S")):
        for xs, side in ((-1, "W"), (1, "E")):
            s.col_box("Barrier%s%s" % (nm, side), (xs * (gap / 2 + seg / 2), 0.5, zs * (W / 2 + rim / 2)), (seg, 1.0, rim))
    s.col_box("BarrierW", (-L / 2 - rim / 2, 0.5, 0), (rim, 1.0, W))
    s.col_box("BarrierE", (L / 2 + rim / 2, 0.5, 0), (rim, 1.0, W))
    # Water volume blockers (invisible) keep the player and navmesh off the water, leaving a
    # 2.6 m corridor at x=0 where the bridge crosses (the bridge rails close that corridor).
    half = (L / 2 - 1.3)
    for xs, nm in ((-1, "W"), (1, "E")):
        s.col_box("WaterBlock%s" % nm, (xs * (1.3 + half / 2), 0.5, 0), (half, 1.0, W))
    s.save("modules/pond_12x7.tscn")


def building_hall():
    s = Scene("building_hall_10x7", asset_path("Architecture", "hall_building"))
    s.begin()
    s.box("Plinth", (0, 0.3, 0), (10.4, 0.6, 7.4), "stone")
    s.box("Body", (0, 2.4, 0), (10.0, 3.6, 7.0), "plaster")
    for x in (-4.8, -1.6, 1.6, 4.8):
        s.box("Pillar%d" % int(x * 10), (x, 2.4, 3.55), (0.3, 3.6, 0.3), "wood")
    s.box("Eave", (0, 4.5, 0), (12.0, 0.4, 9.0), "tile")
    s.box("Roof", (0, 5.4, 0), (9.0, 1.4, 5.6), "tile")
    s.col_box("Shape", (0, 2.4, 0), (10.4, 4.8, 7.4))
    s.save("modules/building_hall_10x7.tscn")


def path_segment():
    s = Scene("path_stone_4m", asset_path("Landscape", "stone_path_4m"))
    s.begin(collision=False)  # flush with the ground: visual only
    for i, z in enumerate((-1.5, -0.5, 0.5, 1.5)):
        s.box("Slab%d" % i, (0.08 * ((i % 2) * 2 - 1), 0.01, z), (2.2, 0.02, 0.9), "path", shadow=False)
    s.save("modules/path_stone_4m.tscn")


# ---------------------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------------------

def lantern():
    # Matches BJORN's first batch: Decorations/stone_lantern_toro, 2.0 m tall, origin at base.
    s = Scene("lantern_toro", asset_path("Decorations", "stone_lantern_toro"))
    s.begin()
    s.box("Plinth", (0, 0.15, 0), (0.9, 0.3, 0.9), "stone")
    s.cyl("Pillar", (0, 0.8, 0), 0.16, 0.2, 1.0, "stone", 8)
    s.box("Firebox", (0, 1.48, 0), (0.6, 0.36, 0.6), "stone")
    s.cyl("Roof", (0, 1.8, 0), 0.08, 0.5, 0.28, "stone", 6)
    s.cyl("Finial", (0, 1.98, 0), 0.0, 0.07, 0.12, "stone", 6)
    s.col_cyl("Shape", (0, 1.0, 0), 0.42, 2.0)  # same radius as the placeholder arena lantern
    s.save("props/lantern_toro.tscn")


def tree_pine():
    s = Scene("tree_pine", asset_path("Vegetation", "japanese_pine"))
    s.begin()
    s.cyl("Trunk", (0, 1.75, 0), 0.22, 0.38, 3.5, "bark", 8)
    s.sphere("CanopyA", (0, 4.0, 0), 1.8, 1.4, "foliage")
    s.sphere("CanopyB", (1.3, 3.4, 0.4), 1.3, 1.0, "foliage")
    s.sphere("CanopyC", (-1.1, 3.6, -0.6), 1.2, 0.9, "foliage")
    s.col_cyl("Trunk", (0, 1.5, 0), 0.45, 3.0)  # trunk only; canopy is above head height
    s.save("props/tree_pine.tscn")


def rock_large():
    s = Scene("rock_large", asset_path("Landscape", "garden_rock_large"))
    s.begin()
    s.sphere("Body", (0, 0.45, 0), 0.9, 1.1, "stone")
    s.col_box("Shape", (0, 0.45, 0), (1.5, 0.9, 1.3))
    s.save("props/rock_large.tscn")


# ---------------------------------------------------------------------------------------
# Scenes
# ---------------------------------------------------------------------------------------

def courtyard_arena():
    """Skeleton courtyard: same 40 x 40 m walled footprint, gates, player start, spawn markers
    and lantern/tree obstacle positions as scenes/arena/arena.tscn, rebuilt from modules.
    Bill's blueprint replaces the Layout contents; node names the game relies on stay fixed."""
    s = Scene("Arena", script=False)
    script = s._ext("Script", RES + "/scripts/courtyard_arena.gd")
    M = lambda n: RES + "/modules/%s.tscn" % n
    P = lambda n: RES + "/props/%s.tscn" % n
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
    ground_shape = s.sub("BoxShape3D", [("size", "Vector3(120, 1, 120)")])
    grass = s.sub("BoxMesh", [("size", "Vector3(120, 0.1, 120)")])
    gravel = s.sub("BoxMesh", [("size", "Vector3(40, 0.04, 40)")])

    s.node("Arena", "Node3D", None, [("script", 'ExtResource("%s")' % script)])
    s.node("Layout", "Node3D", ".", groups=["nav_source"])
    s.node("Ground", "StaticBody3D", "Layout", [("collision_layer", "1"), ("collision_mask", "0")])
    s.node("Shape", "CollisionShape3D", "Layout/Ground", [("transform", xform((0, -0.5, 0))), ("shape", ground_shape)])
    s.node("Grass", "MeshInstance3D", "Layout/Ground", [("transform", xform((0, -0.06, 0))), ("mesh", grass),
           ("material_override", s.mat("grass")), ("cast_shadow", "0")])
    s.node("Gravel", "MeshInstance3D", "Layout/Ground", [("transform", xform((0, -0.02, 0))), ("mesh", gravel),
           ("material_override", s.mat("gravel")), ("cast_shadow", "0")])

    # Bounds: inner wall faces at +-20 m (as the placeholder), walls 1.2 m thick -> centre 20.6.
    s.node("Bounds", "Node3D", "Layout")
    c = 20.6
    sides = {"North": ((0, 0, -c), 0), "South": ((0, 0, c), 180), "East": ((c, 0, 0), -90), "West": ((-c, 0, 0), 90)}
    for side, (pos, yaw) in sides.items():
        s.node(side, "Node3D", "Layout/Bounds", [("transform", xform(pos, ("y", yaw)))])
        s.node("Gate", None, "Layout/Bounds/%s" % side, instance=M("gate_main"))
        # 16 m each side of the 8 m gate: 6 + 6 + 4
        for i, (x, ln) in enumerate([(-7, 6), (-13, 6), (-18, 4), (7, 6), (13, 6), (18, 4)]):
            s.node("Wall%d" % i, None, "Layout/Bounds/%s" % side, [("transform", xform((x, 0, 0)))],
                   instance=M("wall_straight_%dm" % ln))
    for i, (x, z) in enumerate([(-c, -c), (c, -c), (c, c), (-c, c)]):
        s.node("Corner%d" % i, None, "Layout/Bounds", [("transform", xform((x, 0, z)))], instance=M("wall_corner"))

    s.node("Paths", "Node3D", "Layout")
    for i in range(10):
        z = -18 + i * 4
        if abs(z) > 3:
            s.node("NS%d" % i, None, "Layout/Paths", [("transform", xform((0, 0, z)))], instance=M("path_stone_4m"))
            s.node("EW%d" % i, None, "Layout/Paths", [("transform", xform((z, 0, 0), ("y", 90)))], instance=M("path_stone_4m"))

    s.node("Props", "Node3D", "Layout")
    for i, (x, z) in enumerate([(8, 8), (-8, 8), (8, -8), (-8, -8)]):
        s.node("Lantern%d" % i, None, "Layout/Props", [("transform", xform((x, 0, z), ("y", 15 + 37 * i)))], instance=P("lantern_toro"))
    s.node("Tree0", None, "Layout/Props", [("transform", xform((-17, 0, -17)))], instance=P("tree_pine"))

    # Reserved for Bill's blueprint (pond, bridges, buildings, landscaping). Empty on purpose.
    s.node("Water", "Node3D", "Layout")
    s.node("Buildings", "Node3D", "Layout")
    s.node("Landscaping", "Node3D", "Layout")

    s.node("NavigationRegion3D", "NavigationRegion3D", ".", [("navigation_mesh", nav)])
    s.node("PlayerStart", "Marker3D", ".", [("transform", xform((0, 0.05, 8)))])
    s.node("SpawnPoints", "Node3D", ".")
    for nm, p in [("North", (0, 0.1, -17)), ("South", (0, 0.1, 17)), ("East", (17, 0.1, 0)), ("West", (-17, 0.1, 0)),
                  ("NorthEast", (13, 0.1, -13)), ("NorthWest", (-13, 0.1, -13)), ("SouthEast", (13, 0.1, 13)),
                  ("SouthWest", (-13, 0.1, 13))]:
        s.node(nm, "Marker3D", "SpawnPoints", [("transform", xform(p))])
    s.node("Sun", "DirectionalLight3D", ".", [
        ("transform", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 12, 0)"), ("rotation", "Vector3(-0.85, 0.65, 0)"),
        ("light_color", "Color(1, 0.9, 0.78, 1)"), ("light_energy", "1.0"), ("shadow_enabled", "true"),
        ("directional_shadow_max_distance", "70.0")])
    s.node("WorldEnvironment", "WorldEnvironment", ".", [("environment", env)])
    s.save("scenes/courtyard_arena.tscn")


def modules_gallery():
    s = Scene("ModulesGallery", script=False)
    s.node("ModulesGallery", "Node3D", None)
    items = ["wall_straight_6m", "wall_straight_4m", "wall_corner", "gate_main", "bridge_arched_8m",
             "pond_12x7", "building_hall_10x7", "path_stone_4m"]
    x = 0
    for n in items:
        s.node(n, None, ".", [("transform", xform((x, 0, 0)))], instance=RES + "/modules/%s.tscn" % n)
        x += 14
    for i, n in enumerate(["lantern_toro", "tree_pine", "rock_large"]):
        s.node(n, None, ".", [("transform", xform((i * 5, 0, 12)))], instance=RES + "/props/%s.tscn" % n)
    # Pond + bridge crossing it, as they are meant to combine.
    s.node("PondWithBridge", "Node3D", ".", [("transform", xform((0, 0, 30)))])
    s.node("Pond", None, "PondWithBridge", instance=RES + "/modules/pond_12x7.tscn")
    s.node("Bridge", None, "PondWithBridge", [("transform", xform((0, 0, 0), ("y", 90)))], instance=RES + "/modules/bridge_arched_8m.tscn")
    s.node("Sun", "DirectionalLight3D", ".", [("rotation", "Vector3(-0.85, 0.65, 0)"), ("shadow_enabled", "true")])
    s.save("scenes/modules_gallery.tscn")


if __name__ == "__main__":
    gen_materials()
    wall(6); wall(4); wall_corner(); gate_main(); bridge_arched(); pond(); building_hall(); path_segment()
    lantern(); tree_pine(); rock_large()
    courtyard_arena(); modules_gallery()
    print("graybox generated")
