# V17.1 — calf contour and hand surface work

Unfinished working geometry; **not 99**, not approved for animation or iOS integration.

Selected file: `GreenBody-v17.1-work.blend`, SHA256
`ff0baaad4f893966831c5903a341b1caba8ca967ff3e2e52e239b58dddb461d8`.
Exact copy of `calibration/multiview-reference-v3/captures/V17-calf-and-hand/canonical.blend`.
V15.1 and all other historical versions are preserved.

## Actual changes

`scripts/build_green_body_v17.py` starts with V15.1. It translates bounded calf
cross-sections medially by at most 18 mm. The envelope is sin-squared along
the tibial segment (parameter .04–.96), fading at the ends, with lower-leg
skin-weight and radial support. Bones, pose and skin weights are unchanged.
This is a surface-contour study, not an anatomical claim about tibial alignment.
The upper/middle calf is closer to the reference; the lower shin/ankle still
diverges, so simply increasing the whole amplitude is not an established fix.

`scripts/build_green_body_v16.py` applies ten pairs of local surface smoothing
passes (.45/−.47) to finger-weighted vertices, with a 4 mm displacement cap.
Actual maximum is approximately 2.97 mm, affecting 2,958 vertices. It softens
some hard knuckle/nail transitions but does not solve wrist folds or all finger
bends. The filter is not claimed to conserve volume exactly.

Both builders apply identical displacement to every shape key and verify
unchanged relative corrective deltas, weights and manifold connectivity.
The selected combination retains the V14 two-sided bone-driven trapezius
correctives and V15 smooth upper-arm shaping. The separate hand-binding
diffusion experiment is **not included**.

## Same-protocol results

Reference-v3, pose-v2, studio/cameras, scoring weights and thresholds unchanged.

| Actual capture | Front | Side | Back | Mean | Minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Previous V15.1 | 74.0555 | 78.5443 | 74.0022 | 75.5340 | 74.0022 |
| V16 hand only | 74.0882 | 78.5446 | 74.0148 | 75.5492 | 74.0148 |
| V17 calf only | 76.3736 | 78.5368 | 76.2991 | 77.0698 | 76.2991 |
| Selected V17.1 combined | 76.4063 | 78.5372 | 76.3117 | 77.0851 | 76.3117 |

V17 calf-only front shin height-band score increases from ~74.8 to 82.3523.
These are height bands, not semantic anatomical segmentations. Hand-only gain
is tiny. Side score slightly regresses with the calf edit; no claim of uniform
improvement across every view or region.

## Verification and evidence

- Actual neutral three-view renders: `calibration/multiview-reference-v3/captures/V17-calf-and-hand/`.
- Actual squat/push-up renders, each visually inspected: `renders/v17-experiments/calf-and-hand/poses/`.
- Independent fresh-load driver checks: `renders/v17-experiments/calf-and-hand/driver-validation.json`.
- Structural check: `validation-v17.1-work.json`.
- 57 calibration unit tests pass.

Driver QA covers 82 sampled transition states, independent analytical values,
single-arm independence and global-transform/camera invariance. It is not
exhaustive animation or collision validation. Difference from V13 geometry
includes intentional V15/V17 sculpting, not a driver failure metric.

Remaining issues: shoulders/axilla gap, arm placement, lower shins/ankles and
feet, coarse head/ear/neck, finger bends, and deep knee folds in squat. Existing
protocol remains locked. Any future pose-calibration study must be separate,
explicitly versioned and rebaseline unchanged models rather than claiming a
different protocol's scores as pure geometry progress.
