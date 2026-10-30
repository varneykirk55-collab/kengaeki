#!/usr/bin/env python3
"""Courtyard render budget from the delivered GLBs actually used by the arena (read-only report).

Triangles come from the GLBs (glb_probe.py), instance counts from the blueprint plus the generated
filler wall modules. Texture memory is the size of Godot's imported .ctex files (VRAM-compressed with
mipmaps, so this is close to the GPU footprint); run after `godot --headless --import`.
Note: Godot's importer also generates mesh LODs, so distant instances draw fewer triangles."""
import collections, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402
import glb_probe  # noqa: E402

L = G.load_blueprint()
count = collections.Counter(o[1] for o in L.objs)
count["wall_segment_4m"] += len(G.wall_fillers(L))
rows, tot_tris, tot_inst_tris, tot_tex, tot_git = [], 0, 0, 0, 0
for asset in sorted(count):
    res = G.resolve_model_path(asset)
    path = os.path.join(G.ROOT, res[len("res://"):])
    if not os.path.isfile(path):
        continue
    _js, tris = glb_probe.world_tris(path)
    stem = os.path.basename(path)[:-4]
    tex = git = os.path.getsize(path)
    tex = 0
    d = os.path.dirname(path)
    for f in sorted(os.listdir(d)):
        if f.startswith(stem + "_") and re.search(r"_\d+_\w+\.(png|jpg)$", f):
            git += os.path.getsize(os.path.join(d, f))
            imp = open(os.path.join(d, f + ".import")).read()
            m = re.search(r'^path(?:\.s3tc)?="res://(.+?)"', imp, re.M)
            if m and os.path.isfile(os.path.join(G.ROOT, m.group(1))):
                tex += os.path.getsize(os.path.join(G.ROOT, m.group(1)))
    n = count[asset]
    rows.append((asset, os.path.basename(path), len(tris), n, len(tris) * n, tex, git))
    tot_tris += len(tris); tot_inst_tris += len(tris) * n; tot_tex += tex; tot_git += git
print("| Asset | GLB | Tris | Instances | Tris in scene | Texture VRAM (MB) | Git (MB) |\n|---|---|---|---|---|---|---|")
for r in rows:
    print("| %s | %s | %s | %d | %s | %.2f | %.2f |" % (r[0], r[1], format(r[2], ","), r[3], format(r[4], ","), r[5] / 1e6, r[6] / 1e6))
print("| **Total** | | %s unique | | **%s** | **%.2f** | %.2f |" % (format(tot_tris, ","), format(tot_inst_tris, ","), tot_tex / 1e6, tot_git / 1e6))
