"""Camera-independent, continuous artistic trapezius corrective weights.

Distance-triangle cosines avoid bone-roll conventions. This is an artistic
deformation rule, not a measured biomechanical muscle simulation.
"""
import math


def smooth_gate(cosine):
    t=min(1.,max(0.,(cosine-.25)/.55))
    return .5*(1-math.cos(math.pi*t))


def weight_from_distances(a,b,c,d,e):
    if not all(math.isfinite(v) and v>1e-8 for v in (a,b,c,d,e)):
        raise ValueError('Invalid bone-point distances')
    elevation_cos=(a*a+d*d-e*e)/(2*a*d)
    elbow_cos=(c*c-a*a-b*b)/(2*a*b)
    return .2+.8*smooth_gate(elevation_cos)*smooth_gate(elbow_cos)


# a=shoulder-elbow, b=elbow-wrist, c=shoulder-wrist,
# d=shoulder-lower-spine, e=elbow-lower-spine.
# Blender's built-in simple expression evaluator; no Python namespace/callback.
DRIVER_EXPRESSION='.2+.2*(1-cos(pi*min(1,max(0,((a*a+d*d-e*e)/(2*a*d)-.25)/.55))))*(1-cos(pi*min(1,max(0,((c*c-a*a-b*b)/(2*a*b)-.25)/.55))))'
