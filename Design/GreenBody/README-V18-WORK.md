# V18 — arm proportion and driver-response correction

Current working model: `GreenBody-v18-work.blend`.
SHA256: `543f15d9c93754ebf1ad87bf00832e9a11e91291f11e3c29b3d093d05cf924f2`.
Exact copy of `calibration/multiview-reference-v3/captures/V18-arm-rebalanced/canonical.blend`.
Unfinished; **not99**, not animation-approved, not integrated into iOS.

## Selected changes

`scripts/build_green_body_v18.py`, source V17.1, width `.012`, length `0`,
upperarm-undo `1`:

- Real shoulder/rest-arm chain moves12mm laterally on each side, with matching
  skin-weight-blended surface displacement. Shoulder bones transition into
  unchanged central skeleton; arm lengths and hand size remain unchanged.
- Every wrist descendant, including metacarpals, translates rigidly. Builder
  verifies this explicitly rather than identifying only finger-name prefixes.
- Retracts the earlier V15 upper-arm surface compensation using the exact
  V15.1-minus-V14 base-geometry delta (both source hashes recorded). The new
  wider rig makes that previous lateral surface offset excessive. V16 hand
  smoothing and V17 calf shaping remain intact.
- Every corrective key receives the same base displacement; relative shape
  deltas and skin weights are preserved. The V14 artistic corrective rule is
  unchanged, but its F-curve transfer is corrected as described below.

## Two discovered defects, fixed before selection

Initial V18 builders overlooked four metacarpal bones per hand. The resulting
width/length candidates produced visible wrist folds in squat. Those files
and their scores are retained as **rejected studies**, not selected models.
Corrected descendant handling removed the new wrist kink in actual renders.

The existing shape-driver F-curves contained implicit Bezier identity points
`(0,0),(1,1)`. Native evaluation of input `.9999157444471376` returned `1.0`.
This pre-existing endpoint snapping was newly exposed by the changed rig in
the82-state transition test. Original and evaluated IDs both showed the same
maximum error `8.42555528624e-5`; it was not merely a stale original-ID read.
Diagnostic evidence: `renders/v18-experiments/width-length/driver-diagnostic.json`.

V18 replaces the Bezier transfer points with a native degree-one GENERATOR,
coefficients `(0,1)`. The same input now returns `.9999157190322876`.
Driver expressions, variables, artistic gates and response range are unchanged.
The original2e-5 transition tolerance was **not relaxed**. The validator now
also tests1,004 direct transfer inputs per curve with1e-6 tolerance, including
the problematic endpoint neighborhood. Selected maximum transfer error is
`2.95639037695e-8`. Old saved models remain unchanged and are not claimed to
pass this newly strengthened transfer guard.

## Fixed-protocol capture comparison

Reference-v3, pose-v2, native appearance and the existing studio/scorer are
unchanged. New bones/mesh are actual model changes, not per-view pose changes.

| Candidate | Front | Side | Back | Mean | Minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| V17.1 baseline | 76.4063 | 78.5372 | 76.3117 | 77.0851 | 76.3117 |
| Corrected width12mm | 78.9158 | 78.7065 | 78.8016 | 78.8080 | 78.7065 |
| Corrected width12mm + length4% | 78.4171 | 79.2884 | 78.2944 | 78.6666 | 78.2944 |
| Corrected width20mm | 78.7201 | 78.8011 | 78.5812 | 78.7008 | 78.5812 |
| Selected width12mm + arm rebalance | 79.5250 | 78.7203 | 79.4257 | 79.2237 | 78.7203 |

Selected front torso height-band score78.765, shoulders82.762. Previous V17.1
shoulders were about85.8, so not every region improved. Side remains the
minimum view, and feet/ankles, head/ear/neck, knee folds and axilla require
substantial work. The report is projection agreement, not certified3D fidelity.

## Verification

All selected neutral views and actual squat/push-up renders visually inspected.
Evidence: `renders/v18-experiments/arm-rebalanced/poses/` and corresponding
formal capture. Fresh-load driver QA,82 transition samples, single-arm and
camera/global-transform invariance pass in `arm-rebalanced/driver-validation.json`.
Structural verification: `validation-v18-work.json`.57 calibration tests pass.
Neither static rendering nor these tests certify collision-free animation.

The builder intentionally defaults to V17.1 for reproducible experiments;
its transfer-conversion precondition expects the old two-point Bezier curve.
Do not blindly rerun it on the already-corrected selected V18 or apply the
V15-reversal twice. Future model editors must preserve the native generator,
relative corrective deltas and corrected hand-descendant rig relationships.
