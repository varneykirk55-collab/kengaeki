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
            fit = MODEL_FIT.get(self.name, {})
            if "offset" in fit:
                props.append(("model_offset", vec(fit["offset"])))
            if "scale_xyz" in fit:
                props.append(("model_scale_xyz", vec(fit["scale_xyz"])))
            if getattr(self, "authored_size", None):
                props.append(("authored_size", vec(self.authored_size)))
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
MODEL_VARIANT = {"stone_lantern_toro_2m": "stone_lantern_toro_lod8k"}

# Integration fit applied to the imported model only (graybox and collision unaffected unless noted).
# Every entry is a documented deviation (docs/courtyard/DEVIATIONS.md).
MODEL_FIT = {
    # Sink the arch bridge 0.15 m so its north deck end sits flush on the bank (its ends are
    # 0.15 m / 0.26 m thick above y=0 in the GLB); the arena colliders follow the sunk deck.
}


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
# Deck-top profile of BJORN's bridge_arched_taikobashi.glb (local X = length, model space, y up),
# measured with tools/courtyard/glb_probe.py (vertical ray casts on the deck centre line). The
# deck is not symmetric: the -X end is 0.26 m thick, the +X end 0.15 m. Ends are joined to the
# bank by lead-in chords from y=0 at |x| = 7 m (0.5 m onto the bank, under the deck end).
ARCH_PROFILE = [(-5.0, 0.47), (-3.5, 0.65), (-2.0, 0.78), (-0.75, 0.85), (0.75, 0.845),
                (2.0, 0.78), (3.5, 0.63), (4.75, 0.40), (5.5, 0.17)]
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
FILLER_INNER_EDGE = {"main_gate_yaguramon": 5.8}


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


def prefab_path(asset):
    sub = "modules" if asset in ARCH else "props"
    return "%s/%s/%s.tscn" % (RES, sub, asset)


def build_prefab(asset, size):
    s = Scene(asset, resolve_model_path(asset))
    s.authored_size = tuple(size)
    sx, sy, sz = size
    s.begin(collision=asset not in ARCH and asset not in ("shrub_azalea", "rock_small_cluster"))
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
        # Local X = length (13 m), deck width on Z. Matches the arena colliders (section 7).
        for nm, x, deg in (("RampA", -4.28, 12.53), ("RampB", 4.28, -12.53)):
            s.box(nm, (x, 0.35, 0), (4.61, 0.3, sz), "lacquer", rot=("z", deg))
        s.box("Deck", (0, 0.85, 0), (4.0, 0.3, sz), "lacquer")
        # Rails: top bar ~1.0 m above the walking surface, following the arch (addendum 6:40 PM).
        for z in (-sz / 2, sz / 2):
            s.box("RailDeck%+.1f" % z, (0, 1.94, z), (4.0, 0.12, 0.12), "lacquer")
            for nm, x, deg in (("A", -4.28, 12.53), ("B", 4.28, -12.53)):
                a = math.radians(deg)
                off = 0.15 + 0.94  # ramp half-thickness + rail height along the surface normal
                s.box("Rail%s%+.1f" % (nm, z), (x - math.sin(a) * off, 0.35 + math.cos(a) * off, z),
                      (4.61, 0.12, 0.12), "lacquer", rot=("z", deg))
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
        r, h = (0.35, 3.0) if pine else (0.3, 2.5)
        leaf = "foliage" if pine else "lacquer" if "maple" in asset else "plaster"
        s.cyl("Trunk", (0, sy * 0.3, 0), r * 0.7, r, sy * 0.6, "bark", 8)
        s.sphere("Canopy", (0, sy * 0.7, 0), sx / 2, sy * 0.55, leaf)
        s.col_cyl("Trunk", (0, h / 2, 0), r, h)
    elif asset == "shrub_azalea":
        s.sphere("Body", (0, sy / 2, 0), sx / 2, sy, "foliage")
    elif asset.startswith("rock_"):
        s.sphere("Body", (0, sy / 2, 0), max(sx, sz) / 2, sy, "stone")
        if asset == "rock_formation_large":
            s.col_box("Shape", (0, 0.9, 0), (2.6, 1.8, 2.1))
        elif asset == "rock_medium":
            s.col_box("Shape", (0, 0.45, 0), (1.3, 0.9, 1.0))
    else:  # unknown blueprint asset: authored-size box, no collision
        s.box("Box", (0, sy / 2, 0), size, "stone")
    s.save(prefab_path(asset)[len(RES) + 1:])


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
    col("WallRuns", "N", (0, 2.5, -46), (72, 5, 1.6))
    col("WallRuns", "SW", (-22, 2.5, 34), (28, 5, 1.6))
    col("WallRuns", "SE", (22, 2.5, 34), (28, 5, 1.6))
    col("WallRuns", "E", (40, 2.5, -6), (1.6, 5, 72))
    col("WallRuns", "W", (-40, 2.5, -6), (1.6, 5, 72))
    for nm, x, z in (("NW", -40, -46), ("NE", 40, -46), ("SW", -40, 34), ("SE", 40, 34)):
        col("Turrets", nm, (x, 5, z), (8, 10, 8))
    col("Gate", "Gate", (0, 5, 34), (16, 10, 8))
    col("Buildings", "Hall", (0, 4.5, -39), (24, 9, 12))
    col("Buildings", "Barracks", (-36, 3, 0), (6, 6, 24))
    col("Buildings", "Kura", (-31, 3.5, -36), (6, 7, 8))
    col("Pond", "FenceW", (24.35, 0.45, 0), (0.3, 0.9, 10.6))
    col("Pond", "FenceE", (35.65, 0.45, 0), (0.3, 0.9, 10.6))
    for side, z in (("N", -5.15), ("S", 5.15)):
        for i, (x0, x1) in enumerate(((24.5, 25), (27, 29.8), (32.2, 35.5))):
            col("Pond", "Fence%s%d" % (side, i), ((x0 + x1) / 2, 0.45, z), (x1 - x0, 0.9, 0.3))
    col("Bridges", "ArchRampN", (31, 0.35, -4.28), (2.4, 0.3, 4.61), ("x", -12.53))
    col("Bridges", "ArchDeck", (31, 0.85, 0), (2.4, 0.3, 4.0))
    col("Bridges", "ArchRampS", (31, 0.35, 4.28), (2.4, 0.3, 4.61), ("x", 12.53))
    # Arch rails: short boxes following the arch, top ~1.0 m above the deck surface
    # (addendum 6:40 PM; replaces the single 2 m slab to reduce camera pull-in).
    for side, x in (("W", 29.725), ("E", 32.275)):
        col("Bridges", "ArchRail%sDeck" % side, (x, 1.5, 0), (0.15, 1.0, 4.0))
        for nm, zc, deg in (("N", -4.28, -12.53), ("S", 4.28, 12.53)):
            a = math.radians(deg)
            off = 0.15 + 0.5  # ramp half-thickness + half the rail height, along the ramp normal
            col("Bridges", "ArchRail%s%s" % (side, nm), (x, 0.35 + math.cos(a) * off, zc + math.sin(a) * off),
                (0.15, 1.0, 4.61), ("x", deg))
    col("Bridges", "SlabDeck", (26, -0.15, 0), (2.0, 0.3, 11))
    col("Bridges", "SlabRailW", (24.925, 0.45, 0), (0.15, 0.9, 10))
    col("Bridges", "SlabRailE", (27.075, 0.45, 0), (0.15, 0.9, 10))

    # Props with their own colliders (lanterns, trees, rocks, shrubs) stay inside nav_source.
    s.node("Props", "Node3D", "Collision")
    groups_made = set()
    for (oid, asset, x, y, z, yaw, size, colnote, *_rest) in L.objs:
        if asset in ARCH:
            continue
        grp = {"stone": "Lanterns"}.get(asset.split("_")[0], asset.split("_")[0].capitalize() + "s")
        if grp not in groups_made:
            s.node(grp, "Node3D", "Collision/Props"); groups_made.add(grp)
        s.node(oid, None, "Collision/Props/" + grp, [("transform", xform((x, y, z), ("y", yaw)))], instance=prefab_path(asset))

    # ---- Visual: no colliders ----
    s.node("Visual", "Node3D", ".")
    s.node("Ground", "Node3D", "Visual")
    for nm, pos, size in (("G1", (-7.75, -0.03, -6), (64.5, 0.06, 80)), ("G2", (37.75, -0.03, -6), (4.5, 0.06, 80)),
                          ("G3", (30, -0.03, -25.5), (11, 0.06, 41)), ("G4", (30, -0.03, 19.5), (11, 0.06, 29))):
        s.node(nm, "MeshInstance3D", "Visual/Ground", [("transform", xform(pos)), ("mesh", s.sub("BoxMesh", [("size", vec(size))])),
               ("material_override", s.mat("grass")), ("cast_shadow", "0")])
    s.node("OuterGrass", "MeshInstance3D", "Visual/Ground", [("transform", xform((0, -0.08, -6))),
           ("mesh", s.sub("BoxMesh", [("size", "Vector3(200, 0.05, 200)")])), ("material_override", s.mat("grass")), ("cast_shadow", "0")])
    s.node("Gravel", "MeshInstance3D", "Visual/Ground", [("transform", xform((0, 0.005, 0))),
           ("mesh", s.sub("BoxMesh", [("size", "Vector3(40, 0.01, 40)")])), ("material_override", s.mat("gravel")), ("cast_shadow", "0")])
    s.node("Paths", "Node3D", "Visual")
    for (nm, x0, z0, x1, z1, w) in L.PATHS:
        size = (abs(x1 - x0), 0.02, w) if z0 == z1 else (w, 0.02, abs(z1 - z0))
        s.node(nm.split(" ")[0], "MeshInstance3D", "Visual/Paths", [("transform", xform(((x0 + x1) / 2, 0.01, (z0 + z1) / 2))),
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
        s.node(oid, None, "Visual/" + grp, [("transform", xform((x, y, z), ("y", yaw)))], instance=prefab_path(asset))
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
        ("shadow_opacity", "0.8"), ("shadow_blur", "1.5"), ("directional_shadow_max_distance", "90.0")])
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
        x += size[0] / 2 + 2
        s.node(asset, None, ".", [("transform", xform((x, 0, 0)))], instance=prefab_path(asset))
        x += size[0] / 2
    s.node("Sun", "DirectionalLight3D", ".", [("rotation", "Vector3(-0.85, 0.65, 0)"), ("shadow_enabled", "true")])
    s.save("scenes/prefab_gallery.tscn")


if __name__ == "__main__":
    L = load_blueprint()
    gen_materials()
    for asset in sorted({o[1] for o in L.objs}):
        build_prefab(asset, next(o[6] for o in L.objs if o[1] == asset))
    courtyard_arena(L)
    prefab_gallery(L)
    print("graybox generated from %s (sha256 %s): %d objects, %d prefabs" % (BLUEPRINT_SRC, BLUEPRINT_SHA[:12], len(L.objs), len({o[1] for o in L.objs})))
