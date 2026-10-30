#!/usr/bin/env python3
"""Switch the textures Godot extracted from the courtyard GLBs to VRAM compression (S3TC/BPTC on
desktop) with mipmaps, and mark *_normal maps as normal maps. Godot 4.3 extracts glTF images as
"Lossless" 2D textures by default, which keeps them uncompressed in VRAM (4 bytes/pixel).
Run after a first `godot --headless --import`, then import again. Idempotent."""
import glob, os, re

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
