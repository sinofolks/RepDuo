"""Offline report data safety and integrity tests; no browser dependency."""
import copy
import json
from pathlib import Path
import re
import tempfile
import unittest

from PIL import Image

from report import build_report


class ReportTests(unittest.TestCase):
    def test_empty_report_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = build_report([], Path(temporary)/"report.html")
            self.assertIn("还没有校准记录", out.read_text())
            self.assertIn('"runs":[]', out.read_text())

    def test_injection_escaped_and_input_not_mutated(self):
        with tempfile.TemporaryDirectory() as temporary:
            runs = [{"label": "</script><img src=x onerror=alert(1)>", "score_status": "invalid_input"}]
            before = copy.deepcopy(runs)
            out = build_report(runs, Path(temporary)/"report.html")
            self.assertNotIn(runs[0]["label"], out.read_text())
            self.assertIn("\\u003c/script", out.read_text())
            self.assertEqual(runs, before)

    def test_embedded_assets_deduplicated(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root/"test.png"
            Image.new("RGB", (8, 8), "green").save(image)
            runs = [{"assets": {"reference": str(image), "candidate": str(image)}}]
            out = build_report(runs, root/"report.html")
            self.assertEqual(out.read_text().count("data:image/png;base64,"), 1)

    def test_missing_asset_warning_no_fabricated_image(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = build_report([{"assets": {"reference": "/missing-calibration-image.png"}}], Path(temporary)/"report.html")
            self.assertIn("图片文件不存在", out.read_text())
            self.assertNotIn("data:image/png;base64,", out.read_text())

    def test_no_nan_and_no_remote_dependencies(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = build_report([{"composite_score": float("nan")}], Path(temporary)/"report.html")
            text = out.read_text()
            self.assertIn('"composite_score":null', text)
            self.assertNotRegex(text, r'<(?:script|img)[^>]+src=["\']https?://')
            self.assertIn("connect-src 'none'", text)


if __name__ == "__main__":
    unittest.main()
