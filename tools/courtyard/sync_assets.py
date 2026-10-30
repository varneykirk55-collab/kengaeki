#!/usr/bin/env python3
"""Find BJORN's delivered assets for the courtyard and (on request) copy them into the repo.

  python3 tools/courtyard/sync_assets.py              # report only: what the library has, per blueprint asset
  python3 tools/courtyard/sync_assets.py --apply NAME  # copy one asset (Bill's or BJORN's name), then regenerate

The library (/workspace/kengeki_assets/library, override KENGEKI_LIBRARY) is READ ONLY: this script
only reads it and copies optimised/<name>.glb into res://environment/courtyard/assets/<Category>/<name>/.
Lookup covers the asset's type category plus Courtyard/ and Decorations/, under BJORN's or Bill's name.
--apply refuses unless: the optimised GLB exists, it is <= 10 MB (repo policy, no LFS), the asset has a
REPORT.md and a MANIFEST.json entry whose validation starts with PASS. Read REPORT.md and the library
HANDOFF.md yourself before applying; this script does not judge scale, facing or looks.
"""
import hashlib, json, os, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_graybox as G  # noqa: E402  (module import does not regenerate anything)

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


def find(asset, man):
    for c, n in G.asset_candidates(asset):
        glb = os.path.join(LIB, c, n, "optimised", n + ".glb")
        if os.path.isfile(glb):
            return c, n, glb, man.get((c, n))
    return None


def main():
    L = G.load_blueprint()
    man = manifest()
    bill_assets = sorted({o[1] for o in L.objs})
    apply = sys.argv[sys.argv.index("--apply") + 1] if "--apply" in sys.argv else None
    for asset in bill_assets:
        hit = find(asset, man)
        if apply and apply not in (asset, G.CATEGORY.get(asset, ("", ""))[1]):
            continue
        if not hit:
            print("%-26s not in library yet (looked in %s)" % (asset, ", ".join("%s/%s" % cn for cn in G.asset_candidates(asset))))
            continue
        c, n, glb, entry = hit
        size = os.path.getsize(glb)
        report = os.path.isfile(os.path.join(LIB, c, n, "REPORT.md"))
        valid = (entry or {}).get("validation_status", "")
        repo_rel = os.path.join(G.BASE, "assets", c, n, n + ".glb")
        in_repo = os.path.isfile(os.path.join(G.ROOT, repo_rel))
        print("%-26s %s/%s  %.2f MB  report=%s  manifest=%s  validation=%s  in_repo=%s" % (
            asset, c, n, size / 1e6, report, bool(entry), valid[:4] or "-", in_repo))
        if apply:
            problems = []
            if size > MAX_BYTES:
                problems.append("larger than 10 MB (needs Kirk's LFS / storage decision)")
            if not report:
                problems.append("no REPORT.md")
            if not entry:
                problems.append("no MANIFEST.json entry")
            elif not valid.startswith("PASS"):
                problems.append("validation is not PASS")
            if problems:
                sys.exit("refusing to copy %s: %s" % (n, "; ".join(problems)))
            dst = os.path.join(G.ROOT, repo_rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(glb, dst)  # reads the library file only
            digest = sha(dst)
            line = "| %s | `%s/%s` | `%s` | %d | `%s` | %s |\n" % (
                asset, c, n, repo_rel, size, digest, (entry or {}).get("processed", "?"))
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
