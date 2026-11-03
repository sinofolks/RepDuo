"""Contract tests for normalization, input integrity and regression comparison."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from calibrate import (compare_runs, digest, incomplete_status, largest_component,
                       mask_check, normalize, save_png, verify_capture, write_json)


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.mask = np.zeros((200, 100), dtype=bool)
        self.mask[20:180, 35:65] = True
        self.rgb = np.zeros((200, 100, 3), dtype=np.uint8)
        self.rgb[self.mask] = (100, 200, 30)
        self.settings = {"width": 480, "height": 800, "body_height": 720, "top": 40}

    def test_uniform_transform_and_landmarks(self):
        _, mask, points, transform = normalize(self.rgb, self.mask, {"a": {"xy": [50, 100]}}, self.settings)
        self.assertEqual(transform["scale"], 4.5)
        self.assertEqual(points["a"]["xy"], [240, 400])
        self.assertEqual(mask.sum(), 135*720)
        self.assertFalse(transform["nonuniform_warp"])
        self.assertEqual(transform["rotation"], 0)

    def test_fringe_and_floor_not_in_rgb(self):
        bright = self.rgb.copy()
        bright[~self.mask] = 255
        rgb, mask, _, _ = normalize(bright, self.mask, {}, self.settings)
        self.assertTrue((rgb[~mask] == 0).all())

    def test_clipped_mask_rejected(self):
        mask = self.mask.copy()
        mask[:, 50] = True
        with self.assertRaises(ValueError):
            mask_check(mask)

    def test_empty_mask_rejected(self):
        with self.assertRaises(ValueError):
            mask_check(np.zeros_like(self.mask))

    def test_outside_points_become_missing(self):
        _, _, points, _ = normalize(self.rgb, self.mask, {"a": {"pixel_x": 50, "pixel_y": 100, "in_frame": False}}, self.settings)
        self.assertNotIn("a", points)

    def test_connected_components_never_wrap(self):
        mask = np.zeros((5, 5), dtype=bool)
        mask[1, 4] = True
        mask[2:4, 0] = True
        self.assertEqual(largest_component(mask).sum(), 2)

    def test_source_arrays_not_mutated(self):
        rgb, mask = self.rgb.copy(), self.mask.copy()
        normalize(rgb, mask, {}, self.settings)
        np.testing.assert_array_equal(rgb, self.rgb)
        np.testing.assert_array_equal(mask, self.mask)

    def test_capture_tamper_detected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("beauty.png", "mask.png"):
                save_png(directory / name, self.rgb, "synthetic test")
            cap = {"status": "complete", "source_unchanged": True,
                   "source_blend_sha256_before": "x", "source_blend_sha256_after": "x",
                   **{k: "x" for k in ("effective_profile_sha256", "collector_sha256", "lighting_hash", "material_hash", "track")},
                   "outputs": {n: {"sha256": digest(directory / n)} for n in ("beauty.png", "mask.png")}}
            verify_capture(directory, cap)
            save_png(directory / "beauty.png", self.rgb+1, "changed")
            with self.assertRaises(ValueError):
                verify_capture(directory, cap)

    def test_status_prefixes(self):
        self.assertTrue(incomplete_status("invalid_input"))
        self.assertTrue(incomplete_status("incomplete_landmarks_zero_penalized"))
        self.assertFalse(incomplete_status("provisional"))

    def test_protocol_and_regression_guard(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            base = {"protocol_id": "a", "label": "a", "score_status": "provisional", "metrics_score_status": "complete", "composite_score": 50,
                    "metrics": {"shape": {"score": 50}}, "regional_results": {"head": {"score": 70}}}
            candidate = copy.deepcopy(base)
            candidate["label"] = "b"
            candidate["composite_score"] = 55
            candidate["regional_results"]["head"]["score"] = 60
            a, b = directory/"a.json", directory/"b.json"
            write_json(a, base)
            write_json(b, candidate)
            self.assertEqual(compare_runs(a, b)["decision"], "hold_for_review")
            candidate["protocol_id"] = "changed"
            write_json(b, candidate)
            with self.assertRaises(ValueError):
                compare_runs(a, b)


if __name__ == "__main__":
    unittest.main()
