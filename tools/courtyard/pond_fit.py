#!/usr/bin/env python3
"""Pond stone fit report (read-only): do BJORN's pond stones clip a bridge, a path or a medium rock,
and do they stand in the water?

Places every pond stone GLB (main / _b per gen_graybox.INSTANCE_VARIANT, node scale and offset from
MODEL_FIT) at its generator position (PLACE_OVERRIDE applied) or Bill's (--bill), and measures in
plan view, using only the geometry in the stone's height band (y bottom..top):
  * clearance to the slab and arch bridge models' world AABBs (negative = overlap, m),
  * clearance to the bridge spur paths P5/P6 beyond the pond edge and to the rock_medium boxes,
  * the share of the stone's footprint over the water rectangle (x 24.5..35.5, z -5..5).
  python3 tools/courtyard/pond_fit.py [--bill]
Run after sync_assets.py has copied the GLBs into the repo."""
import math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402
import glb_probe as P  # noqa: E402

L = G.load_blueprint()
BILL = "--bill" in sys.argv


def model_verts(path, fit):
    _, t = P.world_tris(os.path.join(G.ROOT, path[len("res://"):]))
    v = np.unique(t.reshape(-1, 3).round(4), axis=0)
    return v * np.array(fit.get("scale_xyz", (1, 1, 1))) + np.array(fit.get("offset", (0, 0, 0)))


def place(v, x, z, yaw):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    out = np.empty_like(v)
    out[:, 0] = x + c * v[:, 0] + s * v[:, 2]
    out[:, 1] = v[:, 1]
    out[:, 2] = z - s * v[:, 0] + c * v[:, 2]
    return out


def box_clear(pts, x0, x1, z0, z1):
    """Min plan distance from points to an axis-aligned rectangle (negative = inside, by depth)."""
    dx = np.maximum(x0 - pts[:, 0], pts[:, 0] - x1)
    dz = np.maximum(z0 - pts[:, 1], pts[:, 1] - z1)
    out = np.where((dx > 0) | (dz > 0), np.hypot(np.maximum(dx, 0), np.maximum(dz, 0)), np.maximum(dx, dz))
    return float(out.min())


def obb_clear(pts, cx, cz, yaw, hx, hz):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    lx = c * (pts[:, 0] - cx) - s * (pts[:, 1] - cz)
    lz = s * (pts[:, 0] - cx) + c * (pts[:, 1] - cz)
    return box_clear(np.stack([lx, lz], 1), -hx, hx, -hz, hz)


bridges = {}
for o in L.objs:
    if o[1] in ("bridge_stone_slab", "bridge_arched_taikobashi"):
        v = place(model_verts(G.resolve_model_path(o[1]), G.MODEL_FIT.get(o[1], {})), o[2], o[4], o[5])
        bridges[o[0]] = v
rocks = []
for o in L.objs:
    if o[1] == "rock_medium" and G.VARIANTS.get("rock_medium"):
        (cx_, cy_, cz_), (sx_, sy_, sz_) = G.VARIANTS["rock_medium"][None]["collider"]
        rocks.append((o[0], o[2], o[4], o[5], sx_ / 2, sz_ / 2))
paths = [(nm.split(" ")[0], x0 - w / 2, x0 + w / 2, min(z0, z1), max(z0, z1)) for (nm, x0, z0, x1, z1, w) in L.PATHS
         if x0 == x1 and G.POND_X[0] < x0 < G.POND_X[1]]
fails = 0
print("pond stones (%s placement)" % ("Bill's" if BILL else "generator"))
for o in L.objs:
    if o[1] != "pond_edge_stones_2m":
        continue
    oid, x, z, yaw = o[0], o[2], o[4], o[5]
    if not BILL:
        x, z, yaw = G.PLACE_OVERRIDE.get(oid, (x, z, yaw))
    var = G.INSTANCE_VARIANT.get(oid)
    path = G.resolve_variant_path(o[1], var) if var else None
    name = o[1] + ("_" + var if path else "")
    path = path or G.resolve_model_path(o[1])
    v = place(model_verts(path, G.MODEL_FIT.get(name, G.MODEL_FIT.get(o[1], {}))), x, z, yaw)
    y0, y1 = v[:, 1].min(), v[:, 1].max()
    pts = v[:, [0, 2]]
    row = ["%-7s %-26s (%6.2f, %5.2f) yaw %4.0f  y %.2f..%.2f  x %.2f..%.2f z %.2f..%.2f" % (
        oid, os.path.basename(path), x, z, yaw, y0, y1, pts[:, 0].min(), pts[:, 0].max(), pts[:, 1].min(), pts[:, 1].max())]
    worst = 9.0
    for bid, bv in bridges.items():
        band = bv[(bv[:, 1] >= y0) & (bv[:, 1] <= y1)]
        if len(band):
            cl = box_clear(pts, band[:, 0].min(), band[:, 0].max(), band[:, 2].min(), band[:, 2].max())
            row.append("%s %+.2f" % (bid, cl))
            worst = min(worst, cl)
    for (pn, px0, px1, pz0, pz1) in paths:
        for (a, b) in ((pz0, -G.POND_HZ), (G.POND_HZ, pz1)):
            cl = box_clear(pts, px0, px1, a, b)
            worst = min(worst, cl)
    row.append("paths %+.2f" % min(box_clear(pts, px0, px1, a, b) for (pn, px0, px1, pz0, pz1) in paths
                                 for (a, b) in ((pz0, -G.POND_HZ), (G.POND_HZ, pz1))))
    rc = min(obb_clear(pts, rx, rz, ry, hx, hz) for (_r, rx, rz, ry, hx, hz) in rocks) if rocks else 9.0
    row.append("rock_medium %+.2f" % rc)
    inside = (pts[:, 0] > G.POND_X[0]) & (pts[:, 0] < G.POND_X[1]) & (np.abs(pts[:, 1]) < G.POND_HZ)
    row.append("over water %d%%" % round(100 * inside.mean()))
    ok = worst > 0.0 and rc > -0.05
    fails += not ok
    print(("  OK    " if ok else "  CLASH ") + "  ".join(row))
print("pond_fit: %s" % ("clear" if fails == 0 else "%d stone(s) clash" % fails))
