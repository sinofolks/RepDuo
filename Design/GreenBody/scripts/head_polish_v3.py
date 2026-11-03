"""Topology-preserving V3 head/neck study, never edits V2 or studio settings.

``refine_head(body, params=None)`` changes only rest-space head/neck geometry.
All coordinates are meters. Skin weights, faces and the skeleton are retained.
The command-line study renders real Blender geometry in a separate directory.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_green_body import smoothstep
from body_geometry_v2 import _rotate

DEFAULTS = {"strength": 1.0, "neck_strength": 1.0, "nose": .0045,
            "chin": .0018, "face_exponent": .86, "ear_relief": .80,
            "base_polish": 1.0}


def sample(z, data, channel=1):
    """Shape-preserving, first-derivative-continuous profile interpolation."""
    if z <= data[0][0]:
        return data[0][channel]
    if z >= data[-1][0]:
        return data[-1][channel]
    i = next(i for i in range(len(data)-1) if data[i][0] <= z <= data[i+1][0])
    def tangent(k):
        if k == 0:
            return (data[1][channel]-data[0][channel])/(data[1][0]-data[0][0])
        if k == len(data)-1:
            return (data[-1][channel]-data[-2][channel])/(data[-1][0]-data[-2][0])
        a,b,c = data[k-1:k+2]
        h0,h1 = b[0]-a[0], c[0]-b[0]
        d0,d1 = (b[channel]-a[channel])/h0, (c[channel]-b[channel])/h1
        if d0*d1 <= 0:
            return 0.0
        w0,w1 = 2*h1+h0, h1+2*h0
        return (w0+w1)/(w0/d0+w1/d1)
    a,b = data[i:i+2]
    h=b[0]-a[0]
    t=(z-a[0])/h
    return ((2*t**3-3*t*t+1)*a[channel]+(t**3-2*t*t+t)*h*tangent(i)
            +(-2*t**3+3*t*t)*b[channel]+(t**3-t*t)*h*tangent(i+1))


def gaussian(value, center, width):
    return math.exp(-.5*((value-center)/width)**2)


def refine_head(body, params=None):
    p = {**DEFAULTS, **(params or {})}
    mesh = body.data
    before = [(tuple(v.co), tuple((g.group,g.weight) for g in v.groups)) for v in mesh.vertices]
    # Measured V2 cross-sections: the unwanted narrow posterior notch at 1.55
    # and anterior neck bulge are replaced by one smooth cervical envelope.
    old_neck = [(1.49,.19225,-.07436,.06056), (1.51,.15037,-.08015,.04609),
                (1.53,.09699,-.07910,.02880), (1.55,.06815,-.09312,.00358),
                (1.57,.05660,-.09315,.02253), (1.59,.04735,-.09214,.02938),
                (1.61,.05035,-.12400,.03640), (1.63,.06318,-.13308,.04804)]
    new_neck = [(1.49,.19225,-.07436,.06056), (1.51,.15037,-.08015,.04609),
                (1.53,.09400,-.08000,.03000), (1.55,.06200,-.08200,.02500),
                (1.57,.04950,-.07900,.02600), (1.59,.04600,-.08600,.03100),
                (1.61,.05100,-.11850,.03900), (1.63,.06318,-.13100,.04804)]
    # Facial plane becomes one continuous blank mannequin surface. There is
    # no mouth, nostril or orbital bowl. The small nasal ridge is deliberately
    # broad and low, while the chin/jaw separation remains readable in profile.
    face = [(1.600,-.1020), (1.615,-.1260), (1.632,-.1320),
            (1.650,-.1320), (1.677,-.1320), (1.701,-.1320),
            (1.720,-.1330), (1.740,-.1310)]
    old_head = [(1.556,.064,-.091,.009), (1.570,.053,-.088,.024),
                (1.589,.047,-.091,.029), (1.605,.0475,-.115,.034),
                (1.617,.054,-.128,.039), (1.632,.063,-.132,.048),
                (1.655,.0725,-.130,.059), (1.675,.078,-.130,.064),
                (1.696,.0805,-.131,.064), (1.720,.081,-.133,.059)]
    changed = 0
    for vertex in mesh.vertices:
        x,y,z = vertex.co
        if z <= 1.49:
            continue
        neck = smoothstep(1.515,1.54,z)*(1-smoothstep(1.606,1.636,z))*p["neck_strength"]
        if neck > 0:
            rx0, f0, b0 = [sample(z,old_neck,k) for k in (1,2,3)]
            rx1, f1, b1 = [sample(z,new_neck,k) for k in (1,2,3)]
            # Project onto a smooth cervical ellipse while retaining angular
            # order. This removes the small radial folds of the V2 cut join;
            # an affine scale alone would preserve those unwanted folds.
            theta=math.atan2((y-(f0+b0)/2)/((b0-f0)/2),x/rx0)
            vertex.co.x += (rx1*math.cos(theta)-x)*neck
            target_y = (f1+b1)/2+(b1-f1)/2*math.sin(theta)
            vertex.co.y += (target_y-y)*neck
        if 1.601 < z < 1.752 and y < -.018:
            arc=math.sqrt(max(1e-8,1-((z-1.705)/.115)**2))
            cranial=smoothstep(1.642,1.672,z)
            rx=sample(min(z,1.720),old_head,1)
            back=sample(min(z,1.720),old_head,3)
            rx += (.082*arc-rx)*cranial
            back += (-.038+.101*arc-back)*cranial
            front=sample(z,face)
            side = min(1.0,abs(x)/rx)
            sine=math.sqrt(max(0,1-side*side))
            cy=(front+back)/2
            target_y=cy-(cy-front)*sine**p["face_exponent"]
            target_y -= p["nose"]*gaussian(x,0,.016)*gaussian(z,1.686,.019)
            target_y -= p["chin"]*gaussian(x,0,.027)*gaussian(z,1.627,.014)
            region=smoothstep(1.601,1.625,z)*(1-smoothstep(1.720,1.752,z))
            region *= (1-smoothstep(-.065,-.018,y))*p["strength"]
            vertex.co.y += (target_y-vertex.co.y)*region
        # Retain the original integrated ear topology; remove only some of
        # its protrusion so that its concha no longer reads like a glued lump.
        if 1.651 < z < 1.721 and abs(x) > .072 and y > -.047:
            arc=math.sqrt(max(1e-8,1-((z-1.705)/.115)**2))
            expected=.082*arc
            excess=max(0,abs(x)-expected)
            vertex.co.x -= math.copysign(excess*(1-p["ear_relief"]),x)
        changed += tuple(vertex.co) != before[vertex.index][0]
    neighbors=[[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a,b=edge.vertices
        neighbors[a].append(b)
        neighbors[b].append(a)
    # The lower original neck has irregular longitudinal spacing. Polish its
    # transition into the regular cervical envelope with a bounded local brush.
    for _ in range(24):
        positions=[v.co.copy() for v in mesh.vertices]
        for vertex in mesh.vertices:
            z=before[vertex.index][0][2]
            weight=smoothstep(1.491,1.513,z)*(1-smoothstep(1.549,1.578,z))
            weight *= .42*p["base_polish"]
            if weight>0 and neighbors[vertex.index]:
                mean=sum((positions[n] for n in neighbors[vertex.index]),Vector())/len(neighbors[vertex.index])
                vertex.co+=(mean-positions[vertex.index])*weight
    changed=sum(tuple(v.co)!=before[v.index][0] for v in mesh.vertices)
    mesh.update()
    assert all(tuple(v.co) == before[v.index][0] for v in mesh.vertices if before[v.index][0][2] <= 1.49)
    assert all(tuple((g.group,g.weight) for g in v.groups) == before[v.index][1] for v in mesh.vertices)
    return {"parameters":p,"changed_vertices":changed,"topology_preserved":True,
            "weights_preserved":True,"below_1_49_m_unchanged":True}


def main():
    if not bpy.app.background:
        raise RuntimeError("Background only; preserve the user's open Blender scene.")
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--params",type=Path)
    parser.add_argument("--yaw",type=float,default=18)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    out=args.out.resolve()
    if out.exists():
        raise ValueError(f"Refusing to overwrite {out}")
    out.mkdir(parents=True)
    source=ROOT/"GreenBody-v2.blend"
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    body=bpy.data.objects["GreenBody"]
    report=refine_head(body,json.loads(args.params.read_text()) if args.params else None)
    rig=next(m.object for m in body.modifiers if m.type=="ARMATURE")
    for name,weight in (("neck01",.25),("neck02",.25),("head",.5)):
        _rotate(rig.pose.bones[name],Quaternion((0,0,1),math.radians(args.yaw*weight)))
    scene=bpy.context.scene
    scene.cycles.device="CPU"
    scene.cycles.samples=32
    scene.render.resolution_x=800
    scene.render.resolution_y=800
    scene.render.resolution_percentage=100
    bpy.ops.wm.save_as_mainfile(filepath=str(out/"head-study.blend"))
    target=Vector((0,-.025,1.63))
    for name,offset in (("head",(-1.70,-5,.12)),("front",(0,-5,.12)),("side",(-5,0,.12)),("back",(0,5,.12))):
        camera=bpy.data.objects["GB_Camera_Hero"].copy()
        camera.data=camera.data.copy()
        scene.collection.objects.link(camera)
        camera.location=target+Vector(offset)
        camera.rotation_euler=(target-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.ortho_scale=.61
        scene.camera=camera
        scene.render.filepath=str(out/(name+".png"))
        bpy.ops.render.render(write_still=True)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
    report.update({"parent_sha256":digest,"parent_unchanged":True,"yaw_degrees":args.yaw})
    (out/"study.json").write_text(json.dumps(report,indent=2))
    print("HEAD_POLISH_V3",out,flush=True)


if __name__=="__main__":
    main()
