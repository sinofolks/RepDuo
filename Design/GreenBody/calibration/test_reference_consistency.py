import unittest
from audit_reference_consistency import score_ceiling


class ReferenceBoundTests(unittest.TestCase):
    def test_consistent_reference_can_reach100(self):
        self.assertEqual(score_ceiling(1),100)

    def test_nine_percent_disagreement_alone_excludes99(self):
        self.assertAlmostEqual(score_ceiling(.91),98.65)
        self.assertLess(score_ceiling(.91,.01),99)

    def test_triangle_bound_on_all_nonempty_four_pixel_sets(self):
        def j(a,b): return (a&b).bit_count()/(a|b).bit_count()
        for a in range(1,16):
            for b in range(1,16):
                for c in range(1,16):
                    mean=(70+30*j(a,c)+70+30*j(b,c))/2
                    self.assertLessEqual(mean,score_ceiling(j(a,b))+1e-10)


if __name__=='__main__': unittest.main()
