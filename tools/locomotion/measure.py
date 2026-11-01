"""Summarize the deterministic preview logs; requires Python + numpy.
Run from project root after headless previews --out=before and --out=after.
This is a low-ankle planar-speed proxy, not a perfect contact classifier.
"""
import json
from pathlib import Path
import numpy as np
result = {}
for variant in ("before", "after"):
    rows = json.loads(Path(f"build/locomotion/{variant}_samples.json").read_text())
    result[variant] = {}
    for gait, start, end in (("walk", 100, 200), ("run", 245, 320)):
        speeds = []
        window = [r for r in rows if start <= r["frame"] <= end]
        for bone in ("CC_Base_L_Foot", "CC_Base_R_Foot"):
            positions = np.array([r[bone] for r in window])
            frames = np.array([r["frame"] for r in window])
            elapsed = np.diff(frames)
            velocity = np.linalg.norm(np.diff(positions[:, [0, 2]], axis=0), axis=1) * 60 / np.maximum(elapsed, 1)
            low = (positions[1:, 1] < np.quantile(positions[:, 1], .30)) & (elapsed > 0)
            speeds.extend(velocity[low])
        result[variant][gait] = float(np.mean(speeds))
print(json.dumps(result, indent=2))
