"""Explicitly authorized deterministic back-contour edit. Original never overwritten.

Source front projection is authoritative. Back appearance comes only from the
original back, not from model renders or front anatomy. This is authored reference
harmonization, not a measurement of three-dimensional truth.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, PngImagePlugin
from scipy import ndimage
from calibrate import digest, largest_component, bounds
from audit_turnaround_candidate import audit

ROOT = Path(__file__).resolve().parent


def segment(rgb, view):
    cfg = json.loads((ROOT/'multiview/configs'/f'{view}.json').read_text())
    r,g,b = [rgb[...,i].astype(float) for i in range(3)]
    s = cfg['segmentation']
    mask = (g >= s['min_green']) & (g > r*s['green_red_ratio']) & (g > b*s['green_blue_ratio'])
    x0,y0,x1,y1 = cfg['roi']
    region = np.zeros(mask.shape,bool)
    region[y0:y1,x0:x1] = True
    return largest_component(mask & region)


def intervals(row):
    padded = np.r_[False,row,False].astype(int)
    return list(zip(np.where(np.diff(padded)==1)[0],np.where(np.diff(padded)==-1)[0]))


def reflected_mask(front, reflection_sum):
    target = np.zeros_like(front)
    ys,xs = np.where(front)
    dest = reflection_sum-xs
    if dest.min()<0 or dest.max()>=front.shape[1]:
        raise ValueError('Reflected silhouette exceeds image')
    target[ys,dest] = True
    return target


def remap_back(rgb, old, target, smooth=False):
    """Rowwise interval transport, preserving foreground gaps and source anatomy.

    Major intervals map monotonically by rank where their count agrees. At
    finger/topology changes map each target interval to nearest source interval.
    The transported texture is clipped to the authoritative mask, never the
    reverse. No fitted model data are used.
    """
    out = rgb.copy()
    target_box, old_box = bounds(target), bounds(old)
    height = old.shape[0]
    old_rows = np.where(old.any(axis=1))[0]
    # Extend foreground color slightly for interpolation without black fringes.
    core = ndimage.binary_erosion(old,iterations=1)
    _, nearest = ndimage.distance_transform_edt(~core,return_indices=True)
    texture = rgb[nearest[0],nearest[1]].astype(float)
    changed_topology = []
    displacement = np.zeros(old.shape,float)
    for y in range(height):
        if not (old[y].any() or target[y].any()):
            continue
        # Reconstruct the old body's vacated backdrop from its surrounding row.
        old_x = np.where(old[y])[0]
        if len(old_x):
            a,b = max(1110,int(old_x[0])-4), min(1490,int(old_x[-1])+5)
            left,right = rgb[y,max(1110,a-3)].astype(float),rgb[y,min(1489,b+3)].astype(float)
            erase = ndimage.binary_dilation(old[y],iterations=3)
            xs = np.where(erase)[0]
            t = np.clip((xs-a)/max(1,b-a),0,1)
            out[y,xs] = np.rint(left[None,:]*(1-t[:,None])+right[None,:]*t[:,None]).astype(np.uint8)
        if not target[y].any():
            continue
        sy = int(old_rows[np.argmin(abs(old_rows-y))])
        sources,targets = intervals(old[sy]),intervals(target[y])
        if len(sources)!=len(targets):
            changed_topology.append(y)
        old_center=(old_box[0]+old_box[2]-1)/2
        new_center=(target_box[0]+target_box[2]-1)/2
        for i,(a,b) in enumerate(targets):
            if len(sources)==len(targets):
                c,d=sources[i]
            else:
                guess=(a+b-1)/2-new_center+old_center
                c,d=min(sources,key=lambda ab:abs((ab[0]+ab[1]-1)/2-guess))
            xs=np.arange(a,b)
            sx=np.linspace(c,d-1,b-a) if b-a>1 else np.array([(c+d-1)/2])
            displacement[y,xs]=sx-xs
            colors=np.stack([ndimage.map_coordinates(texture[...,ch],
                [np.full(len(sx),sy),sx],order=1,mode='nearest') for ch in range(3)],axis=1)
            colors=np.rint(colors).clip(0,255).astype(np.uint8)
            # Texture transport must not create false holes through thresholding.
            if not np.all((colors[:,1]>=50)&(colors[:,1]>colors[:,0]*1.025)&(colors[:,1]>colors[:,2]*1.3)):
                raise ValueError('Transported back texture violated foreground classification')
            out[y,xs]=colors
    if smooth:
        # Smooth the transport field, not the silhouette or surface colors.
        # This removes scan-line discontinuities without changing locked edges.
        weights=ndimage.gaussian_filter(target.astype(float),sigma=(7,4))
        delta=ndimage.gaussian_filter(displacement*target,sigma=(7,4))/np.maximum(weights,1e-8)
        yy,xx=np.where(target)
        colors=np.stack([ndimage.map_coordinates(texture[...,ch],
            [yy,xx+delta[yy,xx]],order=1,mode='nearest') for ch in range(3)],axis=1)
        # Reconstruct only the back ROI backdrop; other projections and labels
        # are untouched. Smooth boundary samples avoid remnants of old edges.
        left=ndimage.gaussian_filter1d(rgb[25:835,1110].astype(float),sigma=5,axis=0)
        right=ndimage.gaussian_filter1d(rgb[25:835,1489].astype(float),sigma=5,axis=0)
        t=np.linspace(0,1,380)[None,:,None]
        out[25:835,1110:1490]=np.rint(left[:,None,:]*(1-t)+right[:,None,:]*t).astype(np.uint8)
        # A one-pixel edge taper retains classification but avoids hard cutouts.
        depth=ndimage.distance_transform_edt(target)[yy,xx]
        alpha=np.clip(.70+.15*(depth-1),.70,1)
        alpha=np.maximum(alpha,np.minimum(1,52/np.maximum(colors[:,1],1)))
        colors*=alpha[:,None]
        colors=np.rint(colors).clip(0,255).astype(np.uint8)
        if not np.all((colors[:,1]>=50)&(colors[:,1]>colors[:,0]*1.025)&(colors[:,1]>colors[:,2]*1.3)):
            raise ValueError('Smoothed texture lost foreground classification')
        out[yy,xx]=colors
    return out,changed_topology


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--smooth',action='store_true')
    args=p.parse_args()
    out=args.out.resolve()
    report_path=out.with_suffix('.json')
    if out.exists() or report_path.exists():
        raise ValueError('Refusing to overwrite a reference or audit')
    source=ROOT.parent/'reference/green-body-turnaround-v1-candidate.png'
    source_hash=digest(source)
    assert source_hash=='0b67949743a66b47a6b86fa0f0493068f792e6de4bbd2943e6da58e01f96f6b4'
    rgb=np.asarray(Image.open(source).convert('RGB'))
    front,back=segment(rgb,'front'),segment(rgb,'back')
    fb,bb=bounds(front),bounds(back)
    reflection_sum=round((fb[0]+fb[2]-1+bb[0]+bb[2]-1)/2)
    target=reflected_mask(front,reflection_sum)
    result,topology_rows=remap_back(rgb,back,target,smooth=args.smooth)
    assert np.array_equal(rgb[:,:1110],result[:,:1110])
    assert np.array_equal(rgb[835:],result[835:])
    assert np.array_equal(segment(result,'back'),target)
    changed=np.any(result!=rgb,axis=2)
    assert not changed[:,:1110].any() and not changed[:,1490:].any()
    meta=PngImagePlugin.PngInfo()
    meta.add_text('Provenance','User-authorized deterministic reference harmonization; back contour from mirrored original front; back shading transported from original back. Not a model render.')
    meta.add_text('OriginalSHA256',source_hash)
    meta.add_text('ScriptSHA256',digest(Path(__file__)))
    Image.fromarray(result).save(out,pnginfo=meta)
    assert digest(source)==source_hash
    report=audit(out)
    report.update({'method':'authoritative mirrored front mask + original-back interval texture transport',
                   'programmatic_edit_authorization':'允许啊，快点吧',
                   'smooth_transport_field':args.smooth,
                   'source_unchanged':True,'front_and_side_pixels_unchanged':True,
                   'labels_unchanged':True,'original_size_preserved':True,
                   'source_pixel_front_back_mirror_iou':1.0,
                   'back_reflection_x_sum':reflection_sum,'back_y_translation':0,
                   'edited_pixels':int(changed.sum()),'edited_bounds':bounds(changed),
                   'interval_topology_transition_rows':topology_rows,
                   'script_sha256':digest(Path(__file__)),
                   'limitations':['Back interior is resampled artwork, not independently observed geometry.',
                                  'Side projection was preserved, not certified as globally consistent 3D.',
                                  'Exact source-mask agreement is imposed by editing and is NOT model accuracy.',
                                  'Canonical mirror IoU can differ due to independent nearest-neighbor framing.']})
    with report_path.open('x') as f: json.dump(report,f,indent=2)
    print(json.dumps({k:report[k] for k in ('candidate','source_pixel_front_back_mirror_iou',
        'front_back_mirror_iou','translation_sensitivity','front_and_side_pixels_unchanged','edited_pixels')},indent=2))


if __name__=='__main__': main()
