# V28 — asymmetric pelvis-depth registration

Unfinished working model, below the numeric 99 target. Selected
`GreenBody-v28-work.blend`, SHA-256
`0f5580f2151415838ccfbe61618f412ca4167449aaaba7d644381bb96f44901e`, exact
copy of the V28-pelvis-asymmetric canonical capture.

## Change and result

Starting at V25, the pelvic/upper-thigh envelope is shifted smoothly forward
between rest heights.70–1.10m: 23mm on the anterior surface and 12mm posterior.
This is a measured side-view registration correction, not a pose, camera,
reference, material or scoring change. The vector is applied identically to
Basis and every corrective key; weights and rig are unchanged.

| View | V25 | V28 |
| --- | ---: | ---: |
| Front |81.41749|81.52909|
| Side |81.69790|82.85846|
| Back |81.25659|81.47567|
| Mean |81.45733|81.95441|
| Minimum |81.25659|81.47567|

The earlier uniform 23mm V27 shift is retained but unselected. It improves V25
yet leaves side hip front/rear residuals -0.98/-4.68 pixels. V28's independent
front/rear values reduce those to -0.98/-0.55 pixels and improves the side hip
band from79.68 to83.32 without a reference or protocol edit.

Actual squat and push-up renders were inspected. Canonical structural validation
has zero errors/warnings. Fresh-load strict driver QA passes identity transfer,
82 sampled transitions and invariances. As V24+ topology differs from V13, its
descriptive pointwise mesh comparison is explicitly marked not comparable; no
false equivalence metric is emitted. No exhaustive animation/collision or iOS
runtime claim.
