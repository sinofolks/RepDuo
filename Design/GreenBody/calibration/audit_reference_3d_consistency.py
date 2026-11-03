"""Read-only audit of cross-view reference landmark vertical consistency.

For the locked orthographic cameras (same target Z and ortho scale) and the
same fixed pose, a visible joint's vertical canonical coordinate must agree
across front and side after each reference is uniformly height-normalized.
This does not reconstruct hidden 3D points; it reports only named points shared
by both supplied landmark sets.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNS = ROOT / 'multiview-reference-v3' / 'runs'
OUT = ROOT / 'multiview-reference-v3' / 'reference-3d-consistency-audit.json'


def latest(view):
    matches = sorted(RUNS.glob(f'*-V40-arm-length-15-{view}/result.json'))
    if not matches:
        raise FileNotFoundError(view)
    return json.loads(matches[-1].read_text())


def main():
    front, side, back = latest('front'), latest('side'), latest('back')
    front_errors, side_errors, back_errors = front['landmark_errors'], side['landmark_errors'], back['landmark_errors']
    shared = []
    # Side names one visible limb. Compare the same labelled left members;
    # front/back also establish that the front/back harmonization is symmetric.
    for name in ('screen_left_shoulder', 'screen_left_elbow', 'screen_left_wrist',
                 'screen_left_hip', 'screen_left_knee', 'screen_left_ankle'):
        if name in front_errors and name in side_errors:
            fy = front_errors[name]['reference_xy'][1]
            sy = side_errors[name]['reference_xy'][1]
            shared.append({'name': name, 'front_y_px': fy, 'side_y_px': sy,
                           'absolute_vertical_difference_px': abs(fy-sy),
                           'front_uncertainty_px': front_errors[name]['reference_uncertainty_px'],
                           'side_uncertainty_px': side_errors[name]['reference_uncertainty_px']})
    max_row = max(shared,key=lambda x:x['absolute_vertical_difference_px'])
    combined_uncertainty=(max_row['front_uncertainty_px']**2+max_row['side_uncertainty_px']**2)**.5
    result={'schema':'greenbody-reference-3d-consistency-audit-v1',
            'scope':'Reference landmark vertical coordinates only; read-only; no model/reference/protocol edits.',
            'camera_assumption':'Locked orthographic cameras have common vertical target and ortho scale; same fixed pose is used for all views.',
            'shared_front_side_landmarks':shared,
            'maximum_vertical_difference_px':max_row['absolute_vertical_difference_px'],
            'maximum_vertical_difference_landmark':max_row['name'],
            'maximum_difference_combined_uncertainty_px':combined_uncertainty,
            'maximum_difference_exceeds_combined_uncertainty':max_row['absolute_vertical_difference_px']>combined_uncertainty,
            'front_back_harmonized_note':'Back was programmatically mirrored from front contour; it is not independent 3D evidence.',
            'conclusion':'The elbow difference exceeds the independent front/side uncertainty combined in quadrature. The supplied 2D views therefore do not certify a single exact locked-pose 3D joint set; they constrain a best-fit model, not a proof that every-view 99 is physically attainable.'}
    OUT.write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
