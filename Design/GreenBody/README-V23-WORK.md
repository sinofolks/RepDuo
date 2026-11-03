# V23 — bounded lower-face refinement

Unfinished working model, not a 99% reproduction and not approved for final animation.

Selected file: `GreenBody-v23-work.blend`, SHA-256
`ca681431c0936d3f9f2e02af67a585c30dbd74ebb0c4c34ea4596b3f2356b3d5`.
Exact copy of `calibration/multiview-reference-v3/captures/V23-face-only/canonical.blend`.
V21 and all experiments remain available; no iOS asset was changed.

## Model change

`scripts/build_green_body_v23.py` uses V21 directly. A smoothly bounded 12%
lower-jaw taper and up-to-8 mm anterior facial-plane adjustment affect only
rest heights 1.565–1.760 m. Actual maximum displacement is 8.738 mm over 2,574
vertices. The same displacement is applied to Basis and every corrective key;
measured relative-key delta error is zero. Rig, weights, topology, material,
studio, fixed pose protocol and scoring are unchanged.

## Fixed-protocol results

| View | V21 | V23 |
| --- | ---: | ---: |
| Front | 79.57852 | 79.59793 |
| Side | 80.90295 | 81.19312 |
| Back | 79.54508 | 79.56401 |
| Mean | 80.00885 | 80.11835 |
| Minimum | 79.54508 | 79.56401 |

These are provisional image-agreement scores, not a certified reconstruction
percentage. Every view remains below the numeric target of 99.

## Inspection and checks

- Actual front/side head closeups, all three neutral views and both squat and
  push-up renders inspected. Lower-jaw contour is modestly improved; square ear
  relief, neck bands, axilla and knee deformation defects remain.
- Fresh-load structural validation passes with zero errors and warnings:
  `renders/v23-experiments/face-only/validation.json`.
- Fresh-load driver validation passes unchanged strict tolerances, including
  82 transition states, 1,004 transfer samples per driver and invariances:
  `renders/v23-experiments/face-only/driver-validation.json`.
- Static-pose evidence: `renders/v23-experiments/face-only/poses/`.
- These checks do not certify self-intersection-free or exhaustive animation.
- All 57 calibration tests pass. Selected snapshot hash matches its canonical
  capture and manifest; V21 and fixed-reference hashes remain unchanged.

## Rejected experiments

V22 extends the existing local-fairing builder with `--region head`, using
30 two-pass smoothing iterations and a 4 mm displacement cap. Its mean score
is 80.01816 but actual side/rear inspection shows ears smearing into horizontal
ridges. Rejected; no selected model includes this smoothing.

`renders/v23-experiments/face-plane/` combines the face adjustment with that
rejected V22 source. It is only an exploratory render, not scored or selected.
The selected `face-only` branch starts from clean V21 instead.

A read-only BMesh probe found both shape-key and deform-weight layers on V21.
No topology refinement has been implemented or validated. Do not interpret
this probe as proof that subdivision preserves existing corrective behavior.
