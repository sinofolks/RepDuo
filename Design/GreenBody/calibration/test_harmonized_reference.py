import copy
import json
import unittest
from pathlib import Path
import numpy as np
from PIL import Image
from harmonize_turnaround import reflected_mask, segment
from calibrate import digest
from multiview_run import aggregate_results
from test_multiview import fixture

ROOT=Path(__file__).resolve().parent


class HarmonizedReferenceTests(unittest.TestCase):
    def test_original_and_unchanged_projections(self):
        original=ROOT.parent/'reference/green-body-turnaround-v1-candidate.png'
        final=ROOT.parent/'reference/green-body-turnaround-v3b-harmonized.png'
        self.assertEqual(digest(original),'0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4')
        a,b=np.asarray(Image.open(original)),np.asarray(Image.open(final))
        self.assertEqual(a.shape,b.shape)
        np.testing.assert_array_equal(a[:,:1110],b[:,:1110])
        np.testing.assert_array_equal(a[835:],b[835:])
        audit=json.loads(final.with_suffix('.json').read_text())
        self.assertEqual(digest(final),audit['candidate_sha256'])
        np.testing.assert_array_equal(segment(b,'back'),reflected_mask(segment(a,'front'),audit['back_reflection_x_sum']))

    def test_new_protocol_preserves_capture_settings(self):
        for view in ('front','side','back'):
            old=ROOT/'multiview-pose-v2/profiles'/f'{view}.json'
            new=ROOT/'multiview-reference-v3/profiles'/f'{view}.json'
            self.assertEqual(old.read_bytes(),new.read_bytes())

    def test_mixed_reference_series_rejected(self):
        results=fixture()
        results['back']['provenance']['reference']['config']['reference_series']='turnaround-v3-harmonized'
        with self.assertRaises(ValueError):aggregate_results(results)

    def test_all_new_reference_series_allowed_without_auto_approval(self):
        results=fixture()
        for result in results.values():
            result['provenance']['reference']['config']['reference_series']='turnaround-v3-harmonized'
        self.assertFalse(aggregate_results(results)['automatic_model_approval'])


if __name__=='__main__':unittest.main()
