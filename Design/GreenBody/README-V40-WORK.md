# V40 — rig-consistent 1.5% arm-chain extension

Unfinished working model; numeric 99 target remains unmet. `GreenBody-v40-work.blend`
SHA-256 `f55e2f2e2b07e4a4caee8568a4ce30c85416dc1def10e47bc09d2bf7aff6bfc9` is
the exact V40-arm-length-15 canonical capture.

Fixed-protocol landmark data showed elbows/wrists high in both front and side,
where knees/ankles already aligned. V40 extends each upper/lower arm chain 1.5%
in its actual rest-bone directions. It applies matching skin-weighted
displacements to mesh Basis and each corrective key, then moves every affected
rest bone—including all wrist descendants—by the same endpoint field. Segment
ratios are asserted at1.015; all weights and relative-key deltas are preserved.

| View | V36 | V40 |
| --- | ---: | ---: |
| Front |81.65694|81.63624|
| Side |83.15274|83.36285|
| Back |81.53796|81.53865|
| Mean |82.11588|82.17925|
| Minimum |81.53796|81.53865|

Front changes-.02071, while side/back, mean and minimum improve; selection
prioritizes the two aggregate gates, not a claim of all-view gain. Actual squat
and push-up renders were inspected; canonical structural validation has zero
errors/warnings, and fresh driver QA passes strict transfer/invariance checks.

V39 at2.5% has higher side but lower minimum; V41 at1% has lower mean/minimum.
V38 surface-only arm lowering is rejected for severe front/back regression. The
first V38 invocation had an inverted mask and changed zero vertices; the code
was fixed before the distinct `arm-hang-fixed` run, whose actual 3,986-vertex
change is the rejected result. No exhaustive collision or iOS runtime claim.

V42 additionally moved true arm-chain endpoints vertically (elbow20mm,
wrist40mm) with identical skin displacement. It drives side84.27 but front/back
to80.19/80.07, so is rejected. V43 at elbow5mm/wrist10mm has the best mean of
these vertical studies (82.21964) but minimum81.49122, below V40's81.53865;
also rejected. The score tradeoff is therefore documented rather than hidden.
