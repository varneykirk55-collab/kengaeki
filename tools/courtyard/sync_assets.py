#!/usr/bin/env python3
"""Find BJORN's delivered assets for the courtyard and (on request) copy them into the repo.

  python3 tools/courtyard/sync_assets.py              # report only: what the library has, per blueprint asset
  python3 tools/courtyard/sync_assets.py --apply NAME  # copy one asset (Bill's or BJORN's name), then regenerate
  python3 tools/courtyard/sync_assets.py --apply NAME --variant lod8k   # copy a MANIFEST variant instead

The library (/workspace/kengeki_assets/library, override KENGEKI_LIBRARY) is READ ONLY: this script
only reads it and copies the optimised GLB into res://environment/courtyard/assets/<Category>/<name>/.
Lookup covers the asset's type category plus Courtyard/ and Decorations/, under BJORN's or Bill's name;
the GLB is the MANIFEST.json `filename_optimised` (or variant `filename`), else <name>/<name>.glb (flat
layout, batch 1+), else <name>/optimised/<name>.glb (first lantern delivery).
--apply refuses unless: the GLB exists and its sha256 matches stats.json (the library is re-processed
in place, so a mismatch means a delivery is in flight); the git cost (GLB + Godot-extracted textures,
stats.json git_cost) is <= 10 MB (repo policy, no LFS); the asset has a REPORT.md and a MANIFEST.json
entry whose validation starts with PASS; and the GLB's own bounding box (measured here with glb_probe.py)
is within 10% of Bill's authored size on every axis (trees, G.HEIGHT_FIT: height within 10% and canopy
footprint no more than 10% larger, since they are scaled uniformly to Bill's height). Read REPORT.md and HANDOFF.md yourself before
applying; this script does not judge facing or looks.
"""
import hashlib, json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402  (module import does not regenerate anything)
import glb_probe  # noqa: E402

LIB = os.environ.get("KENGEKI_LIBRARY", "/workspace/kengeki_assets/library")
MAX_BYTES = 10 * 1024 * 1024
LEDGER = os.path.join(G.ROOT, G.BASE, "assets", "ASSETS.md")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def manifest():
    try:
        with open(os.path.join(LIB, "MANIFEST.json")) as f:
            return {(a["category"], a["asset_name"]): a for a in json.load(f).get("assets", [])}
    except (OSError, ValueError, KeyError):
        return {}


def lib_path(rel):
    """MANIFEST paths are relative to the library's parent ("library/Courtyard/...")."""
    return os.path.join(os.path.dirname(LIB), rel) if rel.startswith("library/") else os.path.join(LIB, rel)


def find(asset, man, variant=None):
    """(category, name, glb, manifest entry, stats.json path) of the delivered GLB, or None."""
    for c, n in G.asset_candidates(asset):
        entry = man.get((c, n))
        cands = []
        if entry and variant:
            v = (entry.get("variants") or {}).get(variant)
            if v:
                cands.append((lib_path(v["filename"]), lib_path(v.get("stats", "")) if v.get("stats") else None))
        elif entry and entry.get("filename_optimised"):
            cands.append((lib_path(entry["filename_optimised"]), None))
        if not variant:
            cands += [(os.path.join(LIB, c, n, n + ".glb"), None), (os.path.join(LIB, c, n, "optimised", n + ".glb"), None)]
        for glb, st in cands:
            if os.path.isfile(glb):
                st = st or os.path.join(LIB, c, n, "stats.json")
                return c, n, glb, entry, st
    return None


def measured_size(glb):
    _js, tris = glb_probe.world_tris(glb)
    pts = tris.reshape(-1, 3)
    return tuple(float(v) for v in pts.max(0) - pts.min(0)), len(tris)


def main():
    L = G.load_blueprint()
    man = manifest()
    bill_assets = sorted({o[1] for o in L.objs})
    apply = sys.argv[sys.argv.index("--apply") + 1] if "--apply" in sys.argv else None
    variant = sys.argv[sys.argv.index("--variant") + 1] if "--variant" in sys.argv else None
    sizes = {o[1]: o[6] for o in L.objs}
    sizes.update(G.AUTHORED_SIZE)  # documented overrides (DEVIATIONS.md)
    for asset in bill_assets:
        hit = find(asset, man, variant if apply else None)
        if apply and apply not in (asset, G.CATEGORY.get(asset, ("", ""))[1]):
            continue
        if not hit:
            print("%-26s not in library yet (looked in %s)" % (asset, ", ".join("%s/%s" % cn for cn in G.asset_candidates(asset))))
            continue
        c, n, glb, entry, stats_path = hit
        size = os.path.getsize(glb)
        report = os.path.isfile(os.path.join(LIB, c, n, "REPORT.md"))
        valid = (entry or {}).get("validation_status", "")
        if variant and apply:
            valid = ((entry or {}).get("variants") or {}).get(variant, {}).get("validation", "")
        try:
            with open(stats_path) as f:
                stats = json.load(f)
        except (OSError, ValueError):
            stats = {}
        git_cost = (stats.get("git_cost") or {}).get("total_bytes", size)
        repo_rel = os.path.join(G.BASE, "assets", c, n, os.path.basename(glb))
        in_repo = os.path.isfile(os.path.join(G.ROOT, repo_rel))
        print("%-26s %s/%s  %s  %.2f MB (git %.2f MB)  report=%s  manifest=%s  validation=%s  in_repo=%s" % (
            asset, c, n, os.path.basename(glb), size / 1e6, git_cost / 1e6, report, bool(entry), valid[:4] or "-", in_repo))
        if apply:
            problems = []
            digest_lib = sha(glb)
            if stats.get("sha256") and stats["sha256"] != digest_lib:
                problems.append("GLB sha256 differs from stats.json (library re-processing in flight?)")
            if size > MAX_BYTES or git_cost > MAX_BYTES:
                problems.append("git cost over 10 MB (needs Kirk's LFS / storage decision)")
            if not report:
                problems.append("no REPORT.md")
            if not entry:
                problems.append("no MANIFEST.json entry")
            elif not valid.startswith("PASS"):
                problems.append("validation is not PASS")
            (mx, my, mz), ntris = measured_size(glb)
            bx, by, bz = sizes[asset]
            dev = [(m - b) / b * 100 for m, b in ((mx, bx), (my, by), (mz, bz))]
            print("  measured %.3f x %.3f x %.3f m vs Bill %.2f x %.2f x %.2f m (%+.1f%% %+.1f%% %+.1f%%), %d tris" % (
                mx, my, mz, bx, by, bz, dev[0], dev[1], dev[2], ntris))
            if asset in G.HEIGHT_FIT:
                if abs(dev[1]) > 10 or dev[0] > 10 or dev[2] > 10:
                    problems.append("tree height not within 10% of Bill's or footprint more than 10% larger")
            elif any(abs(d) > 10 for d in dev):
                problems.append("bounding box not within 10% of Bill's size on every axis")
            if problems:
                sys.exit("refusing to copy %s: %s" % (n, "; ".join(problems)))
            dst = os.path.join(G.ROOT, repo_rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(glb, dst)  # reads the library file only
            digest = sha(dst)
            if digest != digest_lib:
                sys.exit("copy of %s does not match the library file" % n)
            line = "| %s | `%s/%s` | `%s` | %d | `%s` | %s |\n" % (
                asset, c, n, repo_rel, size, digest, stats.get("processed") or (entry or {}).get("processed", "?"))
            new = not os.path.isfile(LEDGER)
            with open(LEDGER, "a") as f:
                if new:
                    f.write("# Courtyard assets copied from BJORN's library\n\n"
                            "| Blueprint asset | Library | Repo path | Bytes | sha256 | Processed |\n|---|---|---|---|---|---|\n")
                f.write(line)
            print("copied -> %s (sha256 %s); regenerating prefabs" % (repo_rel, digest[:12]))
            subprocess.check_call([sys.executable, os.path.join(os.path.dirname(__file__), "gen_graybox.py")])


if __name__ == "__main__":
    main()
