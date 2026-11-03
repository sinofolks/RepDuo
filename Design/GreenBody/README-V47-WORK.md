# GreenBody V47 working baseline

V47 is an unfinished, verifiable geometry baseline. Its exact SHA-256 is
`01d85cf8ca67a30e55e7021aca8b508d6ae8025f0fa48d196845cdb186194220`.

It combines V45's 6% X-only lower-leg/ankle taper with a 4% local foot-chain
X cross-section expansion. Both rest-space fields are copied identically into
every relative shape key; the rig, vertex weights, stance, cameras, material,
lighting and scoring are unchanged.

Under the separately versioned v4 reference, V47 scores front 81.72446, side
85.11425 and back 81.61177; mean 82.81683 and minimum 81.61177. This improves
every v4 view over V45 and V40-v4. The 10% ankle limit and foot-width-only
study are retained as rejected evidence in `current-model.json`.

Evidence is retained in `renders/v47-experiments/ankle06-foot-x-width-04/` and
`calibration/multiview-reference-v4/captures/V47-ankle06-foot-x-width-04/`:
structural checks, fresh driver validation, and actual squat/push-up renders
all pass. V47 has not met 99 and is not approved for animation/runtime.
