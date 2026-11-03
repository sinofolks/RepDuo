"""Guard an explicit pose-only protocol revision against unrelated score changes."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parent


class PoseProtocolTests(unittest.TestCase):
    def test_only_declared_pose_metadata_differs(self):
        for view in ('front','side','back'):
            old=json.loads((ROOT/'multiview/profiles'/f'{view}.json').read_text())
            new=json.loads((ROOT/'multiview-pose-v2/profiles'/f'{view}.json').read_text())
            for key in ('name','turnaround_pose_rule','code_dependencies'):
                old.pop(key); new.pop(key)
            self.assertEqual(old,new,view)

    def test_dependencies_are_current_and_studios_identical(self):
        for view in ('front','side','back'):
            dependencies=[]
            for folder in ('multiview','multiview-pose-v2'):
                profile=json.loads((ROOT/folder/'profiles'/f'{view}.json').read_text())
                deps=profile['code_dependencies']
                for path,expected in deps.items():
                    self.assertEqual(hashlib.sha256((ROOT.parent/path).read_bytes()).hexdigest(),expected,path)
                dependencies.append({k:v for k,v in deps.items() if 'prepare_turnaround_pose' not in k})
            self.assertEqual(*dependencies)

    def test_original_pose_rule_is_unchanged(self):
        path=ROOT.parent/'scripts/prepare_turnaround_pose.py'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),
                         'e357c74d5dab68e420749278240e4eb515af20caa9946e2fd3b9fb3e894d7dfe')

    def test_approved_design_is_unchanged(self):
        path=ROOT.parent/'reference/green-body-turnaround-v1-candidate.png'
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),
                         '0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4')


if __name__=='__main__': unittest.main()
