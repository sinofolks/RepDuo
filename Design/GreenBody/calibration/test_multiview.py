import copy
import unittest

from multiview_run import aggregate_results, VIEWS


def fixture(scores=(99,99,99)):
    return {v: {'score_status': 'provisional', 'landmark_coverage': 1,
                'composite_score': score, 'protocol_id': v+'-protocol',
                'provenance': {'capture': {'status':'complete', 'source_unchanged':True,
                               'native_appearance': True, 'track':'native-material_fixed-studio',
                               'geometry_hash':'geometry', 'pose_hash':'pose', 'material_hash':'material',
                               'source_blend_sha256_before':'same', 'source_blend_sha256_after':'same'},
                               'reference':{'config':{'view':'approved-turnaround-'+v,
                                            'design_approval':{'status':'user_approved'}}}}}
            for v, score in zip(VIEWS, scores)}


class MultiViewTest(unittest.TestCase):
    def test_all_views_required(self):
        data = fixture()
        del data['back']
        with self.assertRaises(ValueError): aggregate_results(data)

    def test_mean_never_hides_weak_view(self):
        result = aggregate_results(fixture((100,100,98)))
        self.assertGreater(result['equal_view_mean'], 99)
        self.assertEqual(result['minimum_view_score'], 98)
        self.assertFalse(result['numeric_99_target_met_in_every_view'])

    def test_numeric_pass_is_not_automatic_approval(self):
        result = aggregate_results(fixture())
        self.assertTrue(result['numeric_99_target_met_in_every_view'])
        self.assertFalse(result['automatic_model_approval'])

    def test_different_models_rejected(self):
        data = fixture()
        cap = data['side']['provenance']['capture']
        cap['source_blend_sha256_before'] = cap['source_blend_sha256_after'] = 'different'
        with self.assertRaises(ValueError): aggregate_results(data)

    def test_wrong_reference_rejected(self):
        data = fixture()
        data['side']['provenance']['reference']['config']['view'] = 'approved-turnaround-front'
        with self.assertRaises(ValueError): aggregate_results(data)

    def test_invalid_evidence_rejected(self):
        mutations = [('score_status','incomplete_landmarks_zero_penalized'),
                     ('landmark_coverage',.5), ('composite_score',float('nan')),
                     ('composite_score',101)]
        for key, value in mutations:
            data = fixture()
            data['front'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                aggregate_results(data)

    def test_capture_guard(self):
        for key, value in [('status','failed'),('source_unchanged',False),('native_appearance',False),
                           ('source_blend_sha256_after','changed')]:
            data = fixture()
            data['back']['provenance']['capture'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): aggregate_results(data)

    def test_input_not_mutated(self):
        data = fixture((70,80,90))
        original = copy.deepcopy(data)
        aggregate_results(data)
        self.assertEqual(data, original)

    def test_view_dependent_body_state_rejected(self):
        for key in ('geometry_hash','pose_hash','material_hash'):
            data = fixture()
            data['side']['provenance']['capture'][key] = 'changed'
            with self.subTest(key=key), self.assertRaises(ValueError): aggregate_results(data)


if __name__ == '__main__': unittest.main()
