# V25 — bounded limb-path and foot-stance correction

Unfinished working model, not a 99% reconstruction or final animation asset.
Selected `GreenBody-v25-work.blend`, SHA-256
`97ddbfea1c05de302d54bc7a8d02825ad7ced72bb614675682741144aac2f1a4`, an exact
copy of `calibration/multiview-reference-v3/captures/V25-limb-stance/canonical.blend`.

## Geometry and evidence

V25 starts from V24 and changes only rest-surface X positions. It keeps the
fixed turnaround pose, reference, cameras, material and scoring protocol intact.
It adds a smooth 25mm arm mid-section bow at rest height1.075m, 14mm wrist
return at.82m, and35mm toe/forefoot inset. Shape-key deltas remain exactly
relative to Basis, weights/rig are unchanged and the mesh stays closed.

| View | V24 | V25 |
| --- | ---: | ---: |
| Front |79.66999|81.41749|
| Side |81.17726|81.69790|
| Back |79.63506|81.25659|
| Mean |80.16077|81.45733|
| Minimum |79.63506|81.25659|

All three views improve under the fixed protocol. Actual front/side/back and
squat/push-up renders were inspected. Structural validation reports zero errors
and warnings. Fresh-load driver QA passes strict identity-transfer sampling,
82 transitions and invariances. As with V24 topology, V13 pointwise mesh
comparison is honestly reported as not comparable rather than manufactured.

`V26-limb-ends` tested stronger hand38mm and foot65mm inset. It scores
front81.14752/side79.70461/back81.01973, mean80.62395, minimum79.70461.
Rejected: it regresses every view from V25, especially side. It is not selected.

Remaining issues include simplified head/facial anatomy, neck transition,
torso/hip volume, axilla, knees and full animation collision behavior. No iOS
runtime-port or exhaustive motion approval is claimed.
