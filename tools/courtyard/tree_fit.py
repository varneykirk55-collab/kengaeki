#!/usr/bin/env python3
"""Tree canopy fit report (read-only): does any tree's canopy clip a wall, turret, gate or building?

Places every tree GLB at its blueprint position with its yaw (gen_graybox.YAW_OVERRIDE applied) and
tests its vertices against the world AABBs of the placed architecture models (walls incl. the filler
modules, turrets, gate, hall, barracks, kura). AABBs include roof eaves, so this is conservative.
  python3 tools/courtyard/tree_fit.py               # report at the generator's yaws
  python3 tools/courtyard/tree_fit.py --bill        # report at Bill's yaws (no overrides)
  python3 tools/courtyard/tree_fit.py --margin 0.25 --search PINE3   # nearest clear yaw for one tree
Run after sync_assets.py has copied the GLBs into the repo."""
import math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402
import glb_probe as P  # noqa: E402

L = G.load_blueprint()
_cache = {}


def verts(asset):
    if asset not in _cache:
        p = os.path.join(G.ROOT, G.resolve_model_path(asset)[len("res://"):])
        if not os.path.isfile(p):
            _cache[asset] = None
        else:
            _, t = P.world_tris(p)
            v = np.unique(t.reshape(-1, 3).round(4), axis=0)
            fit = G.MODEL_FIT.get(asset, {})
            # Same as CourtyardProp's Model holder: per-axis node scale (LOD pack: pine (1, 1, 1.3),
            # maple (1.237, 1, 1.238)), then the offset.
            _cache[asset] = v * np.array(fit.get("scale_xyz", (1, 1, 1))) + np.array(fit.get("offset", (0, 0, 0)))
    return _cache[asset]


def place(v, x, y, z, yaw, k=1.0):
    # Godot yaw about +Y: local +X -> (cos, 0, -sin) (same convention as gen_graybox.wall_fillers).
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    vx = v[:, 0] * k
    return np.c_[vx * c + v[:, 2] * s + x, v[:, 1] + y, -vx * s + v[:, 2] * c + z]


def boxes(margin=0.0):
    out = []
    for o in L.objs:
        oid, asset, x, y, z, yaw = o[:6]
        if asset in G.ARCH and not asset.startswith("bridge_") and asset != "castle_keep_tenshu":
            v = verts(asset)
            if v is not None:
                w = place(v, x, y, z, yaw)
                out.append((oid, w.min(0) - margin, w.max(0) + margin))
    if verts("wall_segment_4m") is not None:
        for (fid, x, y, z, yaw, k) in G.wall_fillers(L):
            w = place(verts("wall_segment_4m"), x, y, z, yaw, k)
            out.append((fid, w.min(0) - margin, w.max(0) + margin))
    return out


def report(bx, yaws):
    res = {}
    for o in L.objs:
        oid, asset, x, y, z, yaw = o[:6]
        if not asset.startswith("tree_") or verts(asset) is None or (yaws is not None and oid not in yaws):
            continue
        yaw = yaws[oid] if yaws is not None else yaw
        w = place(verts(asset), x, y, z, yaw)
        worst = (0.0, None, 0, 0.0)
        for (bid, lo, hi) in bx:
            inside = np.all((w > lo) & (w < hi), axis=1)
            if inside.any():
                p = w[inside]
                pen = np.minimum(p - lo, hi - p).min(1).max()
                if pen > worst[0]:
                    worst = (pen, bid, int(inside.sum()), p[:, 1].min())
        res[oid] = (asset, yaw, w.min(0), w.max(0), worst)
    return res


def main():
    margin = float(sys.argv[sys.argv.index("--margin") + 1]) if "--margin" in sys.argv else 0.0
    bx = boxes(margin)
    trees = {o[0]: o[5] for o in L.objs if o[1].startswith("tree_")}
    if "--search" in sys.argv:
        oid = sys.argv[sys.argv.index("--search") + 1]
        for d in sorted(range(-180, 180), key=abs):
            if report(bx, {oid: (trees[oid] + d) % 360})[oid][4][1] is None:
                print("%s: nearest clear yaw %d (Bill %d, change %+d) at margin %.2f m" % (oid, (trees[oid] + d) % 360, trees[oid], d, margin))
                return
        print("%s: no clear yaw" % oid)
        return
    yaws = None if "--bill" in sys.argv else {k: G.YAW_OVERRIDE.get(k, v) for k, v in trees.items()}
    bad = 0
    for oid, (asset, yaw, lo, hi, worst) in report(bx, yaws).items():
        bad += worst[1] is not None
        print("%-8s yaw %3d  canopy x %6.2f..%6.2f z %6.2f..%6.2f top %.2f  clip: %s" % (
            oid, yaw, lo[0], hi[0], lo[2], hi[2], hi[1],
            "none" if worst[1] is None else "%.2f m into %s (%d verts, from y %.2f)" % worst))
    print("trees clipping (margin %.2f m): %d" % (margin, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
