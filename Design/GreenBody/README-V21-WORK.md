# V21 — native pigment, foot volume and toe detail

Unfinished working model: `GreenBody-v21-work.blend`, SHA256
`669f34b5ed3f5550805f5e8a5ee768a4dc31272acb6e09eebe5ab8be105ff114`.
Exact copy of `calibration/multiview-reference-v3/captures/V21-toe-fairing/canonical.blend`.
**Not99**, not approved for animation or iOS integration. V18 and all prior
models remain intact; V20's unfaired toe version is also saved separately.

## Actual changes and controls

`build_green_body_v19.py`: a single uniform native pigment, sRGB `BEE83B`,
roughness.48/specular.24/subsurface0. This is a restrained color change from
V18's B8E53B, not an image edit, emission compensation or camera-specific
shader. Geometry, rig, keys, weights and studio state checked unchanged.
All three V19 variants have identical evaluated geometry/pose hashes and
pixel-identical masks to V18. PNG file bytes can differ due to metadata;
the initial byte-equality diagnostic failed, but decoded pixels matched.
The combined V20-warm-foot similarly matches V20 geometry/pose/mask pixels.

`build_green_body_v20.py`:18mm maximum forefoot dorsal lift and14mm maximum
upper-heel posterior fill, bounded by foot skin weights, forward distance and
smooth height masks.1,554 vertices changed. All X coordinates, rest points
at/below8mm, points at/above160mm, rig and skin weights remain unchanged.
It does not lengthen the toe tips; the upper heel extends posteriorly, so it
would be inaccurate to claim every definition of total foot length unchanged.
The sole contact geometry is preserved at this V20 stage.

`build_green_body_v16.py --region toes`: adds a toe-only version of the existing
two-pass surface fairing;10 iterations with.45/−.47 coefficients,4mm cap,
1,616 vertices changed. Every shape key gets identical displacement, preserving
relative corrective deltas. Toe fairing can alter sole/toe points slightly;
the V20 sole-invariance claim is NOT inherited by V21. Canonical grounding
and posed-contact checks are rerun. V21 retains the V18 hand/metacarpal rig and
native identity driver generators; no iOS runtime changes.

## Fixed reference-v3 / pose-v2 results

No reference, pose, camera, lighting, scoring-weight or threshold changes.

| Candidate | Front | Side | Back | Mean | Minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| V18 baseline | 79.5250 | 78.7203 | 79.4257 | 79.2237 | 78.7203 |
| V19 warm pigment | 79.7190 | 79.0289 | 79.6895 | 79.4791 | 79.0289 |
| V19 brighter pigment | 79.3878 | 79.0495 | 79.5103 | 79.3159 | 79.0495 |
| V19 soft satin | 79.4643 | 79.0607 | 79.6236 | 79.3829 | 79.0607 |
| V20 foot geometry only | 79.3768 | 80.5846 | 79.2884 | 79.7499 | 79.2884 |
| V20 + warm pigment | 79.5814 | 80.9095 | 79.5516 | 80.0141 | 79.5516 |
| Selected V21 toe fairing | 79.5785 | 80.9030 | 79.5451 | 80.0089 | 79.5451 |

V20 side foot height-band score improves60.9622→81.3903; front foot band
67.0564→68.4340. Its total front/back scores still slightly regress without
the color change. Bands are not semantic segmentations. V21's score is lower
than V20 by0.00529 mean; it is selected for its slightly softer toe/nail edges
in actual closeups, **not** claimed as numerical improvement over V20.

## Evidence and remaining work

- Actual matched foot closeups: `renders/v21-experiments/baseline-feet/` and
  `renders/v21-experiments/toe-fairing/feet/`. Dorsal before/after and V21 side
  inspected. Native diagnostic renders, not image manipulations.
- All selected neutral views and both squat/push-up renders inspected.
- Driver QA: `renders/v21-experiments/toe-fairing/driver-validation.json`;
  82 transition samples,1,004 transfer inputs per driver, independent values,
  single-arm and global-transform/camera invariance. Existing tolerances held.
- Structural QA: `validation-v21-work.json`.57 calibration tests pass.

These checks are not exhaustive animation or collision certification. Head,
ear and neck surfaces remain coarse; axilla and deep squat knee folds remain;
lower-shin/ankle contours, frontal foot proportions and appearance still differ
substantially. The99 objective remains active and unmet.
