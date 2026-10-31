# Courtyard asset credits and AI-generation notice

**The 3D models and textures under `environment/courtyard/assets/` are AI-generated.** They
were generated with Tencent Hunyuan 3D (web platform) and then post-processed (decimated,
re-textured to 2048², re-scaled, origin set to base centre) by Agent 2 (BJORN)'s asset
pipeline. No AI-generation marks were removed.

Per-asset provenance (library source, bytes, sha256, processing time) is in `ASSETS.md`.
BJORN's licence research for these outputs is at `library/LICENSE_NOTES.md` on the shared
build box (not legal advice; some terms are still unverified there).

| Asset | Generator | Post-processing |
|---|---|---|
| `Decorations/stone_lantern_toro` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 50,012 → 25,000 tris, 3 × 2048² textures, scaled to 2.0 m |
| `Decorations/stone_lantern_toro` (`stone_lantern_toro_lod8k.glb`) | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 50,012 → 8,000 tris, 1024² textures (JPEG albedo), scaled to 2.0 m |
| `Courtyard/wall_segment_4m` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 13,134 tris, 3 × 1024² textures, 4.00 × 4.74 × 1.59 m, tiling ends checked |
| `Courtyard/corner_turret` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 12,000 tris, 2048² albedo (JPEG) + 1024² data maps, 7.48 × 10.72 × 7.46 m |
| `Courtyard/main_gate_yaguramon` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 20,000 tris, 2048² albedo (JPEG) + 1024² data maps, 14.67 × 10.91 × 8.00 m |
| `Courtyard/main_hall_goten` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 50,004 → 25,000 tris, 2048² albedo (JPEG) + 1024² data maps, 22.93 × 9.42 × 12.00 m |
| `Courtyard/bridge_arched_taikobashi` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 8,000 tris, 1024² textures, non-uniform fit to 13 × 1.8 × 2.4 m (anisotropy 3.14). v2 (Oct 30, 8:06 PM EDT): symmetric, 8 piers extended down, origin at the pier bottoms, 13 × 2.05 × 2.4 m, 8,000 tris; v1 stays in git history and in BJORN's library as `_v1.glb` |
| `Courtyard/barracks_nagaya` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 12,000 tris, 1024² textures (JPEG albedo), 24 × 6 × 6 m |
| `Courtyard/storehouse_kura` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 6,000 tris, 1024² textures, 8 × 7 × 6 m, door +Z |
| `Courtyard/castle_keep_tenshu` | Tencent Hunyuan 3D (AI-generated) | BJORN pipeline: 20,000 tris, 1024² textures (JPEG albedo), 30 × 28 × 22 m, backdrop only |
