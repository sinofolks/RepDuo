# GreenBody V45 working baseline

V45 is an unfinished, verifiable geometry baseline. Its exact SHA-256 is
`bc7c9e7b2e32aab124644eb03a6b2f0792fce9bb29b0cb6cc3e1417ea965cbe3`.

It changes only lower-leg/ankle rest-surface X cross-sections: a 6% taper fades
between the foot and knee and is applied identically to every relative shape
key. The rig, vertex weights, feet, pose, cameras, material, lighting and
scoring implementation remain unchanged.

The v4 reference protocol was created after the user's explicit authorization
to correct the side reference/joint annotations. Its source artwork is
byte-identical to v3; only side shared-joint vertical annotation coordinates
were reconciled to the fixed common orthographic-camera constraint. See
`calibration/multiview-reference-v4/reference-v4-authorization-audit.json`.

V45 v4 scores are front 81.68819, side 85.08828, back 81.58757; equal-view
mean 82.78801 and minimum 81.58757. The separately recaptured V40 v4 baseline
is 81.63624/85.06909/81.53865, so V45 improves every v4 view. This does not
meet 99, and neither scores nor reference revisions certify model completion.

Evidence: `renders/v45-experiments/ankle-x-taper-06/` includes source-preserving
structural validation, fresh-load driver validation and actual squat/push-up
renders/reports. `calibration/multiview-reference-v4/captures/V45-ankle-x-taper-06/`
contains the canonical model and three independent captures.
