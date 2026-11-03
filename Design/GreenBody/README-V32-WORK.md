# V32 — bounded face-profile refinement

Unfinished working model, not a 99% reconstruction. `GreenBody-v32-work.blend`
has SHA-256 `df5ce9108ac35098ea7833931502d3eed3624af673a6f47898f1e28f3f73d95c` and is
an exact copy of the V32-face-profile canonical capture.

V32 starts from V28 and changes only continuous anterior head surface: nose tip
7mm, related bridge up to2.45mm, chin6mm and a shallow intermediary recess.
The fields are restricted to the facial plane/head height; the recess prevents
a single projecting beak. Same deltas are applied to Basis and all correctives;
weights/rig/fixed pose/reference/cameras/material/scoring are unchanged.

| View | V28 | V32 |
| --- | ---: | ---: |
| Front |81.52909|81.52631|
| Side |82.85846|83.03922|
| Back |81.47567|81.47584|
| Mean |81.95441|82.01379|
| Minimum |81.47567|81.47584|

The primary measured gain is side profile; front changes only-.00279 and back
+.00017. Actual head front/side/rear closeups and squat/push-up evidence were
inspected. Canonical structural validation reports zero errors/warnings;
fresh-load driver QA passes strict identity transfer,82 transitions and
invariances. The V24 topology caveat remains: V13 pointwise geometry comparison
is explicitly not comparable, never treated as equivalence.

Unselected V29/V30/V31 are retained as evidence: extra feet-only inset regresses
all views; shoulder-root inset regresses front/back; feet center+width improves
front/back but collapses side to78.08. None is included in V32.

Further retained rejections: V33 narrows hips/shins by 4%/5% and improves side
to83.11 but damages front/back to80.61/80.66; its mean81.46 is below V32. V34
changes pigment from BEE83B to BFEA3B only; it preserves geometry but its
mean81.97/min81.41 is lower than V32. These results rule out both simple
transverse shrinking and small brightening as the next accepted step.
