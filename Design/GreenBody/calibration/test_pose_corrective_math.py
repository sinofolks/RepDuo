import math
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from pose_corrective_math import smooth_gate,weight_from_distances,DRIVER_EXPRESSION


def triangle(raise_degrees,bend_degrees,scale=1):
    theta,phi=map(math.radians,(raise_degrees,bend_degrees))
    a,b,d=.26,.26,.50
    ex,ez=a*math.sin(theta),-a*math.cos(theta)
    wx,wz=ex+b*math.sin(theta+phi),ez-b*math.cos(theta+phi)
    return dict(zip('abcde',[scale*v for v in (a,b,math.hypot(wx,wz),d,math.hypot(ex,ez+d))]))


class CorrectiveMathTests(unittest.TestCase):
    def test_neutral_and_flexed_endpoints(self):
        self.assertEqual(weight_from_distances(**triangle(0,0)),1)
        self.assertEqual(weight_from_distances(**triangle(90,0)),.2)
        self.assertEqual(weight_from_distances(**triangle(0,100)),.2)

    def test_simple_driver_matches_python_math(self):
        for raised in range(0,121,5):
            for bent in range(0,161,5):
                values=triangle(raised,bent)
                result=eval(DRIVER_EXPRESSION,{'__builtins__':{},'cos':math.cos,'pi':math.pi,'min':min,'max':max},values)
                self.assertAlmostEqual(result,weight_from_distances(**values),places=12)
                self.assertGreaterEqual(result,.2)
                self.assertLessEqual(result,1)

    def test_global_scale_invariant(self):
        for scale in (.01,.5,3,100):
            self.assertAlmostEqual(weight_from_distances(**triangle(25,45)),
                                   weight_from_distances(**triangle(25,45,scale)),places=12)

    def test_gate_no_jump_or_slope_at_clamps(self):
        eps=1e-6
        for edge in (.25,.8):
            self.assertLess(abs(smooth_gate(edge+eps)-smooth_gate(edge-eps))/eps,1e-4)

    def test_rejects_invalid_distances(self):
        for value in (0,-1,float('inf'),float('nan')):
            values=triangle(0,0);values['a']=value
            with self.assertRaises(ValueError):weight_from_distances(**values)


if __name__=='__main__':unittest.main()
