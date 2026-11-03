# V36 — Lab-guided uniform pigment

Unfinished working model, not a 99% reproduction. `GreenBody-v36-work.blend`
SHA-256 `9668ef46af8e942f2a8d831cd03467239a84eb20ee960119502fa05a62765de6` is the
exact V36-bright-pigment canonical capture.

V36 is V32 geometry unchanged. Its material-only builder establishes matching
geometry/pose/lighting/camera/shape-key/weight/rest-bone hashes before and after
the change. One native uniform body pigment changes BEE83B→C2E93C; roughness.48,
specular IOR level.24 and SSS0 remain unchanged. No render compensation,
image edit, per-view material or scoring edit exists.

V32 overlap Lab mean indicated candidate brightness about0.8–1.0 lower and a
slightly more-negative green coordinate. C2E93C raises/corrects that residual:

| View | V32 | V36 |
| --- | ---: | ---: |
| Front |81.52631|81.65694|
| Side |83.03922|83.15274|
| Back |81.47584|81.53796|
| Mean |82.01379|82.11588|
| Minimum |81.47584|81.53796|

The C2EA3F follow-up V37 raises front81.70044 but reduces side/back and aggregate
to mean82.09194/min81.50057, so it is retained and rejected. V35 narrow elbow
bow is also rejected (mean81.69567). V36 retains all V32 structural, driver and
static-pose evidence; geometry hash is exactly equal to V32 in the formal
capture. It does not establish exhaustive animation, collision or iOS runtime
approval.
