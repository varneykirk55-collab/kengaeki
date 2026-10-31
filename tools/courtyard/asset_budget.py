#!/usr/bin/env python3
"""Courtyard render budget from the delivered GLBs actually used by the arena (read-only report).

Per asset it lists every committed model file (LOD0, the second variants of the batch 4 rocks and
BJORN's hand-made LODs), with triangles (glb_probe.py), instance counts (blueprint + generated filler
wall modules; variants split by gen_graybox.INSTANCE_VARIANT), texture memory and git cost.
- Texture VRAM: size of Godot's imported .ctex files (VRAM-compressed with mipmaps, close to the GPU
  footprint); run after `godot --headless --import`. LODs drawn with LOD0's materials add none.
- Git: the GLB plus the textures Godot extracted from it (both committed; .import files not counted).
- "Tris in scene": LOD0 x instances (everything at full detail). "Drawn from centre": each instance at
  the level a camera at the combat centre (0, 1.7, 0) selects (distance to its box centre vs
  gen_graybox.MODEL_LODS), minus instances culled by MODEL_RENDER vis_end; ignores frustum culling.
  python3 tools/courtyard/asset_budget.py [--files]"""
import collections, math, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402
import glb_probe  # noqa: E402

TEX = re.compile(r"_(\d+_)?(basecolor|metallic_roughness|normal)\.(png|jpg)$")
EYE = (0.0, 1.7, 0.0)


def file_cost(path):
    """(tris, texture VRAM bytes, git bytes) for one committed GLB."""
    _js, tris = glb_probe.world_tris(path)
    stem = os.path.basename(path)[:-4]
    git, tex = os.path.getsize(path), 0
    d = os.path.dirname(path)
    for f in sorted(os.listdir(d)):
        m = TEX.search(f)
        if not m or f[:m.start()] != stem:
            continue
        git += os.path.getsize(os.path.join(d, f))
        imp = open(os.path.join(d, f + ".import")).read()
        mm = re.search(r'^path(?:\.s3tc)?="res://(.+?)"', imp, re.M)
        if mm and os.path.isfile(os.path.join(G.ROOT, mm.group(1))):
            tex += os.path.getsize(os.path.join(G.ROOT, mm.group(1)))
    return len(tris), tex, git


def main():
    L = G.load_blueprint()
    inst = collections.defaultdict(list)  # (asset, variant) -> [(x, y, z, height)]
    for o in L.objs:
        oid, asset, x, y, z = o[:5]
        v = G.INSTANCE_VARIANT.get(oid) if G.resolve_variant_path(asset, G.INSTANCE_VARIANT.get(oid)) else None
        inst[(asset, v)].append((x, y, z, o[6][1]))
    wall_h = next(o[6][1] for o in L.objs if o[1] == "wall_segment_4m")
    for (_fid, x, y, z, _yaw, _k) in G.wall_fillers(L):
        inst[("wall_segment_4m", None)].append((x, y, z, wall_h))
    rows, files = [], []
    tot = collections.Counter()
    for (asset, variant) in sorted(inst, key=lambda k: (k[0], k[1] or "")):
        res = G.resolve_variant_path(asset, variant) if variant else G.resolve_model_path(asset)
        path = os.path.join(G.ROOT, res[len("res://"):])
        if not os.path.isfile(path):
            continue
        name = asset + ("_" + variant if variant else "")
        tris0, tex, git = file_cost(path)
        files.append((name, os.path.basename(path), tris0, tex, git))
        levels = [(0.0, tris0)]
        lod_tris, lod_tex, lod_git = [], 0, 0
        if not variant:
            for lres, dist, _share in G.resolve_lods(asset):
                t, x_tex, x_git = file_cost(os.path.join(G.ROOT, lres[len("res://"):]))
                files.append((name, os.path.basename(lres), t, x_tex, x_git))
                levels.append((dist, t))
                lod_tris.append(t); lod_tex += x_tex; lod_git += x_git
        vis_end = G.MODEL_RENDER.get(asset, {}).get("vis_end", 0.0)
        n = len(inst[(asset, variant)])
        drawn = 0
        for (x, y, z, h) in inst[(asset, variant)]:
            d = math.dist(EYE, (x, y + h / 2.0, z))
            if vis_end and d > vis_end:
                continue
            drawn += [t for (start, t) in levels if d >= start][-1]
        rows.append((name, tris0, lod_tris, n, tris0 * n, drawn, tex + lod_tex, git + lod_git))
        tot.update(unique=tris0, scene=tris0 * n, drawn=drawn, tex=tex + lod_tex, git=git + lod_git)
    print("| Asset | Tris LOD0 | LOD tris | Instances | Tris in scene (LOD0) | Drawn from centre | Texture VRAM (MB) | Git (MB) |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %s | %s | %d | %s | %s | %.2f | %.2f |" % (r[0], format(r[1], ","), " / ".join(format(t, ",") for t in r[2]) or "-",
              r[3], format(r[4], ","), format(r[5], ","), r[6] / 1e6, r[7] / 1e6))
    print("| **Total** | %s unique | | | **%s** | **%s** | **%.2f** | %.2f |" % (format(tot["unique"], ","), format(tot["scene"], ","),
          format(tot["drawn"], ","), tot["tex"] / 1e6, tot["git"] / 1e6))
    if "--files" in sys.argv:
        print("\n| Asset | File | Tris | Texture VRAM (MB) | Git (MB) |\n|---|---|---|---|---|")
        for f in files:
            print("| %s | %s | %s | %.2f | %.2f |" % (f[0], f[1], format(f[2], ","), f[3] / 1e6, f[4] / 1e6))


if __name__ == "__main__":
    main()
