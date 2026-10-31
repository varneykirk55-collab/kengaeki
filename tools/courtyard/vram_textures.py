#!/usr/bin/env python3
"""Switch the textures Godot extracted from the courtyard GLBs to VRAM compression (S3TC/BPTC on
desktop) with mipmaps, and mark *_normal maps as normal maps. Godot 4.3 extracts glTF images as
"Lossless" 2D textures by default, which keeps them uncompressed in VRAM (4 bytes/pixel).
LOD pack: hand-made LODs drawn with LOD0's materials (gen_graybox.MODEL_LODS share=True) are set to
discard their embedded images on import (gltf/embedded_image_handling=0), and any textures already
extracted from them are deleted, so the repo stores no duplicate textures for them.
Run after a first `godot --headless --import`, then import again. Idempotent."""
import glob, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
changed = 0
for imp in sorted(glob.glob(os.path.join(ROOT, "environment/courtyard/assets/**/*.import"), recursive=True)):
    if not re.search(r"\.(png|jpg|jpeg)\.import$", imp):
        continue
    s = open(imp).read()
    new = re.sub(r"^compress/mode=\d+$", "compress/mode=2", s, flags=re.M)
    new = re.sub(r"^mipmaps/generate=\w+$", "mipmaps/generate=true", new, flags=re.M)
    if "_normal." in os.path.basename(imp):
        new = re.sub(r"^compress/normal_map=\d+$", "compress/normal_map=1", new, flags=re.M)
    if new != s:
        open(imp, "w").write(new)
        changed += 1
        print("vram:", os.path.relpath(imp, ROOT))
print("%d texture import files updated" % changed)

shared = 0
for asset in G.MODEL_LODS:
    for res, _dist, share in G.resolve_lods(asset):
        if not share:
            continue
        glb = os.path.join(ROOT, res[len("res://"):])
        imp = glb + ".import"
        if os.path.isfile(imp):
            s = open(imp).read()
            new = re.sub(r"^gltf/embedded_image_handling=\d+$", "gltf/embedded_image_handling=0", s, flags=re.M)
            if new != s:
                open(imp, "w").write(new)
                print("shared-material LOD, textures discarded:", os.path.relpath(imp, ROOT))
                shared += 1
        stem = os.path.basename(glb)[:-4]
        for f in glob.glob(os.path.join(os.path.dirname(glb), stem + "_[0-9]_*")):
            os.remove(f)
            print("removed duplicate texture:", os.path.relpath(f, ROOT))
print("%d shared-material LOD imports updated" % shared)
