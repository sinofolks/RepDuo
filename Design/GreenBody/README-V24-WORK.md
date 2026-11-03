# V24 — local ear topology and relief

Unfinished working model; the 99 target is not met. No iOS changes or final
animation approval. Prior V23 remains unchanged.

Selected: `GreenBody-v24-work.blend`, SHA-256
`3bbaed080c08b8257e8ea2eaad2ee5a93b1b55136e026913bb9bbfc76cee9ed4`.
Exact copy of `calibration/multiview-reference-v3/captures/V24-projected-ear/canonical.blend`.

## Actual geometry changes

`scripts/build_green_body_v24.py` uses V23, `--cuts 2 --ear --surface-project`.
The head-side region between rest heights1.625–1.750m receives local linear
edge subdivision, adding8,996 vertices:13,024→22,020 control points. The saved
mesh remains one connected closed manifold. The evaluated surface now has
350,650 vertices, not the previous208,170. Original lower-body vertices are
unchanged; this is not a globally shape-identical tessellation operation.

Subdivision may invalidate BMesh Python vertex wrappers. The builder therefore
reconstructs unique retained-vertex correspondence from coordinates, requiring
error<1e-7m (actual0). It does not infer lost geometry from invalid wrappers.

All retained vertex weights remain exact. New points receive explicit closest
source-triangle barycentric skin weights and relative corrective-key deltas.
The maximum new-point distance from that source surface is0.7923mm. All weights
are normalized and nonnegative. Subsequent geometry displacement is identical
in Basis and both corrective keys. Relative-delta error1.86e-9m; actual mesh and
shape-key storage errors0 after writing BMesh back into the Blender mesh.

Linear tessellation alone produces visible vertical shading bands, so affected
points are smoothly projected onto V23's subdivided rest Basis surface before
sculpting. Source modifiers/driver mutes/key values are restored after the
read-only surface capture. Maximum projection2.573mm. Native material, rig,
pose rules, lighting, cameras and scoring are unchanged.

Ear relief is rebuilt over a quadratic local skull fit sampled outside the old
ear. An oval cushion/rim/concha replaces the crude rectangular relief. Actual
maximum ear-sculpt displacement8.149mm across1,998 points. No separate floating
ear object, render-only image edit, changed reference or score adjustment.

## Fixed-protocol results

| View | V23 | V24 |
| --- | ---: | ---: |
| Front |79.59793|79.66999|
| Side |81.19312|81.17726|
| Back |79.56401|79.63506|
| Mean |80.11835|80.16077|
| Minimum |79.56401|79.63506|

Side regresses0.01586. Selection accepts that small regression for inspected
continuous ear shape and improvement in mean/minimum, not as an all-view gain.
These are provisional image-agreement scores, not a certified 3D percentage.

## Verification and limitations

- Actual front/side/rear head closeups, all three formal neutral views and both
  static squat/push-up renders inspected. Ear blockiness improves; neck bands,
  simplification of facial anatomy, axilla and knee deformation defects remain.
- Canonical structural validation: zero errors/warnings.
- Candidate and canonical fresh-load driver QA pass82 transition states,
  1,004 transfer samples/driver and invariances without changing tolerances.
- `validate_pose_correctives_v14.py` now accepts explicit
  `--expected-refined-vertex-count 22020`. It requires that exact control count
  and labels the descriptive V13 pointwise geometry comparison **not comparable
  due to different topology**. No fake distance/equivalence is reported. All
  driver checks remain unchanged. Default mode still requires equal topology;
  fresh V23 regression run passes and gives the same prior distances.
- Static-pose reports have zero errors/warnings. No exhaustive animation,
  self-intersection or iOS runtime portability claim.
- All57 calibration tests pass.

Evidence lives in `renders/v24-experiments/projected-ear/` and the selected
formal capture. Do not assume pre-V24 scripts with fixed vertex indices or
V13 geometry arrays can consume this changed topology without adaptation.

## Retained, unselected branches

- `refinement-only`: tessellation control, side/back closeups inspected;
  unwanted vertical bands and no ear improvement. No formal scoring.
- `oval-ear`, `oval-ear-verified`: unprojected oval relief, superseded because
  the tessellation bands remain. Verified branch adds mesh/key storage checks.
- `open-rim`: thinner anterior rim and added tragus study. Only side closeup
  inspected; not formally scored or motion-validated. Not included in V24.
