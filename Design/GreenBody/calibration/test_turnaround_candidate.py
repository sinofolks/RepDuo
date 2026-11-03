import unittest
from pathlib import Path
from audit_turnaround_candidate import audit
from calibrate import digest


class CandidateAuditTests(unittest.TestCase):
    def test_original_recovers_locked_mirror_result_without_changes(self):
        path = Path(__file__).resolve().parents[1]/'reference/green-body-turnaround-v1-candidate.png'
        before = digest(path)
        result = audit(path)
        self.assertEqual(before, digest(path))
        self.assertAlmostEqual(result['front_back_mirror_iou'], .9087081140236594)
        self.assertAlmostEqual(result['translation_sensitivity']['best_iou'], .9176020942408377)
        self.assertFalse(result['translation_sensitivity']['applied'])
        self.assertFalse(result['reference_selected'])
        self.assertEqual(result['design_silhouette_retention'], {'front':1.,'side':1.,'back':1.})


if __name__ == '__main__':
    unittest.main()
