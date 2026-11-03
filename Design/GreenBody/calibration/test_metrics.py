"""Run: python3 -m unittest discover -s Design/GreenBody/calibration -p 'test_metrics.py'."""

import copy
import json
import unittest

import numpy as np

from metrics import _boundary, evaluate


class AgreementTests(unittest.TestCase):
    def setUp(self):
        self.mask = np.zeros((160, 120), dtype=bool)
        self.mask[10:28, 52:68] = True
        self.mask[28:37, 57:63] = True
        self.mask[37:77, 42:78] = True
        self.mask[43:87, 31:39] = True
        self.mask[43:87, 81:89] = True
        self.mask[77:90, 43:77] = True
        self.mask[90:145, 44:55] = True
        self.mask[90:145, 65:76] = True
        self.mask[145:150, 40:55] = True
        self.mask[145:150, 65:83] = True
        self.rgb = np.zeros((160, 120, 3), dtype=np.uint8)
        self.rgb[self.mask] = [150, 210, 30]
        self.points = {
            "left_shoulder": {"xy": [43, 40], "weight": 1, "uncertainty_px": 0.5},
            "right_shoulder": {"xy": [77, 40], "weight": 2, "uncertainty_px": 0.5},
            "left_ankle": {"xy": [49, 144], "weight": 1, "uncertainty_px": 0.5},
            "right_ankle": {"xy": [70, 144], "weight": 1, "uncertainty_px": 0.5},
        }
        self.config = {"body_height": 140, "body_top_y": 10, "body_center_x": 60,
                       "boundary_tolerance_px": 1}

    def run_score(self, rgb=None, mask=None, points=None):
        return evaluate(self.rgb, self.rgb if rgb is None else rgb,
                        self.mask, self.mask if mask is None else mask,
                        self.points, self.points if points is None else points, self.config)

    def assert_json_finite(self, result):
        json.dumps(result, allow_nan=False)
        self.assertTrue(0 <= result["composite_score"] <= 100)
        for metric in result["metrics"].values():
            self.assertTrue(0 <= metric["score"] <= 100)

    def test_identity_is_100_and_complete(self):
        result = self.run_score()
        self.assertAlmostEqual(result["composite_score"], 100)
        self.assertEqual(result["score_status"], "complete")
        for metric in result["metrics"].values():
            self.assertAlmostEqual(metric["score"], 100)
        for region in result["regional_results"].values():
            self.assertAlmostEqual(region["score"], 100)
        self.assert_json_finite(result)

    def test_translation_is_not_auto_registered_away(self):
        mask = np.zeros_like(self.mask)
        rgb = np.zeros_like(self.rgb)
        mask[:, 8:] = self.mask[:, :-8]
        rgb[:, 8:] = self.rgb[:, :-8]
        points = copy.deepcopy(self.points)
        for value in points.values():
            value["xy"][0] += 8
        result = self.run_score(rgb, mask, points)
        for key in ("silhouette_iou", "boundary_f1", "width_profile", "landmarks"):
            self.assertLess(result["metrics"][key]["score"], 99)
        self.assertLess(result["metrics"]["color"]["score"], 100)

    def test_horizontal_compression_penalizes_width(self):
        xs = np.rint((np.arange(120) - 60) / 0.8 + 60).astype(int)
        valid = (xs >= 0) & (xs < 120)
        mask, rgb = np.zeros_like(self.mask), np.zeros_like(self.rgb)
        mask[:, valid] = self.mask[:, xs[valid]]
        rgb[:, valid] = self.rgb[:, xs[valid]]
        result = self.run_score(rgb, mask)
        self.assertLess(result["metrics"]["width_profile"]["score"], 95)
        self.assertLess(result["metrics"]["silhouette_iou"]["score"], 95)

    def test_local_head_change_is_local_and_sides_stay_distinct(self):
        mask = self.mask.copy()
        mask[10:28, 45:52] = True
        rgb = self.rgb.copy()
        rgb[mask] = [150, 210, 30]
        result = self.run_score(rgb, mask)
        regions = result["regional_results"]
        self.assertLess(regions["head"]["left"]["score"], 90)
        self.assertAlmostEqual(regions["head"]["right"]["score"], 100)
        self.assertAlmostEqual(regions["shins"]["score"], 100)

    def test_recolor_changes_appearance_not_geometry(self):
        rgb = self.rgb.copy()
        rgb[self.mask] = [30, 70, 210]
        result = self.run_score(rgb=rgb)
        self.assertLess(result["metrics"]["color"]["score"], 10)
        self.assertAlmostEqual(result["metrics"]["silhouette_iou"]["score"], 100)
        self.assertAlmostEqual(result["metrics"]["landmarks"]["score"], 100)

    def test_background_does_not_change_appearance(self):
        rgb = self.rgb.copy()
        rgb[~self.mask] = [255, 255, 255]
        result = self.run_score(rgb=rgb)
        self.assertAlmostEqual(result["metrics"]["color"]["score"], 100)
        self.assertAlmostEqual(result["metrics"]["shading"]["score"], 100)

    def test_spatial_shading_is_measured_separately(self):
        rgb = self.rgb.copy()
        rgb[20:80][self.mask[20:80]] = [100, 145, 20]
        result = self.run_score(rgb=rgb)
        self.assertLess(result["metrics"]["shading"]["score"], 90)

    def test_missing_points_have_fixed_weight_denominator(self):
        points = copy.deepcopy(self.points)
        del points["right_shoulder"]
        result = self.run_score(points=points)
        self.assertAlmostEqual(result["landmark_coverage"], 3 / 5)
        self.assertAlmostEqual(result["metrics"]["landmarks"]["score"], 60)
        self.assertAlmostEqual(result["composite_score"], 94)
        self.assertNotEqual(result["score_status"], "complete")
        self.assertEqual(result["landmark_errors"]["right_shoulder"]["status"], "missing")

    def test_candidate_cannot_hide_error_with_weight_or_uncertainty(self):
        points = copy.deepcopy(self.points)
        points["right_shoulder"]["xy"][0] += 10
        before = self.run_score(points=points)["metrics"]["landmarks"]["score"]
        points["right_shoulder"].update(weight=0, uncertainty_px=1000000)
        after = self.run_score(points=points)["metrics"]["landmarks"]["score"]
        self.assertEqual(before, after)

    def test_no_points_is_incomplete_not_perfect(self):
        result = self.run_score(points={})
        self.assertEqual(result["landmark_coverage"], 0)
        self.assertEqual(result["metrics"]["landmarks"]["score"], 0)

    def test_empty_masks_never_score_high(self):
        empty = np.zeros_like(self.mask)
        for rm, cm in ((empty, empty), (self.mask, empty), (empty, self.mask)):
            result = evaluate(self.rgb, self.rgb, rm, cm, self.points, self.points, self.config)
            self.assertEqual(result["composite_score"], 0)
            self.assertEqual(result["score_status"], "invalid_input")
            self.assert_json_finite(result)

    def test_no_overlap_zeroes_appearance(self):
        mask = np.zeros_like(self.mask)
        mask[10:150, :5] = True
        rgb = np.zeros_like(self.rgb)
        rgb[mask] = [150, 210, 30]
        result = self.run_score(rgb, mask)
        self.assertEqual(result["metrics"]["color"]["score"], 0)
        self.assertEqual(result["metrics"]["shading"]["score"], 0)
        self.assertLess(result["composite_score"], 40)

    def test_nan_image_and_mask_are_safe_invalid(self):
        rgb = self.rgb.astype(float)
        rgb[0, 0, 0] = np.nan
        mask = self.mask.astype(float)
        mask[0, 0] = np.inf
        for kwargs in ({"rgb": rgb}, {"mask": mask}):
            result = self.run_score(**kwargs)
            self.assertEqual(result["composite_score"], 0)
            self.assert_json_finite(result)

    def test_nan_landmark_is_zero_penalized_not_json_nan(self):
        points = copy.deepcopy(self.points)
        points["right_shoulder"]["xy"][0] = float("nan")
        result = self.run_score(points=points)
        self.assertAlmostEqual(result["metrics"]["landmarks"]["score"], 60)
        self.assertEqual(result["landmark_errors"]["right_shoulder"]["status"], "invalid")
        self.assert_json_finite(result)

    def test_boundary_neighborhood_does_not_wrap_rows(self):
        mask = np.ones((4, 5), dtype=bool)
        boundary = _boundary(mask)
        self.assertTrue(boundary[:, 0].all())
        self.assertTrue(boundary[:, -1].all())
        self.assertFalse(boundary[1:3, 1:4].any())
        rm, cm = np.zeros((4, 5), bool), np.zeros((4, 5), bool)
        rm[1, 4], cm[2, 0] = True, True  # Adjacent in flattened memory, not 2D.
        rgb = np.zeros((4, 5, 3), np.uint8)
        result = evaluate(rgb, rgb, rm, cm, {}, {},
                          {"body_height": 2, "boundary_tolerance_px": 1})
        self.assertEqual(result["metrics"]["boundary_f1"]["score"], 0)

    def test_results_are_deterministic(self):
        self.assertEqual(json.dumps(self.run_score(), sort_keys=True),
                         json.dumps(self.run_score(), sort_keys=True))


if __name__ == "__main__":
    unittest.main()
