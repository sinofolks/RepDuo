"""Deterministic, view-specific reference agreement; not 3D/material truth.

Inputs must already share one fixed camera/canvas alignment. No registration,
resizing, or per-candidate recentering is performed here. Scores are bounded
0..100. Their weighted composite is an engineering agreement index, NOT a
percentage of geometric reconstruction accuracy. Height bands are not semantic
body-part segmentation: an arm can overlap the torso-height band.
"""

from collections.abc import Mapping
import math

import numpy as np
from scipy import ndimage


METRIC_WEIGHTS = {
    "silhouette_iou": 30.0,
    "boundary_f1": 20.0,
    "width_profile": 20.0,
    "landmarks": 15.0,
    "color": 10.0,
    "shading": 5.0,
}
DESCRIPTIONS = {
    "silhouette_iou": "Foreground intersection / union on the fixed canvas.",
    "boundary_f1": "Symmetric 2D boundary precision/recall within a fixed pixel tolerance.",
    "width_profile": "Equal-weight fixed height bands; left/right outline extent and occupied row width.",
    "landmarks": "Reference-weighted point agreement; missing/invalid candidates score zero without renormalization.",
    "color": "Overlap-gated Lab mean/distribution agreement of the rendered appearance, not material truth.",
    "shading": "Overlap-gated coarse spatial L* contrast agreement, not recovered lighting or material truth.",
}
BANDS = (
    ("head", 0.0, 0.15), ("shoulders", 0.15, 0.27),
    ("torso", 0.27, 0.46), ("hips", 0.46, 0.59),
    ("thighs", 0.59, 0.75), ("shins", 0.75, 0.94),
    ("feet", 0.94, 1.0),
)


def _number(value, default, minimum=0.0):
    try:
        value = float(value)
        return value if math.isfinite(value) and value >= minimum else default
    except (TypeError, ValueError):
        return default


def _score_error(error, scale):
    return float(100.0 * math.exp(-float(error) / float(scale)))


def _boundary(mask):
    # Genuine 2D neighborhoods with constant outside=False: never flatten/roll.
    return mask & ~ndimage.binary_erosion(
        mask, structure=np.ones((3, 3), dtype=bool), border_value=0)


def _boundary_result(reference, candidate, tolerance):
    rb, cb = _boundary(reference), _boundary(candidate)
    nr, nc = int(rb.sum()), int(cb.sum())
    if not nr or not nc:
        return {"f1": 0.0, "precision": 0.0, "recall": 0.0,
                "tolerance_px": tolerance, "reference_boundary_pixels": nr,
                "candidate_boundary_pixels": nc}
    precision = float((ndimage.distance_transform_edt(~rb)[cb] <= tolerance).mean())
    recall = float((ndimage.distance_transform_edt(~cb)[rb] <= tolerance).mean())
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"f1": f1, "precision": precision, "recall": recall,
            "tolerance_px": tolerance, "reference_boundary_pixels": nr,
            "candidate_boundary_pixels": nc}


def _iou(reference, candidate):
    union = int(np.count_nonzero(reference | candidate))
    return float(np.count_nonzero(reference & candidate) / union) if union else 0.0


def _row_profiles(mask, side, center):
    xs = np.arange(mask.shape[1], dtype=float)
    side_columns = xs < center if side == "left" else xs >= center
    selected = mask & side_columns[None, :]
    distance = np.abs(xs - center) + 0.5
    extent = np.max(np.where(selected, distance[None, :], 0.0), axis=1)
    return extent, selected.sum(axis=1).astype(float), selected


def _width_results(reference, candidate, top, height, center, scale):
    results, scores = {}, []
    for name, start, end in BANDS:
        lo = max(0, min(reference.shape[0], int(round(top + start * height))))
        hi = max(lo, min(reference.shape[0], int(round(top + end * height))))
        region = {"normalized_height_range": [start, end], "row_range": [lo, hi],
                  "is_height_band_not_anatomical_segmentation": True}
        side_scores = []
        for side in ("left", "right"):
            re, ro, rm = _row_profiles(reference[lo:hi], side, center)
            ce, co, cm = _row_profiles(candidate[lo:hi], side, center)
            if hi > lo:
                extent_error = float(np.abs(re - ce).mean())
                occupancy_error = float(np.abs(ro - co).mean())
                score = _score_error((extent_error + occupancy_error) / 2, scale)
            else:
                extent_error = occupancy_error = None
                score = 0.0
            region[side] = {
                "score": score,
                "outline_extent_mae_px": extent_error,
                "occupied_width_mae_px": occupancy_error,
                "reference_mean_extent_px": float(re.mean()) if len(re) else None,
                "candidate_mean_extent_px": float(ce.mean()) if len(ce) else None,
                "reference_mean_occupied_width_px": float(ro.mean()) if len(ro) else None,
                "candidate_mean_occupied_width_px": float(co.mean()) if len(co) else None,
                "reference_area_px": int(rm.sum()), "candidate_area_px": int(cm.sum()),
                "silhouette_iou": _iou(rm, cm),
            }
            side_scores.append(score)
        region["score"] = float(np.mean(side_scores))
        region["silhouette_iou"] = _iou(reference[lo:hi], candidate[lo:hi])
        results[name] = region
        scores.append(region["score"])
    return float(np.mean(scores)), results


def _point(entry):
    if not isinstance(entry, Mapping):
        return None
    try:
        point = np.asarray(entry.get("xy"), dtype=float)
    except (TypeError, ValueError):
        return None
    return point if point.shape == (2,) and np.isfinite(point).all() else None


def _landmark_results(reference, candidate, config, height, shape):
    reference = reference if isinstance(reference, Mapping) else {}
    candidate = candidate if isinstance(candidate, Mapping) else {}
    required = config.get("required_landmark_names", list(reference))
    required = list(dict.fromkeys(required))
    scale = _number(config.get("landmark_error_scale_px"), 0.05 * height, 1e-9)
    total_weight = valid_weight = weighted_score = 0.0
    details, valid_errors, missing, invalid = {}, [], [], []
    for name in required:
        r = reference.get(name, {})
        c = candidate.get(name, {})
        weight = _number(r.get("weight") if isinstance(r, Mapping) else None, 1.0, 1e-9)
        total_weight += weight
        rp, cp = _point(r), _point(c)
        # Only trusted reference uncertainty relaxes a score. A candidate cannot
        # award itself a better score by declaring a huge uncertainty or weight.
        uncertainty = _number(r.get("uncertainty_px") if isinstance(r, Mapping) else None, 0.0)
        state, error, effective, score = "valid", None, None, 0.0
        if rp is None or cp is None:
            state = "missing" if name not in candidate else "invalid"
        elif not all(0 <= p[0] < shape[1] and 0 <= p[1] < shape[0] for p in (rp, cp)):
            state = "invalid"
        if state == "valid":
            error = float(np.linalg.norm(rp - cp))
            effective = max(0.0, error - uncertainty)
            score = _score_error(effective, scale)
            valid_weight += weight
            valid_errors.append(error)
        elif state == "missing":
            missing.append(name)
        else:
            invalid.append(name)
        weighted_score += weight * score
        details[name] = {"status": state, "score": score, "weight": weight,
                         "reference_xy": rp.tolist() if rp is not None else None,
                         "candidate_xy": cp.tolist() if cp is not None else None,
                         "distance_px": error, "effective_distance_px": effective,
                         "reference_uncertainty_px": uncertainty}
    coverage = valid_weight / total_weight if total_weight else 0.0
    raw = {"coverage": coverage, "required_count": len(required),
           "valid_count": len(valid_errors), "missing": missing, "invalid": invalid,
           "weighted_denominator": total_weight, "error_scale_px": scale,
           "mean_valid_error_px": float(np.mean(valid_errors)) if valid_errors else None,
           "max_valid_error_px": max(valid_errors) if valid_errors else None,
           "missing_policy": "zero_score_fixed_reference_denominator"}
    score = weighted_score / total_weight if total_weight else 0.0
    return score, raw, details


def _lab(rgb):
    rgb = np.asarray(rgb, dtype=np.float64) / 255.0
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    xyz = linear @ np.array([[0.4124564, 0.3575761, 0.1804375],
                             [0.2126729, 0.7151522, 0.0721750],
                             [0.0193339, 0.1191920, 0.9503041]]).T
    xyz /= np.array([0.95047, 1.0, 1.08883])
    delta = 6 / 29
    f = np.where(xyz > delta ** 3, np.cbrt(xyz), xyz / (3 * delta ** 2) + 4 / 29)
    return np.stack((116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])), axis=-1)


def _appearance(reference_rgb, candidate_rgb, reference_mask, candidate_mask, config, height):
    overlap = reference_mask & candidate_mask
    overlap_count = int(overlap.sum())
    coverage = overlap_count / max(int(reference_mask.sum()), int(candidate_mask.sum()), 1)
    if not overlap_count:
        return (0.0, {"overlap_coverage": 0.0, "delta_e_mean": None, "delta_e_quantiles": None},
                0.0, {"overlap_coverage": 0.0, "spatial_lstar_mae": None})
    rl, cl = _lab(reference_rgb), _lab(candidate_rgb)
    rvalues, cvalues = rl[overlap], cl[overlap]
    delta_mean = float(np.linalg.norm(rvalues.mean(axis=0) - cvalues.mean(axis=0)))
    quantiles = [0.1, 0.25, 0.5, 0.75, 0.9]
    delta_distribution = float(np.linalg.norm(
        np.quantile(rvalues, quantiles, axis=0) - np.quantile(cvalues, quantiles, axis=0), axis=1).mean())
    color_scale = _number(config.get("color_delta_e_scale"), 20.0, 1e-9)
    color_score = coverage * _score_error((delta_mean + delta_distribution) / 2, color_scale)
    color_raw = {"overlap_coverage": coverage, "overlap_pixels": overlap_count,
                 "delta_e_mean": delta_mean, "delta_e_quantiles": delta_distribution,
                 "reference_mean_lab": rvalues.mean(axis=0).tolist(),
                 "candidate_mean_lab": cvalues.mean(axis=0).tolist(),
                 "delta_e_scale": color_scale}
    sigma = _number(config.get("shading_sigma_px"), 0.025 * height, 1e-9)
    shading_scale = _number(config.get("shading_lstar_scale"), 10.0, 1e-9)
    weights = ndimage.gaussian_filter(overlap.astype(float), sigma, mode="constant")
    smooth = []
    for lab in (rl, cl):
        field = ndimage.gaussian_filter(lab[..., 0] * overlap, sigma, mode="constant")
        field = field / np.maximum(weights, 1e-12)
        # Global brightness/color are already covered by Lab. This term isolates
        # coarse spatial contrast; background pixels never enter the convolution.
        values = field[overlap]
        smooth.append(values - values.mean())
    shading_error = float(np.abs(smooth[0] - smooth[1]).mean())
    shading_raw = {"overlap_coverage": coverage, "spatial_lstar_mae": shading_error,
                   "sigma_px": sigma, "lstar_scale": shading_scale,
                   "global_mean_removed": True}
    return color_score, color_raw, coverage * _score_error(shading_error, shading_scale), shading_raw


def evaluate(reference_rgb, candidate_rgb, reference_mask, candidate_mask,
             reference_landmarks, candidate_landmarks, config=None):
    """Return a JSON-safe report; invalid image/mask inputs return zero scores.

    Config keys: body_height (720), body_top_y (reference-mask top),
    body_center_x (reference bounding-box center), boundary_tolerance_px (.005H),
    width_error_scale_px (.025H), landmark_error_scale_px (.05H),
    color_delta_e_scale (20), shading_sigma_px (.025H), shading_lstar_scale (10),
    required_landmark_names (reference keys), weights (known metric keys only).
    Thresholds are exponential e-folding scales, not declarations of accuracy.
    """
    config = dict(config or {})
    warnings = []
    weights = dict(METRIC_WEIGHTS)
    for name, value in config.get("weights", {}).items():
        if name in weights:
            weights[name] = _number(value, weights[name], 0.0)
    if not sum(weights.values()):
        weights = dict(METRIC_WEIGHTS)
        warnings.append("All supplied weights were zero; default weights restored.")
    report = {"schema_version": 1, "score_kind": "fixed_view_reference_agreement_index",
              "score_status": "invalid_input", "composite_score": 0.0,
              "landmark_coverage": 0.0, "metrics": {
                  name: {"score": 0.0, "raw": None, "weight": weights[name],
                         "description": DESCRIPTIONS[name]} for name in weights},
              "regional_results": {}, "landmark_errors": {}, "warnings": warnings}
    try:
        rr, cr = np.asarray(reference_rgb), np.asarray(candidate_rgb)
        rm, cm = np.asarray(reference_mask), np.asarray(candidate_mask)
        if rr.ndim != 3 or rr.shape[-1] != 3 or rr.shape != cr.shape or min(rr.shape[:2]) < 1:
            raise ValueError("RGB images must have identical nonempty H x W x 3 shapes.")
        if rm.shape != rr.shape[:2] or cm.shape != rm.shape:
            raise ValueError("Masks must match both image dimensions.")
        for array in (rr, cr, rm, cm):
            if not np.isfinite(array).all():
                raise ValueError("NaN/Inf image or mask values are invalid.")
        if rr.min() < 0 or cr.min() < 0 or rr.max() > 255 or cr.max() > 255:
            raise ValueError("RGB values must be in [0, 255].")
        rm, cm = rm.astype(bool), cm.astype(bool)
        if not rm.any() or not cm.any():
            raise ValueError("Both masks must contain foreground; empty masks never earn agreement.")
    except (TypeError, ValueError) as exc:
        warnings.append(str(exc))
        return report
    height = _number(config.get("body_height"), 720.0, 1e-9)
    ys, xs = np.nonzero(rm)
    top = _number(config.get("body_top_y"), float(ys.min()), 0.0)
    center = _number(config.get("body_center_x"), float((xs.min() + xs.max()) / 2), 0.0)
    tolerance = _number(config.get("boundary_tolerance_px"), 0.005 * height, 0.0)
    width_scale = _number(config.get("width_error_scale_px"), 0.025 * height, 1e-9)
    if top + height > rm.shape[0] or center >= rm.shape[1]:
        warnings.append("Configured body frame exceeds the canvas; check normalization before comparing scores.")
    silhouette = _iou(rm, cm)
    boundary = _boundary_result(rm, cm, tolerance)
    width_score, regions = _width_results(rm, cm, top, height, center, width_scale)
    landmark_score, landmark_raw, errors = _landmark_results(
        reference_landmarks, candidate_landmarks, config, height, rm.shape)
    color_score, color_raw, shading_score, shading_raw = _appearance(rr, cr, rm, cm, config, height)
    values = {
        "silhouette_iou": (silhouette * 100, {"iou": silhouette, "intersection_pixels": int((rm & cm).sum()),
                                               "union_pixels": int((rm | cm).sum())}),
        "boundary_f1": (100 * boundary["f1"], boundary),
        "width_profile": (width_score, {"error_scale_px": width_scale,
                                        "equal_weight_regions": [b[0] for b in BANDS]}),
        "landmarks": (landmark_score, landmark_raw),
        "color": (color_score, color_raw), "shading": (shading_score, shading_raw),
    }
    for name, (score, raw) in values.items():
        report["metrics"][name].update(score=float(np.clip(score, 0.0, 100.0)), raw=raw)
    coverage = landmark_raw["coverage"]
    report.update(composite_score=float(sum(weights[k] * report["metrics"][k]["score"] for k in weights)
                                        / sum(weights.values())),
                  score_status="complete" if coverage == 1.0 else "incomplete_landmarks_zero_penalized",
                  regional_results=regions, landmark_errors=errors, landmark_coverage=coverage,
                  body_frame={"height_px": height, "top_y": top, "center_x": center})
    if coverage < 1:
        warnings.append("Landmark coverage is incomplete. Missing/invalid points contribute zero with fixed reference weights; this is not a complete-evidence score.")
    if not (rm & cm).any():
        warnings.append("No foreground overlap; color and shading scores are zero.")
    return report
