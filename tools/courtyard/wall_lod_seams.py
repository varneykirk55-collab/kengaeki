#!/usr/bin/env python3
"""Wall LOD seam report (read-only): do mixed wall_segment_4m LODs tile without gaps or steps?

For LOD0/LOD1/LOD2 it prints each module's x extent (must be exactly +-2.000 m: modules abut on a
4 m pitch, so any shortfall is a gap) and the end-face height/depth range, then slices every level
at x = +-1.99 m and compares the outer outline (z min/max per 10 cm height band) of one module's
+x end against its neighbour's -x start for every LOD pair. LOD0|LOD0 is the reference: the stone
and tile ends are irregular by design, so a mixed pair is fine when its steps are no larger.
  python3 tools/courtyard/wall_lod_seams.py"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402
import glb_probe as P  # noqa: E402

LEVELS = [("LOD0", "wall_segment_4m")] + [("LOD%d" % (i + 1), os.path.basename(p)[:-4]) for i, (p, _, _) in enumerate(G.resolve_lods("wall_segment_4m"))]
DIR = os.path.join(G.ROOT, G.resolve_model_path("wall_segment_4m")[len("res://"):].rsplit("/", 1)[0])
YS = np.arange(0.05, 4.7, 0.1)


def slice_pts(t, x0):
    pts = []
    for tri in t:
        s = tri[:, 0] - x0
        if s.min() > 0 or s.max() < 0:
            continue
        for i in range(3):
            j = (i + 1) % 3
            if (s[i] > 0) != (s[j] > 0):
                u = s[i] / (s[i] - s[j])
                pts.append(tri[i] + (tri[j] - tri[i]) * u)
    return np.array(pts)


def outline(p):
    out = []
    for y in YS:
        q = p[np.abs(p[:, 1] - y) < 0.05]
        out.append((q[:, 2].min(), q[:, 2].max()) if len(q) else (np.nan, np.nan))
    return np.array(out)


def main():
    ends = {}
    for name, stem in LEVELS:
        _, t = P.world_tris(os.path.join(DIR, stem + ".glb"))
        v = t.reshape(-1, 3)
        print("%s %-24s x %.4f..%.4f  y %.3f..%.3f  z %.3f..%.3f" % (name, stem, v[:, 0].min(), v[:, 0].max(), v[:, 1].min(), v[:, 1].max(), v[:, 2].min(), v[:, 2].max()))
        ends[name] = (outline(slice_pts(t, 1.99)), outline(slice_pts(t, -1.99)))
    for a, _ in LEVELS:
        for b, _ in LEVELS:
            d = np.abs(ends[a][0] - ends[b][1]).ravel()
            d = d[~np.isnan(d)]
            print("joint %s end | %s start: outline step median %.3f m, p90 %.3f m, max %.3f m" % (a, b, np.median(d), np.percentile(d, 90), d.max()))


if __name__ == "__main__":
    main()
