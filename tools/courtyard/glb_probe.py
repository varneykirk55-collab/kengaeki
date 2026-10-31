#!/usr/bin/env python3
"""Read-only geometry probe for a GLB (numpy only): bbox, tris, textures, and optional
height profiles. Used to check BJORN's assets against Bill's dimensions before integration.

  python3 tools/courtyard/glb_probe.py FILE.glb [--profile-x N] [--ends]
"""
import json, struct, sys
import numpy as np

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    dt = CT[a["componentType"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(binc, np.uint8, count=stride * a["count"], offset=start).reshape(a["count"], stride)[:, :item]
        return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], n)
    return np.frombuffer(binc, dt, count=a["count"] * n, offset=start).reshape(a["count"], n)


def node_matrix(nd):
    if "matrix" in nd:
        return np.array(nd["matrix"], float).reshape(4, 4).T
    t = np.array(nd.get("translation", [0, 0, 0]), float)
    x, y, z, w = nd.get("rotation", [0, 0, 0, 1])
    s = np.array(nd.get("scale", [1, 1, 1]), float)
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4); m[:3, :3] = r * s; m[:3, 3] = t
    return m


def world_tris(path):
    js, binc = load(path)
    out = []
    scene = js["scenes"][js.get("scene", 0)]

    def walk(i, parent):
        nd = js["nodes"][i]
        m = parent @ node_matrix(nd)
        if "mesh" in nd:
            for p in js["meshes"][nd["mesh"]]["primitives"]:
                v = accessor(js, binc, p["attributes"]["POSITION"]).astype(float)
                v = (np.c_[v, np.ones(len(v))] @ m.T)[:, :3]
                idx = accessor(js, binc, p["indices"]).reshape(-1, 3) if "indices" in p else np.arange(len(v)).reshape(-1, 3)
                out.append(v[idx])
        for c in nd.get("children", []):
            walk(c, m)
    for r in scene["nodes"]:
        walk(r, np.eye(4))
    return js, np.concatenate(out)


def main():
    path = sys.argv[1]
    js, tris = world_tris(path)
    v = tris.reshape(-1, 3)
    lo, hi = v.min(0), v.max(0)
    print("file %s" % path)
    print("tris %d  bbox min %s max %s size %s" % (len(tris), np.round(lo, 3), np.round(hi, 3), np.round(hi - lo, 3)))
    for im in js.get("images", []):
        print("image %s %s" % (im.get("name", "?"), im.get("mimeType", "?")))
    for m in js.get("materials", []):
        print("material %s doubleSided=%s" % (m.get("name"), m.get("doubleSided", False)))
    if "--profile-x" in sys.argv:
        # Top surface height and lowest point per X slice (bridge deck / ramp ends).
        n = int(sys.argv[sys.argv.index("--profile-x") + 1])
        c = tris.mean(1)
        zc = (lo[2] + hi[2]) / 2
        edges = np.linspace(lo[0], hi[0], n + 1)
        print("x-slice | top y (all) | top y (|z-zc|<0.5, centre strip) | min y")
        for a, b in zip(edges[:-1], edges[1:]):
            sel = (v[:, 0] >= a) & (v[:, 0] < b)
            strip = sel & (np.abs(v[:, 2] - zc) < 0.5)
            print("%6.2f..%6.2f | %5.2f | %5.2f | %5.2f" % (a, b, v[sel, 1].max() if sel.any() else np.nan,
                  v[strip, 1].max() if strip.any() else np.nan, v[sel, 1].min() if sel.any() else np.nan))
    if "--ends" in sys.argv:
        for side, x in (("-x", lo[0]), ("+x", hi[0])):
            sel = np.abs(v[:, 0] - x) < 0.05
            if sel.any():
                print("end %s: y %.2f..%.2f  z %.2f..%.2f" % (side, v[sel, 1].min(), v[sel, 1].max(), v[sel, 2].min(), v[sel, 2].max()))


if __name__ == "__main__":
    main()


def ray_top(tris, x, z):
    """Highest surface hit by a vertical ray at (x, z); None if no hit (Moller-Trumbore, vectorised)."""
    o = np.array([x, 1e3, z]); d = np.array([0, -1.0, 0])
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2); det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1), 0)
    t = o - v0
    u = (t * p).sum(1) * inv
    q = np.cross(t, e1)
    w = (d * q).sum(1) * inv
    dist = (e2 * q).sum(1) * inv
    hit = ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (dist > 0)
    if not hit.any():
        return None
    return 1e3 - dist[hit].min()


def ray_bottom(tris, x, z):
    o = np.array([x, -1e3, z]); d = np.array([0, 1.0, 0])
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2); det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1), 0)
    t = o - v0
    u = (t * p).sum(1) * inv
    q = np.cross(t, e1)
    w = (d * q).sum(1) * inv
    dist = (e2 * q).sum(1) * inv
    hit = ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (dist > 0)
    if not hit.any():
        return None
    return -1e3 + dist[hit].min()
