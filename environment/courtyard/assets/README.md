# Courtyard assets

Optimised GLBs copied (read-only source) from BJORN's library at
`/workspace/kengeki_assets/library/<Category>/<asset>/optimised/`, placed as
`<Category>/<asset>/<asset>.glb`. The mapping from Bill's asset names to categories is `CATEGORY` in
`tools/courtyard/gen_graybox.py`. See `docs/courtyard/INTEGRATION_PLAN.md` §5 for the size and LFS policy.
Prefabs in `../modules` and `../props` load these only if present, otherwise they show graybox.
