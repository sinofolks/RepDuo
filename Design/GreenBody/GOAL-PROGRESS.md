# Active goal checkpoint — 2026-09-13

## Latest — V53 foot cross-section selected

V53 exact SHA `67e5215fab5a865ad77dd701c996b18b86b5bba562aeb3924e830a9ad3ba6edb`
uses the best tested15% foot-chain X cross-section from V50. Scores:
82.01729/84.94952/81.95021,mean82.97234,min81.95021, better than validated10%.
25% regresses all aggregates and is rejected. Fresh driver QA and actual squat/
push-up reports have0errors/warnings. Still not99 and not animation approval.

## Latest — V52 foot cross-section selected by mean/minimum

V52 exact SHA `0a518d65ecadf31a10e68d242ba1178c890dfa18eff0815c6f40dbc0a2008434`
adds a bounded10% foot-chain X cross-section field to V50. It scores
82.01701/84.92788/81.94993,mean82.96494,min81.94993, improving aggregate
mean/minimum over V50 while recording side−.12462. Structural/driver QA and
actual squat/push-up reports have0errors/warnings. Still not99, not animation
approval, no iOS edit or commit.

## Latest — V50 waist cross-section selected

V50 builds bounded central torso X expansion from V49. V503.5% exact SHA
`956774764f7d7ef18a3d832a8409612e64a14371da98d3987b7ec77fc6576449` scores
81.90913/85.05250/81.86342,mean82.94168,min81.86342: every view/mean/minimum
improves. V50 5% scores81.89111/85.04167/81.84756 and is rejected. Structural
validation, strict fresh driver QA and actual squat/push-up reports have0errors/
warnings. Still not99, not animation approval, no iOS edit or commit.
Material-only V51 (same C2E93C,rough.35/spec.30) scores81.87791/84.90461/
81.73502,mean82.83918/min81.73502; it regresses V50 and is retained rejected.

## Latest — V49 shoulder-root inset selected by mean/minimum

V48 thighX4% score81.70483/85.09197/81.63614,mean82.81098,min81.63614 and
loses mean versus V47, so is retained rejected. V49 adds a bounded6mm shoulder
root inset to immutable V47; exact work SHA
`904b729858ac765cc53866a7e100a90fef628953c8bd45fe9283269bc83374bd`.
V49 scores81.75468/85.07590/81.64415,mean82.82491,min81.64415, improving both
mean/minimum over V47 despite a tiny side change−.03835. Structural/driver QA
and actual squat/push-up reports have0errors/warnings; squat inspected. Not99,
not animation approval, no iOS edit or commit.

## Latest — V47 combined ankle/foot X cross-section selected

V45 ankle6%/V46 foot-width4%/V47 combination and V45 ankle10% were built from
immutable sources and measured under the new v4 reference. V47 exact SHA
`01d85cf8ca67a30e55e7021aca8b508d6ae8025f0fa48d196845cdb186194220` is an
exact work-model copy. V45 scores81.68819/85.08828/81.58757,
mean82.78801,min81.58757; V47 scores81.72446/85.11425/81.61177,
mean82.81683,min81.61177, therefore every view/mean/minimum improves. V45
ankle10% regresses front/back and is rejected. V47's structural checks, fresh
driver QA, actual squat and push-up reports pass with0errors/warnings; both
poses inspected. Still not99 or animation approval.

## Latest — V45 ankle cross-section selected under user-authorized v4 reference

User explicitly authorized correcting the side reference/joint annotations.
`calibration/create_reference_v4.py` created a new immutable v4 protocol: all
source artwork stays byte-identical to v3; only side shared-joint vertical
annotations were reconciled under the pre-existing same-scale orthographic
camera/pose constraint. Authorization and every old/new coordinate are recorded
in `multiview-reference-v4/reference-v4-authorization-audit.json`; v3 remains
untouched and its scores are not compared numerically to v4.

V45 is an exact copy of `renders/v45-experiments/ankle-x-taper-06/candidate.blend`,
SHA `bc7c9e7b2e32aab124644eb03a6b2f0792fce9bb29b0cb6cc3e1417ea965cbe3`.
It makes a bounded6% X-only lower-leg/ankle taper from V40, with equal delta in
all relative keys and unchanged rig/weights/feet. Fresh V40-v4 baseline:
81.63624/85.06909/81.53865,mean82.74799,min81.53865. V45:
81.68819/85.08828/81.58757,mean82.78801,min81.58757: every view/mean/minimum
improves. Structural validation, strict fresh driver QA, actual squat and
push-up reports have zero errors/warnings; squat visually inspected. Still not
99, not final animation approval, no iOS edits or commit.

## Latest — V40 rig-consistent arm chain selected

Previous V36 Lab-material turn made selected verifiable progress. This turn
diagnosed actual landmark residuals, fixed an inverted no-op V38 mask, rejected
surface-only arm path, then built/scored V39/V40/V41 real rig+skin extensions
and completed V40 QA. Goal ACTIVE/unmet/notblocked.

Current `GreenBody-v40-work.blend`, exact V40 canonical SHA
`f55e2f2e2b07e4a4caee8568a4ce30c85416dc1def10e47bc09d2bf7aff6bfc9`.
Front81.63623722002802/side83.36285006979615/back81.53864840836648,
mean82.17924523273022,min81.53864840836648;numeric99false. V36 preserved.
Manifest/README-V40 updated.

V40 extends true upper/lower-arm rest chains1.5%, matching all weighted surface
and correctives, every wrist/finger descendant. Segmentratios1.015 asserted.
Front−.02071,side+.21011,back+.00069,mean/min slightly improve. Actual squat/
push-up inspected; structural0errors/warnings and strict fresh driverQA passes.
V392.5% higher side but worsemin;V41 1% lowermean/min; rejected. V38 surface-only
drop changed3986points and regressed; originalV38 no-op confirmed0points due
inverted mask, fixed before `arm-hang-fixed`. No reference/pose/protocol/camera/
material/scoring edit, agent, commit or blocker.
Follow-up arm vertical real-bone studies:V42 elbow20mm/wrist40mm yielded
80.19391/84.27279/80.06780 and was rejected. V43 elbow5mm/wrist10mm yielded
81.60329/83.56442/81.49122, mean82.21964 but min below V40; rejected. Both
preserve matching skin/key/bone displacement; V40 remains selected.

New read-only audit `calibration/audit_reference_3d_consistency.py` compares
shared front/side canonical landmark Y coordinates under the locked equal-scale
orthographic protocol. It intentionally does not alter model, reference or
protocol. This is needed to determine whether exact every-view99 is physically
well-posed before further conflicting limb edits.
Audit result: reference left-elbow canonical Y differs front295.21345 versus
side313.13548 (17.92203px), above independent uncertainty combined in quadrature
(13.1555px). Wrist differs12.07862px (below its combined uncertainty); shoulder,
hip,knee,ankle differ less. Back is acknowledged as mirrored front contour, not
independent3D evidence. This is read-only evidence of a real exact-3D ambiguity,
not a reference/model/protocol mutation and not permission to fake per-view99.

---

## Latest — V36 Lab-guided uniform pigment selected

Previous V32 face-profile turn made verified geometry progress. This turn made
and scored V35 elbow, V33 lower contour, V34 material,V36 material,V37 material
variants. Goal ACTIVE/unmet/notblocked.

Current `GreenBody-v36-work.blend`, exact V36 canonical SHA
`9668ef46af8e942f2a8d831cd03467239a84eb20ee960119502fa05a62765de6`.
Front81.65694451052629/side83.15274305079058/back81.53795990685809,
mean82.11588248939165,min81.53795990685809;numeric99false. V32 remains intact;
manifest/README-V36 updated.

V36 is geometry-identical V32:material onlyBEE83B→C2E93C,roughness.48,
specular.24,SSS0. State guard confirms geometry/pose/lights/cameras/keys/weights/
restbones unchanged; captures share geometry hash. Lab residual informed this
color and all3 views improve V32. V37C2EA3F front rises but overallmean/min fall;
rejected. V35elbow bow and V33shrink/V34bright pigment already rejected. No
reference/pose/protocol/scoring/camera edits, agents, commits or blocker.

---

## Latest — V32 facial side-profile selected

Previous goal turn V28 asymmetric pelvis correction was actual verified progress.
This turn produced/rejected isolated feet/shoulder studies, then V32 local face
profile geometry with full capture and QA. Goal remains ACTIVE/unmet/notblocked.

Current `GreenBody-v32-work.blend`, exact V32 canonical SHA
`df5ce9108ac35098ea7833931502d3eed3624af673a6f47898f1e28f3f73d95c`.
Front81.52630729545282/side83.03921750440578/back81.47583953250698,
mean82.01378811078854,min81.47583953250698;numeric99false. V28 preserved. See
`README-V32-WORK.md`; manifest updated.

V32 onV28: local nose7mm/bridge/chin6mm and intermediary recess; identical keys,
weights/rig/pose/reference/cameras/material/scoring unchanged. Side+.18076,
front−.00279,back+.00017. Actual headcloseups and both static poses inspected;
canonical structural0errors/warnings and strict driverQA passes. Still simplified
facial anatomy; no final-animation/collision/iOS claim.

Rejected V29 feetonly15mm:81.50147/82.75813/81.43293. V30 shoulder-root18mm:
80.25578/82.76158/80.19855. V31 footcenter+width:81.94441/78.08371/81.81068.
All outside selection. No reference/pose/protocol/studio/scoring changes,
agents, commits or blocker.
Later evidence in this same work phase: V33 hip.96/shin.95 contour shrink
improved side83.10581 but regressed front80.60767/back80.65641 (rejected).
V34 BFEA3B pigment-only study preserved geometry but mean81.97468/min81.40575
(rejected). Both recorded in manifest/README; V32 stays selected.

---

## Latest — V28 asymmetric pelvis correction selected

Previous goal turn V25 limb/forefoot correction was substantive progress. This
turn made actual V27/V28 pelvic geometry variants, formal captures and V28
structural/driver/static-pose evidence. Goal ACTIVE/unmet/notblocked.

Current `GreenBody-v28-work.blend`, exact V28 canonical SHA
`0f5580f2151415838ccfbe61618f412ca4167449aaaba7d644381bb96f44901e`.
Front81.52909325561977/side82.85846182334724/back81.47567093717421,
mean81.95440867204708,min81.47567093717421; numeric99false. V25 unchanged.
Manifest updated; see `README-V28-WORK.md`.

V28 on V25 applies smooth anterior23mm/posterior12mm forward rest depth through
pelvis/upper thighs heights.70–1.10 only, all keys identically/weights unchanged.
No rig/pose/reference/camera/material/scoring change. V27 uniform23mm had
mean81.77336/min81.47321, retained but superseded: side hip residuals−.98/−4.68.
V28 yields−.98/−.55 and side hip band83.32. Actual V28 squat/push-up inspected;
canonical structural0errors/warnings and strict driverQA pass. No completeness
or exhaustive collision claim. No agent/commit/blocker.

---

## Latest — V25 limb path and forefoot stance selected

Previous goal turn was substantive V24 topology/ear work. This turn is
substantive V25 geometry work: fixed-protocol residual measurement, bounded arm
and forefoot edits, full three-view capture, structural/driver/static-pose QA,
then a stronger end-effector rejection. Goal ACTIVE, unmet, not blocked.

Current `GreenBody-v25-work.blend` SHA
`97ddbfea1c05de302d54bc7a8d02825ad7ced72bb614675682741144aac2f1a4`, exact
V25-limb-stance canonical. Front81.41749162893599/side81.69790104253526/
back81.25659231702888, mean81.45732832950004,min81.25659231702888. All3 improve
V24 (+1.74750,+.52064,+1.62153); numeric99 false. Manifest updated, V24 unchanged.
See `README-V25-WORK.md`.

V25 builder is `build_green_body_v25.py` on V24 topology:25mm upper/mid-arm
bow,14mm wrist return,35mm forefoot inset. No rig/pose/reference/camera/material
or scoring edits. Same vector to all keys, original weights unchanged. Actual
front/side/back and squat/push-up inspected. Canonical structural0errors/warnings;
native driver QA strict identities,82transitions,1004samples/invariances passes.

V26 stronger hand38mm/foot65mm end inset formal capture:front81.14752,
side79.70461,back81.01973,mean80.62395,min79.70461. REJECTED: lower every view,
especially side. No selection, no QA claim. Future torso/hip work begins fromV25,
notV26. No commit/agents/new blocker. 99 remains unachieved.

---

## Latest — V24 refined ear topology selected

Previous goal turn was PROGRESS: V23 model selection and verified lower-face
improvement. This turn is also substantive progress: local topology refinement,
explicit skin/key transfer, ear sculpt, source-surface projection, actual
closeup and pose checks, full3-view scoring and canonical QA. Goal ACTIVE,
unmet, not blocked. No reference/pose/studio/scoring/material/iOS changes.

Current `GreenBody-v24-work.blend`, exact V24-projected-ear canonical, SHA
`3bbaed080c08b8257e8ea2eaad2ee5a93b1b55136e026913bb9bbfc76cee9ed4`.
Front79.6699899417804 /side81.17726299737996 /back79.63506043262028,
mean80.16077112392686,min79.63506043262028. Side−.01586vsV23, explicitly accepted
for inspected less-blocky ears and mean/minimum improvement. Not99. V23 kept.
Details `README-V24-WORK.md`. Manifest updated.

IMPORTANT: topology is now22,020 controls/350,650 evaluated, not13,024/208,170.
Builder `build_green_body_v24.py` defaults sourceV23, cuts2, selected flags
`--ear --surface-project`. Original weights exact; new8,996 vertices receive
explicit closest-triangle barycentric skin/key deltas (maxsourcegap.7923mm).
All keys displaced equally;relativeerror1.86e-9m; mesh/key storageerrors0.
Original vertices outside head band unchanged. Native identity drivers intact.
Local subdivision is NOT shape-identical; source-smooth-surface projection
max2.573mm reduces its vertical bands. Oval ear sculptmax8.149mm/1998points.

Initial BMesh wrappers invalidated after subdivision, not actual vertex loss;
builder now restores exact unique coordinate correspondence (actualerror0).
Initial linear refinement-only and unprojected oval-ear were visually rejected.
`open-rim` extra study has only side closeup inspected, no formal scoring or
motion validation, not selected. Do not infer it is included in V24.

Actual selected3views,headfront/side/back,and squat/push-up inspected. Structural
canonicalQA0errors/warnings, bothpose reports0errors/warnings. Candidate AND
canonical fresh driverQA pass82transitions/1004samples/invariances. New explicit
validator flag `--expected-refined-vertex-count 22020` checks exact count and
reports V13 geometry comparison NOT COMPARABLE (no pointcorrespondence), while
all strict driver checks remain. Default behavior unchanged; fresh V23
regression passes identical old pointwise distances.57tests pass.
No exhaustive animation/collision approval. Future indexed source-delta
builders must accommodate changed topology. No agents, no commits, no blocker.
Final checks: V24 snapshot SHA and scores match manifest/canonical; V23 and
fixed-reference SHA unchanged. Shared report regenerated. All known modeling,
QA and report processes terminal. No background job left running.

---

## Latest — V23 lower face selected; V22 smoothing rejected

Goal ACTIVE, unmet, not blocked. Current `GreenBody-v23-work.blend` is an exact
copy of V23-face-only canonical, SHA
`ca681431c0936d3f9f2e02af67a585c30dbd74ebb0c4c34ea4596b3f2356b3d5`.
Front79.59793458312284 /side81.19311846084344 /back79.56400851480103,
mean80.11835385292243, min79.56400851480103. Manifest updated. Not99.
See `README-V23-WORK.md`; V21 is preserved unchanged.

V23 builder on clean V21 applies jaw-taper.12 and face-forward.008, actual
maximum8.738mm,2574 vertices. Same displacement to every key, relative delta
error0, weights/rig/topology unchanged. Actual front/side head closeups, all3
neutral views and squat/push-up inspected. Structural QA0errors/warnings and
fresh native-driver QA82 transitions/1004 transfer samples/invariances pass.
Existing ear/neck/axilla/knee defects are not resolved or approved.

V22 head fairing (30iterations,4mmcap) had mean80.01815586 but actual ears
smeared into horizontal ridges: REJECTED. V23-face-plane source was that V22,
so also not selected; head renders exist but no scoring. Selected V23-face-only
is independent, sourced directly fromV21 and does not inherit V22 smoothing.
Head topology investigation so far is READ ONLY: BMesh exposes3shape layers
and deform weights. No subdivision, topology replacement or proof of safe
interpolation has been implemented. Future topology edits require robust
shape/weight/driver validation; current driver validator's descriptive V13
comparison assumes identical vertex count.

No reference/pose/protocol/scoring/studio/material/iOS changes this turn.
No agents or commits. No new blocker, no goal status change.
Final checks:57 calibration tests pass; selected V23 SHA matches capture and
manifest, V21 and fixed reference SHA unchanged. Both static-pose reports have
zero errors/warnings and source-unchanged true. Shared report regenerated.
All known jobs terminal; no background modeling job left running.

---

## Latest — V21 pigment/foot/detail work selected

Goal ACTIVE, unmet, not blocked. Previous turn was substantive V18 progress.
This turn produced three uniform-material variants, foot-volume geometry,
combined capture and toe fairing (six complete three-view captures), with
actual closeup/static-pose inspection. No reference/pose/studio/scoring/iOS
changes, no agents or commits. See `README-V21-WORK.md`.

**Current: GreenBody-v21-work.blend**, SHA
`669f34b5ed3f5550805f5e8a5ee768a4dc31272acb6e09eebe5ab8be105ff114`, exact copy
of `calibration/multiview-reference-v3/captures/V21-toe-fairing/canonical.blend`.
Front79.57852254484692 /side80.90295390811069 /back79.54507728490252,
mean80.00885124595338, min79.54507728490252. Numeric99 false. Manifest updated.
V18 preserved; `GreenBody-v20-work.blend` also saved, hash
`602b22420f03161eafff84d17cfe5b5679e95096f2d1f2417911410bbd845809`, exact
V20-warm-foot canonical (mean80.01414135, min79.55156143). V21's tiny mean
regression.00529 is explicitly accepted for inspected softer toe/nail edges,
not misrepresented as a numerical gain overV20.

Final QA: `validation-v21-work.json` PASS0 errors/warnings; both selected static
pose reports0 errors/warnings. Selected file hash and scores agree exactly with
canonical summary and manifest. V18/reference-v3 hashes verified unchanged.
Shared report regenerated. All known tool sessions terminal; no live modeling
process left. Goal remains active; no completion or blocked claim.

`build_green_body_v19.py`: uniform pigment BEE83B,roughness.48/specular.24/SSS0;
native body material only, geometry/rig/keys/weights/studio state unchanged.
Material now named GB_V19_UniformPigment_BEE83B (capture may copy-name suffix).
Source geometry/pose hashes and decoded masks match all3 V19 trials exactly;
PNG byte comparison initially failed because metadata differs, decoded pixels
do NOT. Warm pigment chosen over C1ED3F and softer BRDF (.65/.12/SSS.02).

`build_green_body_v20.py` onV18: dorsal forefoot lift18mm, upper-heel posterior
fill14mm,1554 vertices, smooth/skin masks. Rig/weights/allX unchanged; z<=.008
and z>=.16 untouched, toe tips not lengthened. Upper-heel envelope extends, so
do not claim all foot length unchanged. Foot-only mean79.74993452, side foot
band60.962→81.390; front foot band67.056→68.434. Material then applied usingV19
builder to create `renders/v20-experiments/warm-foot/candidate.blend`.

V21 `build_green_body_v16.py --region toes` onV20-warm-foot; original default
hands algorithm unchanged. Ten .45/−.47 pass pairs,4mmcap,1616 vertices; all
relative corrective deltas/weights unchanged. Sole points MAY change slightly
under fairing, so V20's sole-invariance claim does not apply toV21. Grounding
and pose checks rerun. New read-only `inspect_green_body_feet.py` renders side
and dorsal native closeups. Before/after dorsal and V21 side inspected; actual
selected all3 neutral views and both squat/push-up inspected. Toe folds softer
but all broader existing head/neck/knee/axilla/foot-proportion defects remain.

V20 and selected V21 driver QA pass82 transitions,1004 transfer inputs and
invariances with unchanged tolerances.57 tests pass. Preserve V18 identity
GENERATOR curves, all relative shape deltas and corrected metacarpal rig.
Do not claim exhaustive animation/collision approval or99. No new blocker.

---

## Latest — V18 arm rig/skin correction selected

Goal ACTIVE, unmet, not blocked. Previous turn was actual V17.1 progress;
this turn made actual rig/skin edits, six full three-view captures, identified
and fixed a metacarpal omission and a pre-existing driver-transfer snap, then
selected a verified improvement. No reference/pose/scoring/camera/material/iOS
changes, no agents or commits. See `README-V18-WORK.md`.

**Current: GreenBody-v18-work.blend**, SHA
`543f15d9c93754ebf1ad87bf00832e9a11e91291f11e3c29b3d093d05cf924f2`, exact copy
of `calibration/multiview-reference-v3/captures/V18-arm-rebalanced/canonical.blend`.
Scores front79.52502672025949 /side78.72034576379338 /back79.42571280861496,
mean79.22369509755595, min78.72034576379338. All below99. Current-model manifest
updated; V17.1 and old models preserved.

Final QA: structural `validation-v18-work.json` PASS0 errors/warnings, both
pose reports0 errors/warnings; selected file hash and scores match summary and
manifest. V17.1/reference-v3 hashes verified unchanged. Report regenerated.
All known tool sessions terminal; no live background modeling job remains.

Builder `build_green_body_v18.py` sourceV17.1, width.012/length0/upperarm-undo1:
real lateral12mm shoulder/rest-arm displacement and matching skin edits;
arm lengths/hands unchanged. Correctly includes ALL wrist descendants,
including metacarpals. Retracts V15.1-minus-V14 upper-arm surface compensation
now excessive with wider rig, preserving V16 hands/V17 calves/V14 key deltas.
New driver F-curves are native identity GENERATOR (degree1,coefficients0,1).

Initial width-only and width-length studies are REJECTED: omitted metacarpals
produced wrist folds; first driver check also failed. Read-only
`diagnose_v18_drivers.py` proved both original/evaluated keys had max8.4256e-5
error only near top endpoint. Existing Bezier identity transfer snapped
input.9999157444 to1; native generator now yields.9999157190. Driver-expression
math unchanged, transition tolerance2e-5 NOT relaxed. Validator now additionally
checks1004 transfer inputs with1e-6 tolerance (selected error2.9564e-8), and
assertion failures include actual/expected/distances. Earlier saved models
unchanged; do not claim old V17 passes the new transfer test.

Other captures: corrected width12 mean78.807984/min78.706511; corrected
width12+length4% mean78.666602/min78.294381; width20 mean78.700808/min78.581158.
Both lose to selected rebalanced model. Intermediate `width-length-fixed-hand`
has metacarpals fixed but NOT the driver transfer; not selected or scored.
All variants preserved. Selected all3 neutral views and squat/push-up actually
inspected. Driver QA on exact canonical passes82 transitions plus invariances
and new transfer guard;57 unit tests pass. No full animation/collision approval.

Future builders must preserve corrected metacarpals, shape-key relative deltas,
drivers and identity generator. V18 builder defaults toV17.1 and asserts its
old Bezier-transfer precondition; do not blindly use V18 as its input or undo
V15 twice. Remaining larger issues: side feet/ankles, coarse head/ears/neck,
lower-shin contour, axilla and squat knee folds. Color/shading agreement remains
weak (~70–75/~30–35), so appearance work matters too; no material edits yet.
Any future pose protocol study must be separately versioned/rebaselined.

---

## Latest — V17.1 calf + hand geometry selected

Goal ACTIVE and unmet, not blocked. This turn made actual modeling progress:
V16 hand fairing, V17 medial calf contour and combined three-view capture, with
real closeups/static-pose inspection and driver verification. No reference,
pose rule, scoring, camera, iOS, agent or commit changes. Prior V15.1 remains.

Current selection: **GreenBody-v17.1-work.blend**, SHA256
`ff0baaad4f893966831c5903a341b1caba8ca967ff3e2e52e239b58dddb461d8`, exact copy
of `calibration/multiview-reference-v3/captures/V17-calf-and-hand/canonical.blend`.
Selection manifest updated. Front76.40630847523046 / side78.53720449239792 /
back76.31174190804522; mean77.08508495855786, min76.31174190804522. Compared
V15.1 mean+1.5511, front/back+~2.3; side−.0071. Numeric99 remains false.

Final verification: `validation-v17.1-work.json` PASS0 errors/warnings;
both static pose reports0 errors/warnings; selected hash and summary scores
match manifest. Actual combined side/back renders also inspected. Original
V15.1/reference-v3 hashes unchanged. Shared report regenerated. All known tool
jobs terminal; no live background modeling process left.

`build_green_body_v17.py`: real medial calf-section displacement, 18mm peak,
sin² envelope across tibia .04–.96 with radius/skin masks, unchanged bones/pose.
Then `build_green_body_v16.py`: ten Taubin-style .45/−.47 hand-surface pass pairs,
finger-weight mask,4mm cap (actual2.97mm),2958 vertices. Both preserve every
shape-key relative delta and all weights; V14 drivers retained. Combined
source `renders/v17-experiments/calf-and-hand/candidate.blend`.

Independent V16-hand-fairing mean75.549207, tiny improvement; V17-medial-calf
mean77.069840/min76.299112. Actual V16 front/back/side hands and both static
poses inspected. Actual V17 calf-only and combined neutral/front and both
static poses inspected. Fresh-load V17 and combined driver QA pass82 states
and invariances.57 unit tests pass. No claim of exhaustive animation approval.
Details `README-V17.1-WORK.md`.

Separate `renders/v16-experiments/hand-binding/` uses old weight-diffusion
script on V16 with amount.35/6 iterations. Only actual side closeup inspected;
front/back also rendered but not inspected. Not scored, not motion-validated,
NOT selected or included in V17.1. Historical V10 weight studies also remain
unselected. Current hands still have unnatural wrist/finger folds.

Next evidence: at canonical rows580/610 V17 calf matches well; rows670/700
still too lateral/narrow. Do not blindly increase whole calf displacement or
move skin off bone axes. Upper arms/forearms have positional disagreement:
row240 arm spans match approximately; rows300–380 are ~8–11px too medial;
row220 candidate axilla remains joined while reference has narrow gaps. These
may require carefully separated anatomy/pose investigation. Existing pose-v2
MUST NOT silently change; any new pose study needs separate protocol and
unchanged-model rebaseline, not fabricated geometry improvement. Head/ear,
feet, knee folds and axilla still unfinished. No new blocker established.

---

## Latest — V14 driven correction, V15.1 smooth upper-arm sculpt selected

Goal remains ACTIVE and unmet, not blocked. Previous goal turn was **progress** (V12 selected with genuine geometry/rig edits, rejected V13 deformation). This turn also made substantive progress: bilateral bone-driven corrective shapes, fresh-load/pose/camera-invariance checks, four real three-view captures, three upper-arm variants and selected V15.1. No reference/protocol/camera/material/score edits, no iOS changes, no agents, no commits. All tool jobs terminal;57 tests PASS.

**Current selected model is `GreenBody-v15.1-work.blend`**, SHA256 `4d757e22f2356bbf38142062bf93e4dfb7ae5a240a360f10260fc5f3d88db841`; exact copy of `calibration/multiview-reference-v3/captures/V15-smooth-arm/canonical.blend`. `current-model.json` now points here. V12, V14 and medial-only V15 snapshots are preserved. V14 SHA `0f83cff04352f2e38ba054358a3908e58d550f7428e30f0abfc63a3268a0e53c`; medial V15 SHA `79c683f06b4323a5930f734e8ebee23f2f96ee8dd3ffc441bdc6a51ded3167db`. Reference-v3 PNG unchanged SHA `73b210848a7ea201c45ed6443fb74d5d4852fcb16794bf434814c0d6f9a6e863`.

### V14 corrective, retained in V15.1

`build_green_body_v14.py` uses preserved V13 foot10-source (V12 + foot length10%) as Basis and V13-neck-foot as target. Splits ONLY added posterior-neck delta into two bilateral shape keys, partition of unity across X. `pose_corrective_math.py`: native simple expression from5 bone-point distances per side (shoulder/elbow/wrist/lower spine), cosine-derived elevation and elbow flexion; smooth cosine gates across cosine.25–.80, weight.2+.8*gate_elevation*gate_elbow. Neutral1, squat/push-up.2. No camera/frame/pose-name logic, no external Python driver callback. This is an artistic correction, not biomechanical muscle conservation. Shape-key relative delta sums reconstruct raw V13 sculpt; after existing modifiers, neutral evaluated V14 vs baked V13 differs max1.099mm/RMS.0403mm, explicitly measured, not claimed identical.

Actual V14 squat/push-up inspected: previous sharp posterior-neck protrusion markedly attenuated; existing V12 defects remain. V14 same-protocol scores73.150485 /78.560165 /73.103749, mean74.938133. `validation-v14-work.json` PASS0 errors/warnings. `validate_pose_correctives_v14.py` fresh loads with use_scripts=False, checks82 transition samples, analytical weights, single-arm independence, global translation/rotation/uniform-scale and camera invariance. V14 and both V15 work variants pass. No collision or exhaustive animation certificate; no iOS port. Driver validation logs in each experiment folder.

### V15 variants, selection and limitations

`build_green_body_v15.py` preserves rig/weights and applies the same base displacement to EVERY shape key, verifying relative deltas. Default sourceV14. `medial` thins only inner upper arm; `translate` moves a bounded bone-relative section outward, but its short fade caused visible shoulder steps. Selected `translate-smooth` uses16mm maximum, `sin²(pi*(t-.04)/.81)` over .04<t<.85; zero value/first derivative at endpoints. Skin and radial masks bound the actual mesh sculpt. This is surface shaping around unchanged bone axes, not moving the joint annotation or changing pose rules.

- V15-medial-arm mean75.174964/min73.443696, retained as `GreenBody-v15-work.blend` but not current; width-profile torso band regressed despite boundary gain.
- V15-translated-arm mean75.527615/min73.988652, not selected: short-fade shoulder step.
- **V15-smooth-arm / V15.1** front74.05546813977159 /side78.54425821472958 /back74.00221656399317, mean75.53398097283144, min74.00221656399317. Compared V14: front+.904983, back+.898468, side−.015906; torso bands +.87 but shoulder bands −.745/−.687. Side silhouette bands unchanged. Do not claim every region improved.

Actual neutral front plus squat/push-up for ALL3 arm variants inspected; selected smooth variant removes the sharper shoulder transition while retaining V14 driver behavior. `validation-v15.1-work.json` PASS0 errors/warnings. Both static pose reports0 errors/warnings, source unchanged. Driver revalidation of selected work passes82 states and invariances. V15.1 vs V13 neutral geometry max15.76mm includes intentional arm sculpt, not a driver error. Details `README-V14-WORK.md` and `README-V15.1-WORK.md`. Report regenerated with every experiment; use selection manifest, not highest/latest run by assumption.

**Critical future edit constraint:** selected model now contains Basis +2 driven corrective keys. Any subsequent base-shape edit MUST update all shape keys consistently and preserve/revalidate drivers; older V7–V13 builders are not generally shape-key aware. Do not silently discard the corrective setup. Bone-driven logic still needs explicit runtime implementation when eventually integrating into iOS, which remains out of current modeling scope.

Remaining real defects: head/ear/neck surface quality, hand shape/pose, limb contours, knee folds and axilla/chest-shoulder indentation;99 unachieved. Continue actual shape/deformation work under reference-v3/pose-v2 without changing acceptance rules. No genuine new blocker identified.

---

## Latest — V12 selected; V11/V13 regressions rejected

Goal ACTIVE verified with get_goal, not99, not blocked. Previous goal turn was **progress**: authorized deterministic reference correction + new baseline. This turn also made concrete progress: actual model/rig edits, five full three-view experiments under the unchanged reference-v3/pose-v2 protocol, selected V12, structural and visual/static-pose QA. No iOS changes, no agents, no commits. All known tool jobs terminal.52 tests PASS.

**Current selected model: `GreenBody-v12-work.blend`**, SHA256 `1c16701319fbf5b69d0c98ad1c07db37ec4b0d7865bf85e17b0126a20cc9c514`; exact copy of `calibration/multiview-reference-v3/captures/V12-head-offset/canonical.blend`. V10 and reference-v3 image SHA `73b210848a7ea201c45ed6443fb74d5d4852fcb16794bf434814c0d6f9a6e863` preserved. `build_green_body_v12.py` makes a real15mm positive-X head/neck offset, smoothly transitioning across rest Z1.48–1.66m, with head/neck rig adjusted. This explicitly matches the approved front's small asymmetric head position; Y/Z, lower body and skin weights unchanged. No pose/camera/material/reference/score changes.

V12 scores front73.2901280030789 / side75.46959283046567 / back73.32121448849881; mean74.02697844068113, min73.2901280030789. Compared same-protocol V10, front+1.892708/back+1.951222, side−0.014330. Front/back head bands approximately+18, side silhouette bands unchanged. `validation-v12-work.json`: PASS0 errors/warnings. Actual front/side/back head closeups and both squat/push-up inspected in `renders/v12-experiments/head-offset/`; reports0 errors/warnings, source unchanged. Existing posterior head/neck crease, crude ears, knee folds and axilla indentation remain. No animation/final visual approval.

**Do not automatically select the higher neutral-pose V13 score.** V13-neck-foot mean74.93148, min73.10251 is a rejected study: posterior neck/trapezius40mm volume plus foot length10% creates an unnatural upper-back/neck protrusion in push-up, despite clean structural reports. Real pose images inspected. V13-neck-only mean72.16868 also rejected. V11-foot25 mean68.56163 rejected; V11-width30 mean72.84204 not selected because minimum/front/back regress. All trials retained. `README-V12-WORK.md` and `README-V13-STUDIES.md` explain exact changes, comparisons and visual rejection. `calibration/multiview-reference-v3/current-model.json` is the working selection authority; report.html includes both accepted and rejected studies, so latest/highest run is NOT implicitly selected.

Next work should improve actual remaining form/deformation while retaining V12 as safe baseline. V13 may be revisited only with reduced volume or a bone-pose-driven corrective that genuinely avoids its flexed-pose protrusion, followed by full recapture and visual QA. Hand pose/limb silhouette/foot proportions and coarse head/neck surface remain unfinished. Do not revert to old inconsistent reference or claim image mask100% is model fidelity. The99 goal remains unmet; no genuine blocker found this turn.

---

## Latest — deterministic harmonization completed, new baseline measured

User explicitly authorized programmatic image editing: “允许啊，快点吧”. No outstanding reference-edit permission question remains. Do not ask again. Selected working reference is `reference/green-body-turnaround-v3b-harmonized.png`; original front/side pixels and labels unchanged. Front/back source and canonical mask mirror IoU both1.0 with zero extra translation. `harmonize_turnaround.py --smooth` transfers only original-back appearance into original-front-mirrored contours. First unsmoothed V3 rejected for scanline seams; preserved. V3b smoothing inspected; authored remapping is not independent 3D evidence. Do not claim100% model fidelity or globally certified side consistency.

New reference and same pose-v2/studio profiles separately locked at `calibration/multiview-reference-v3/`. Back joints inferred from front mirror, annotation provisional. Original user-approved design and explicit harmonization authority recorded; no claim of final new-image user visual approval. Old model, original reference and old scores unchanged. `setup_reference_v3.py` re-evaluated hash-verified existing V10 captures, not newly rendered images: front71.3974203795525 / side75.48392240082327 / back71.36999278999058, mean72.75044519012211, min71.36999278999058. This is the NEW baseline, not model improvement. Report and baseline-summary.json are in the new folder.

Runner now accepts `--reference-version v3 --pose-version v2` and rejects mixed reference series. Next actual geometry changes should use this protocol, keeping old results separate. V10 remains current model; no Blender/iOS modifications this turn. Goal99 remains unmet; tool still holds historical blocked status and has no resume operation. No repeated-block count has been reached or reasserted. Details: `reference/turnaround-v3-harmonization-status.md`.

---

## Current scope — reference harmonization authorized (2026-09-13)

User replied “确认” to permission to preserve the approved design while correcting mutually inconsistent three-view contours. This resolves the previous authorization blocker. Original images, protocols and results remain immutable. Use the approved front design as authority, not the current model; generate a separate harmonized candidate, audit its cross-view consistency before selecting a new reference, then recapture models under a separately identified protocol. No threshold, weights or historical scores may be silently changed. Current V10 is still unfinished, old-protocol mean72.67007304, not99. The goal tool still reports the previous blocked status; its API has no resume operation. Continue the explicitly authorized work without claiming completion.

This resumed turn used built-in imagegen twice, then audited both candidates with `audit_turnaround_candidate.py` (read-only, same original segmentation/framing). V2 raw mirror IoU90.5738%, best translation91.5665%; V2b92.1779%, best93.2217%. Neither selected or locked. Original front was also slightly changed by imagegen despite preservation requests (retention97.7524% /98.1457%). Prompts, images, exact audit JSON and `reference/turnaround-v2-harmonization-status.md` retained. No Blender/iOS changes this turn. Next possible method is deterministic reference raster contour correction; tool instructions require explicit agreement to programmatic image editing instead of imagegen, so ask that specific method question, not repeat the already-granted general reference permission. Goal unachieved. Prior blocked-turn count must not be reused for this different issue.

## Historical goal state — BLOCKED pending reference/evaluation decision

Third consecutive occurrence of the same unresolved full-target conflict confirmed. Previous continuation was read-only revalidation with no substantive progress, not a verified running-job wait. This turn reconfirmed unchanged approved-reference and V10 hashes and the current-protocol feasibility evidence. No user authorization or external-state change has arrived. Goal has now been marked **BLOCKED**, not complete.

Reason: the approved front/back references conflict with the same-mesh/same-pose orthographic99 acceptance requirement. No legitimate path to that full fixed-protocol target was found without a user decision about harmonizing the reference or the evaluation interpretation. This is not a claim that model quality cannot improve further, nor a universal impossibility theorem for every conceivable camera/protocol. Continuing subtarget polishing does not resolve the contradictory acceptance condition. Do not silently change the reference, threshold, weights, cameras or per-view geometry to force a pass.

Waiting for user direction on preserving the approved design while correcting mutually inconsistent reference contours. All work, original references and reports are preserved; no live jobs. Current model remains `GreenBody-v10-work.blend`, SHA256 `9cfe41224d71f4357dceb5397e7955b73572ab39b42e6da27bac1e12bff6cb64`. If user resumes without resolving the issue, restart the blocked audit count per instructions; do not immediately reapply this prior three-turn count.

---

## Pending reference decision — second consecutive occurrence

The preceding turn made genuine progress (V10 geometry/captures and reference-feasibility evidence). This continuation performed **read-only revalidation, no substantive model progress**. No user reply authorizing reference harmonization has arrived; an automatic goal continuation is not approval.

Rechecked current front/back profiles: exactly opposite Y cameras at ±6.8m, same target height.91m, ORTHO scale2.1, identical768×960 render settings, and opaque white emission silhouette masks of the same mesh/pose. Approved reference SHA remains `0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4`. The mathematical bound remains applicable to the **current fixed orthographic protocol**. It is not a universal claim about every possible camera/protocol or subjective likeness.

No authorized change has been made to reference, camera assumptions, pose rules, weights, target or scores. Independent per-view geometry/poses, altered scoring weights, or raster artifacts would not honestly resolve the same-model fixed-protocol99 requirement. Perspective or a different reference interpretation would require an explicit new evaluation decision, not a silent claim that the old goal passed. Lower-score model improvements alone do not remove this full-target conflict.

Same unresolved decision now observed in2 consecutive goal turns, including its original discovery. Goal remains ACTIVE; blocked-tool threshold has NOT yet been met. Do not repeat lengthy explanations or manufacture progress with status files. On another continuation, inspect for a real user decision or changed reference/protocol state. Only mark blocked if the same conflict persists for the required third occurrence and no meaningful authorized route to the full target exists. Current work remains V10; no live jobs.

---

## Latest checkpoint — V10 leg depth; first reference-feasibility conflict discovery

Goal ACTIVE, not achieved. Previous goal turn was **progress** (V9 actual geometry, fixed pose-v2 recapture and QA); this turn also made actual model/evidence progress. **Do not mark complete. Do not mark blocked on this first discovery.** A new reference-approval decision is being requested, not silently assumed. All tool sessions terminal. No iOS edits, no commits, no agents.

Current work model `GreenBody-v10-work.blend`, SHA256 `9cfe41224d71f4357dceb5397e7955b73572ab39b42e6da27bac1e12bff6cb64`; exact copy of `calibration/multiview-pose-v2/captures/V10-legdepth/canonical.blend`. Geometry source `renders/v10-experiments/leg-depth/candidate.blend`, SHA256 `5ddd427f30a3f63b2e812519a50d0082f2d4e42f5c09d35de9abe380f6cf2c89`. V9 source unchanged. `build_green_body_v10.py`: local posterior thigh/calf volume, max28mm displacement, rest X/Z, upper body, pose and weights unchanged. No scoring or reference/protocol edits in this turn.

V10 same pose-v2 front/side/back =71.39742038 /75.48392240 /71.12887633, mean72.67007304, min71.12887633. V9 mean71.08557. Side thigh band+14.838, shin+13.150; front/back silhouette bands nearly unchanged. Actual side view inspected. `validation-v10-work.json` PASS,0 errors/warnings. Both actual squat/push-up inspected at `renders/v10-work/poses/`; reports0 errors/warnings, source unchanged. Knee and axilla defects remain; leg bulges more obvious in some flexed poses. This is unfinished working geometry, NOT animation or final appearance approval.

### New evidence relevant to the actual99 target — user direction needed

`calibration/audit_reference_consistency.py` performed a read-only feasibility check. **Do not regenerate/overwrite approved reference automatically.** Human-readable derivation `calibration/REFERENCE-CONSISTENCY-AUDIT.md`; exact results/hashes `calibration/reference-consistency-audit.json`.

- A single opaque mesh/pose under current front/back orthographic cameras has mirrored ideal silhouettes.
- Locked reference front/back mirror IoU only0.908708; even generous independent read-only ±12px X /±6px Y search gives maximum0.917602 at(+1,+1). No shift applied to scorer/reference.
- Current actual candidate mirror Jaccard distance0.001518 (rasterization differences).
- By Jaccard triangle inequality, ideal front/back composite mean upper bound with ALL other metrics100 is `100−15*(1−reference_IoU)` =98.7640314; measured raster gap gives98.78680. Allowing1% candidate raster mismatch as a sensitivity case gives98.91403. **The1% is an assumed sensitivity allowance, not a universal raster bound.** This is a fixed-protocol feasibility bound, not a claim of current model quality or subjective3D fidelity.
- Therefore the requested simultaneous99 cannot be honestly guaranteed with the ideal same-pose geometry and current mutually inconsistent locked reference. Asking user whether to harmonize conflicting contours while retaining the approved design; the goal/threshold has NOT been lowered. No new-reference authorization yet. Do not manufacture99 by changing weights, reference or per-view geometry/pose.
- This is the first discovery/request for that decision, NOT three consecutive blocked goal turns. Continue only within authorized scope; if a future explicit reply permits reference harmonization, follow that direction and keep original/reference history. Further model improvement remains possible, so don't misuse the blocked tool merely because99 is difficult.

### Hand inspection and unselected binding studies

`scripts/inspect_green_body_hands.py` read-only actual closeups at `renders/v10-experiments/v9-hands/`. Both front/back images inspected. `inspection.json` confirms both thumbs more medial than pinkies: the earlier suspected reversed-thumb orientation was NOT supported. Don't flip hands based on the small full-body preview. Actual issues are stiff finger joint transitions, fingernail/tip geometry and wrist/palm surface.

`scripts/refine_green_body_weights.py` generated independent `hand-weights/candidate.blend` and `knee-weights/candidate.blend` under `renders/v10-experiments/`. Geodesic inverse-edge-length weight diffusion, bounded joint masks, rest mesh/pose unchanged, weights normalized; build reports retained. They are **not rendered/scored/selected**, and are NOT in V10-work. Do not promote merely because weight variation decreases; inspect poses and influence counts first. No running processes remain for them.

Main pose-v2 report regenerated.47 tests PASS (44 prior plus3 reference-bound tests, including exhaustive nonempty4-pixel set triangle checks). Detailed model note `README-V10-WORK.md`. Old selected models and approved reference hash preserved.

---

## Latest checkpoint — V9 restrained, explicit pose-v2 protocol

Goal ACTIVE, not99, not blocked. Previous goal turn is **progress** (selected V7 plus actual three-view captures). This turn is also progress: real head and knee/torso edits, rejected visual regressions, independent pose-protocol revision, recaptured baseline/candidates, selected V9, structural/static-pose QA and44 passing tests. No iOS changes, no commits, no subagents. All tool sessions terminal at this checkpoint.

**Current selected work model: `GreenBody-v9-work.blend`**, SHA256 `5361058afc0f62538856076a90cecd385632a44111f17980312f661127c4f322`. Exact binary copy of `calibration/multiview-pose-v2/captures/V9-restrained/canonical.blend`; stored pose is v2. Geometry/rig source `renders/v9-experiments/restrained/candidate.blend`, SHA256 `344f3975d6b5113e0e6989442f70c0a9caee1700a878ef990a9e9bcfddf2bf72`. Canonical preparation validates rest mesh/weights unchanged. V7 and all references preserved.

### Selected real modifications

- Head component from `renders/v8-experiments/lowered-jaw/candidate.blend`, built against V7 with `build_green_body_v8.py --method lowered-jaw --strength 1 --neck-strength .6`: smoothly broader cranium/jaw/neck, local lower-face vertical extension, no anterior chin extrusion. Actual head/side/back preview renders inspected. This component is provisional visual progress, still an abstract mannequin face, not final likeness.
- `build_green_body_v9.py`: source above, `--height-mode knee-only --width-mode restrained --width-strength 1 --strength 1`. C1 monotonic height map lowers knee area up to35mm with foot and pelvis-height anchors unchanged; applies to both mesh and rig. Restrained lateral torso/hip/shoulder fullness; no added leg radial extra. Weights unchanged, closed single component. Earlier full-torso lowering and extra leg volume NOT selected.
- `validation-v9-work.json`: PASS,0 errors/warnings. Rest candidate validation also PASS. Actual squat and push-up at `renders/v9-experiments/restrained/poses/` both visually inspected; reports0 errors/warnings, source unchanged. This does NOT approve deformation: deep knee crease and shoulder/axilla dip remain visible. Static poses reset all pose bases, so evidence applies to the identical-rest-mesh canonical work copy; no animation/self-intersection certificate.

### Explicit new pose protocol — never mix scores with v1

Announced to user that old neutral rules had straight diagonal legs and forward hands/feet inconsistent with approved reference. Added separate `scripts/prepare_turnaround_pose_v2.py`, `calibration/multiview-pose-v2/profiles/` and independent runs/reports. Same fixed rules for every model, no per-model fitting. Reference/camera/studio/material-policy/scoring unchanged; only pose metadata/dependency differs. `multiview_run.py --pose-version v2`; default remainsv1. `setup_pose_v2.py` is initialization-only, refuses existing profiles. Old `prepare_turnaround_pose.py` hash unchanged.44 tests pass including4 new protocol-isolation tests.

V2 rules: upper leg `(±.08,-.075,-1)`, lower `(±.19,.10,-1)`, upperarm13°,forearm18°with forward component−.23, feet outward20°, hands inward30°, fingers6/16/10°. These are approximate reference-led pose rules, not proof of exact pose reconstruction. Hand/palm orientation still needs explicit closeup review before any final claim.

Pose-v2 protocol IDs: front `a8e96f91652a07ca23fe7ce201b3687def99df1fad89bc071afdaed9504f3bdb`, side `119a1a4e95a36207c6ab1da8078d89af6a56bb6b5656316af34f3dd09de20611`, back `bb5754ad9b030cc7dc77214db124a69c4ae65aeb49cb5a75d8736f9555f1f352`.

Same-v2 comparisons, front/side/back:

- V7-baseline:67.73091756 /69.08378420 /65.82483482, mean67.54651219.
- V9-combined (full height/volume):71.10542592 /71.30412167 /70.96185261, mean71.12380007. Not selected: hips−9 points and shins−6/7 vs baseline in front/back bands.
- **V9-restrained selected**:71.44825387 /70.70489174 /71.10357594, mean71.08557385, minimum70.70489174. All front/back height bands improve vsV7 under v2. Side thighs−4.906, shins−1.928, feet−.431 remain explicit local regressions; not hidden by overall gain. Chosen as an unfinished modeling checkpoint, not a final gate pass. Next iteration should target sagittal thigh shape without moving already-improved front/back joints or changing the protocol.

Main reports regenerated separately: `calibration/multiview/report.html` (v1), `calibration/multiview-pose-v2/report.html` (v2). V9 work shared capture hashes: geometry `5d8d512a0836a485eab51babcd9e845a1a641b0e58799e364c5d6c10b08bcd8d`, pose `c6b170bd700079c4275aa26e9206cd38f62f54a8c495f776263a337702b90471`, material `3a7f5b8112496c3dc2eaa20be5248eb4e09eb5e01617a6104c7b40150c64196f`.

### Rejected/retained experiments — don't accidentally promote them

- `measure_head_sections_v8.py` → `v8-head-sections.json`: measured front/back width and side contours, reference/capture hashes retained; no image editing. V8 `sections` head-full andhead60 genuinely improved some silhouette scores but produced horizontal facial/neck ripples and broad shelf-like projections. **Rejected after actual closeups**, despite v1 mean70.34010 /69.88734.
- V8 `anatomical`: smooth local anterior chin push produced a beak-like lower face; rejected despite v1 mean69.70855. `lowered-jaw` instead extends lower face downward without anterior push; selected only as component. v1 mean69.52163.
- V9-proportions (full height, no added widths) v1 mean69.61375; V9-volume mean70.75156; V9-combined mean71.32202. Old-pose bands revealed hip/leg regressions. No v9-work alias was made from these. All images/models preserved.

### Next useful work

1. Read current V9 actual views and v2 regional report; repair side thigh curvature/volume locally, preserving improved front/back contours. Do not revisit rejected global face-ring expansion or full pelvis lowering.
2. Hands still look stiff and palm/thumb orientation may not match the reference; inspect actual hand closeups and bone axes before changing. Current pose v2 is fixed for comparisons. Any further sampling-pose revision must be explicit with baseline recapture, not a silent patch.
3. Shoulder width and limb proportions still differ; shoulder-center differences are roughly8–10 canonical pixels in earlier v1 evidence, wrist offsets about10–14px. Distinguish skeletal width, local volume and pose before editing. Do not fabricate 99% from approximate joint annotations.
4. Actual knees/axillae still have poor deep flexion deformation. Preserve-volume is already enabled; prior generic corrective smoothing did not solve them. Local skin-weight/corrective-shape work with intermediate-pose verification remains needed.
5. Face/ears, feet/toes, native material/shading still incomplete. Do not equate the current ~71 agreement index with 71% measured geometric reconstruction, and absolutely do not mark99/complete. Approved reference hash still `0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4`.

---

## Current checkpoint — approved turnaround, V6 and V7 studies

**User explicitly approved the new turnaround: “我认可刚才的三视图”.** This supersedes all older pending-approval notes. The image is locked at SHA256 `0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4`; no regeneration or further approval request is needed. Annotation uncertainty and inferred geometry remain limitations, not an approval blocker.

Goal ACTIVE, not 99, not blocked. Concrete progress: actual posterior head repair, independent three-view protocol and real V7 geometry studies. No iOS changes, no commits, no new agents. **Current selected model: `GreenBody-v7-work.blend`**, SHA256 `6418619612c1fc4aa7bdb2af1033ea9d6009e1ae52d144690a8bda59994c54df`, exact binary copy of `renders/v7-experiments/body/candidate.blend`. The V6 source remains unchanged (SHA256 `1f4c67375a454315b3ec0b19eec4bd9b4634c1d232c99e2160626a7f074bde3b`), exact copy of `renders/v6-experiments/head-fair/candidate.blend`. V6 smooths a visible horizontal posterior head stripe; actual headback renders inspected. Rest-head-only 619 vertices, max displacement 1.2059 mm, weights unchanged. Other V6 joint-smoothing studies not selected. V6 structural validation PASS; both diagnostic pose runs terminal, retained at `renders/v6-work/poses/`.

New independent protocol: `calibration/multiview/README.md`, configs/references/profiles, `calibration/multiview_run.py`, locked `scripts/prepare_turnaround_pose.py`. Source and all per-view geometry/pose/material hashes guarded. Native material, fixed view-relative studio. Three scores, equal mean and minimum; numeric target requires every view >=99 but never automatically approves the model. Old one-view reference/protocol untouched and not numerically comparable. All 40 calibration tests pass.

Baseline V5 front/side/back: 66.12442 / 65.41086 / 65.22673, mean65.58733. Selected V6: 66.12434 / 65.39093 / 65.22617, mean65.58048. V6 selection is visual stripe repair, NOT numeric improvement.

V7 script `scripts/build_green_body_v7.py` modifies actual rest mesh torso width/depth and leg radial volume, optionally foot mesh and corresponding toe/foot bones. Source V6 preserved; topology, normalized weights and head unchanged. All candidates preserve provenance JSON. Study results under `calibration/multiview/captures/`:

- `V7-combined`: body_strength1, foot_strength1; front67.83891 / side61.21928 / back66.98432; mean65.34750. REJECTED for substantial side regression. Actual three views inspected. Do not select because front/back improve. Longer foot changes silhouette alignment as well as actual shape.
- `V7-body`: body_strength1, foot_strength0; front66.99669 / side73.36110 / back66.51454; mean68.95744, minimum66.51454. **SELECTED as V7-work**. All view scores improve vs V6; no height-band regression beyond1 point. Actual three views and selected squat/push-up inspected. `validation-v7-work.json` PASS, no errors/warnings. Both pose reports source unchanged, no errors/warnings, no clipping, support gaps about0.5mm. This is static QA, NOT good-deformation/animation approval: deep knee fold and shoulder/axilla dip remain visible.
- `V7-body150`: body_strength1.5, foot_strength0; front67.22423 / side70.48751 / back67.00969; mean68.24047. Not selected: slightly better front/back but worse side and lower overall mean vs body1; use restrained body1 for current geometry checkpoint.

All tool processes at this checkpoint are terminal (including V7-body150 scoring, V7 structural validation and both V7 pose renders). Main three-view `calibration/multiview/report.html` regenerated with15 view entries. Tests40 pass. Goal remains ACTIVE with real progress; no completion/blocked update called. Detailed handoff: `README-V7-WORK.md`.

Current actual deficiencies: reference has fuller shoulder/chest/waist and legs, more natural facial planes; head/neck and feet still differ, hands/feet pose differs from locked neutral sampler. Fixed-pose scores cannot establish geometric identity. Do not distort geometry to hide a pose mismatch or change protocol without a new baseline. Knee/axilla deformation still needs real corrective work, not a manifold-only claim.

## Historical request: three-view reference (subsequently approved above)

User asked whether the reference should also have front/side/back views for easier comparison. At that earlier checkpoint V5 was the latest model. Approval and subsequent work are recorded above.

Used the imagegen skill (read completely plus prompting guidance). First generation was blocked at output safety stage with no usable image; explicitly fully covered training-mannequin retry succeeded. New candidate: `reference/green-body-turnaround-v1-candidate.png`. Final prompt `reference/turnaround-v1-retry-prompt.txt`; detailed status `reference/turnaround-v1-status.md`. Uses ONLY original concept as input, never current Blender renders. The native generated image was shown inline; workspace copy preserves the output. This is a **new inferred design candidate awaiting user approval**, not measured 3D truth or a locked scoring reference.

Do not replace old reference or scoring contract automatically. New orthographic-like pose is symmetric and differs from the original standing pose. Side/back have inferred anatomy; user must confirm proportion/muscle/volume direction. If approved, add distinct multiview reference protocol and recapture both old and new models. Until then existing single-view protocol stays authoritative for its limited purpose. Can still fix objective current-model defects without using the new sheet as approved ground truth.

Goal remains active and 99% unverified. No new Blender processes or source-model edits in this interrupted continuation. No blocking state asserted.

## Latest checkpoint — V5 work (supersedes the V4 current-work section below)

Goal still **ACTIVE, not achieved**. This turn made concrete model and evaluation progress, not a blocked/no-progress turn. Do not claim 99% or animation readiness.

- Current selected model: `GreenBody-v5-work.blend`, SHA256 `1b69e4928acd5e3852e5d206560988833a394b51835b41f4e0f4aa8c3dd42aad`.
- Exact binary copy of `renders/v5-experiments/foot-study/forearm10-arm5/candidate.blend`.
- Official fixed-protocol repeat: `calibration/runs/20260913T041636662886Z-V5-work/result.json`, score **74.90189717525928**, identical to experiment. Capture `calibration/captures/20260913T041610786983Z-V5-work/`.
- Same protocol as V4. Delta **+1.691555293496961**, greater than sensitivity margin 1.271924520951643. No height band drops >3 points; torso band +7.34447. Color metric -.46752 (do not claim all metrics improved).
- `validation-v5-work.json`: PASS, 0 errors/warnings; scoring tests 31 pass again.
- Actual full views (1000×1200, head1000 square) `renders/v5-work/views/{front,side,back,head}.png` all inspected. Actual squat and push-up `renders/v5-work/poses/` both inspected; reports source unchanged.
- `renders/v5-work/reference-v4-v5.png` arranges unchanged canonical evidence side-by-side.
- Main `calibration/report.html` regenerated. Browser not refreshed or opened in this goal turn.
- `README-V5-WORK.md` contains concise Chinese instructions, evidence, decisions and limitations.
- No iOS edits, no git commits, no delegated agents. V3.1, V4 and reference SHA reconfirmed unchanged.

### Actual V5 changes

`scripts/build_green_body_v5.py` reads V4-work by default, refuses overwrites, retains topology/weights, validates mesh and records provenance. Params `v5-work-parameters.json` are **deltas against V4**, NOT V5. Selected: left arm in5°, left forearm out10°, forearm radial extra.1, axilla anterior fill.008m, nose plane.006m, chin plane.002m. Right arm corrections and foot yaw deltas zero. Surface displacements fade locally; no image or reference edits.

The builder also supports bounded foot yaw experiments (±25°) and re-solves actual foot support only when they are nonzero. These experiments were NOT selected. `scripts/calibrate_v4_batch.py` now accepts `--builder build_green_body_v5.py`; default V4 behavior preserved. Every batch uses the original unchanged collector/evaluator.

### V5 trials and decisions

- `scripts/refine_green_body_v5.py`: raw CC0 face BVH transfer prototype. Reads the original source transforms without the original synthetic blank-face loop; filters bounded displacement onto current closed head. `head50/`, `head90/` real head renders were visually worse (box-like forehead), explicitly rejected and not scored. Decision recorded `renders/v5-experiments/head-transfer-decision.json`. Do NOT resume raw transfer as if it had improved the face.
- `upper-study/` six actual scored candidates; left-in5-out10 best74.65050. Other arm edits worsened. Plane-only ~73.21009, essentially no score gain.
- `upper-fine-study/` six; left5-out10-planes74.65056, left7out12 lower74.02244. Right-arm corrections +/- made score worse. Forearm volume helped slightly, but those early trials were confounded with poorer right-arm pose.
- `foot-study/` four; **selected forearm10-arm5 74.90190** (no right-arm correction, no foot yaw). Near-foot+10° 74.84018; +20°74.54632; bothfeet+10/-10 69.21753.
- `combined/` (forearm+.1 and near-foot+10) scored75.05036, but feet band **-4.46465** vs V4; `hold_for_review`, NOT promoted. Its views/poses/validation retained. Do NOT select this merely because its composite is higher. Selected model retains V4 feet, still a genuine +1.69 overall improvement.
- Total17 scored candidates plus2 rejected head render studies in this turn; selected official recapture separate.

### Next useful work

1. Main remaining visible defects: posterior head horizontal band, abstract/soft face planes and blocky ear; deep-squat shoulder/axilla indentation and sharp knee fold; foot heel and toes remain too block-like/serrated. These were observed in full actual renders, not just inferred from scores.
2. Read-only modifier inspection confirmed ARMATURE `use_deform_preserve_volume=True` already, followed by CORRECTIVE_SMOOTH and SUBSURF. Do NOT propose enabling preserve-volume as an untried fix. Next deformation work should inspect skin weights/local corrective shapes and verify intermediate poses.
3. Head band comes from the V2 loft/profile plus cranial blend; inspect `head_geometry_v2.py` and current rest coordinates before a carefully bounded posterior surface correction. Rejected raw-face transfer must not be promoted. Keep all old sources/models immutable.
4. Feet remain the lowest fixed height band. Pure yaw studies failed the regional guard or had little benefit; prioritize anatomical cross-section/heel/toe geometry and multi-view/pose quality over another total-score-only pose tweak.
5. The native appearance protocol remains available but distinct; fixed material protocol cannot measure a changed native material. Never silently change scoring to inflate the 99% goal.

All tool processes at this checkpoint are terminal; no ongoing renders, tests, or batch sessions remain. Goal active; no completed/blocked update called.

---

## Prior V4 checkpoint (historical baseline, not latest work)

User objective (unchanged): **你修到 99% 再和我说话**.

Status: **ACTIVE, not achieved**. Do not report completion. The 99% requirement remains unproven; a single-view heuristic score is not a certified 3D fidelity percentage. No blocking state has been declared. This goal turn made concrete progress in actual geometry, rig proportions, poses and verified fixed-protocol captures; it is not a no-progress turn.

## Authoritative current work

- Work model: `GreenBody-v4-work.blend`, SHA256 `425cae1018522efb2a6d0d47f58a19f0593c2a46debf6e73cd84b26592583761`.
- Exact binary copy of `renders/v4-experiments/detail-study/restrained-half-thumb30/candidate.blend`.
- Actual re-capture: `calibration/captures/20260913T040155501770Z-V4-work/`.
- Actual repeat score: `calibration/runs/20260913T040208738955Z-V4-work/result.json` = **73.21034188176232**, identical to its original experiment capture.
- Fixed protocol remains `a27899fbaaab3a81843483895ebc7f9e27e151740b8476f89b2362f8e0765d1f`. No changes to reference, camera, material, lights, metric implementation or scoring weights.
- V3.1 baseline 66.26667430203551. Work candidate delta +6.943667579726807; all seven height-band scores increased; no 3-point regional regression.
- Final structural inspection `validation-v4-work.json`: PASS, zero errors and warnings. Scoring suite still 31 tests passing.
- Main local `calibration/report.html` has been regenerated with `V4-work`; browser was not automatically opened/refreshed during this goal turn.
- Old V1/V2/V3/V3.1 retained. V3.1 unchanged SHA256 `2afdb20281ff0a857c0931818a6f0e35fd22566cbb9e025b7220d4cb1ce4ab89`; reference unchanged `a495910b0855d94a9d5679e41362d4f7aaeda724d0800025c7b5b70871f9b3cd`.
- No iOS changes and no newly delegated agents in this goal turn.

## What changed in real 3D

`scripts/build_green_body_v4.py` reads V3.1 by default. `v4-work-parameters.json` stores the chosen deltas against V3.1, NOT against V4-work. Avoid accidentally applying these deltas twice.

- Monotonic rest-space leg-proportion map: ankle-joint lift 35 mm, knee lift 55 mm, tapered to zero at sole and pelvis; applies to the skeleton as well as the mesh. Overall crown height stays unchanged.
- Ankle/instep surface lift attenuated 50% toward the sole, chosen to reduce the overly thick heel of the highest-scoring unconstrained variant.
- 30-degree femoral-axis twist with ankle target retained, foot orientation reconstructed against the updated rest frame. This improves calf/thigh muscle direction without flattening the model.
- Calf and upper-arm radial fullness +8% and +10% locally (linear radial scale, not volumetric percentages).
- Additional torso yaw 5 degrees; additional small nasal projection 4 mm; thumb direction relaxed 30% toward the hand's longitudinal direction.
- Standing support re-solved against the actual evaluated soles and floor. All mesh topology and normalized vertex weights retained.

Builder bounds and contact assertions were added after the selected experiment; these do not change geometry. Metadata was clarified to distinguish the skeletal/body map from the foot-surface attenuation. The source model copy retains its experiment provenance; a future rebuild should record the new builder hash.

## Evidence checked

Selected experiment `renders/v4-experiments/detail-study/restrained-half-thumb30/`:

- `capture/beauty.png`, mask, fixed-protocol result.
- `views/front.png`, `side.png`, `back.png`, `head.png`: real Blender renders. Main agent visually inspected hero, side, head/other source views during this iteration; see remaining concerns below.
- `poses/squat.png`, `push-up.png`, both saved pose models and individual JSON reports. Main agent inspected deep squat; preceding upper10-yaw5 variant's push-up and squat were also rendered/checked. Both selected pose reports have zero structural errors and source SHA unchanged.
- Selected squat foot gaps ~0.500 mm; push-up hands ~0.500–0.503 mm and feet ~0.505 mm. Source copied to V4-work has identical SHA, so these pose evidence files apply to the same mesh and rig.

Art concerns remain: foot/heel still somewhat block-like and toes need clearer rounded forms; head is still too abstract/soft versus the reference, especially nose/jaw/ear; central chest/armpit is still pinched; deep-squat near knee has an inherited sharp fold. These preclude any 99% or animation-ready claim.

## Experiments retained (all terminal, no processes left running at checkpoint)

`scripts/calibrate_v4_batch.py` runs actual build → unchanged collector → unchanged evaluator. It requires a new output directory, retains every success/failure and does not auto-promote.

- `lower-study/`: 6 candidates. Best index 71.484 (`lift35-knee55-twist30`). Rest knee position now close to the reference; ankle points still ~15 px low, but reference joint semantics are uncertain—do not blindly force them.
- `upper-study/`: 6 candidates. Best index 73.301 (`upper10-yaw5`). Yaw 10° worsens silhouette; additional upper-arm 20% not better than 10%.
- `foot-study/`: 6 candidates. Increasing near-foot yaw to -50/-60° and widening toes hurts alignment and gives larger/blockier feet. Do not adopt these just because they were rendered. The foreground-bbox normalization couples footprint and apparent whole-body offset.
- `detail-study/`: 6 candidates. Highest score 73.608 (`thumb30-only`) has thicker heel. Selected `restrained-half-thumb30` scores 73.210; difference is within mask sensitivity, and the moderated foot surface is preferable. Full instep restraint scores72.920. Thumb50 is not clearly better than30.
- `proportions-a` was an early study that reused old local foot quaternions after rest-frame edits; this introduced extra pitch/roll. It is rejected. `orient_feet` corrects this in later studies.

## Next useful work, preserving the full objective

1. Read the current work model, latest result and actual reference again; use the above as locations, not as a replacement for inspection.
2. Remaining high-error regions are feet/torso and appearance. Refine actual foot anatomical cross-sections (heel/instep/toe volume) rather than just making the foot taller or changing score normalization.
3. Head needs clearer human planes, not additional indiscriminate smoothing. Consider transferring restrained surface structure from the CC0 source head onto the existing closed head topology; the existing `read_source()` function already overwrites its original facial surface, so inspect raw source loading if using it. Keep nose/jaw shallow, remove the back-head band and improve the ear shell.
4. For more systematic shape fitting, use anatomical 3D parameters or smooth cross-section cages with multi-view regularization. Do not warp final images, use a camera-facing billboard, or flatten the body to win a silhouette score.
5. Continue real fixed-protocol captures and multi-view/pose checks. If evaluating native material/light fidelity later, retain this geometry protocol and use a separately identified appearance protocol with baseline re-rendering; never quietly replace the existing scoring contract.
6. The user asked not to receive routine milestone delivery messages until99. Keep the goal active; developer-required progress messages should be brief. Do not call update_goal complete or blocked now: 99 is unverified, and meaningful in-scope work remains.
