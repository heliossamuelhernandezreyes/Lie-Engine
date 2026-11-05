"""Reproduce the 80-vs-83 first-hit disagreement at an authenticated LIE wall pixel.

Does NOT read original Blender geometry; it interrogates the original captured
finite-cell bank, native Vulkan readbacks, and their actual view/proxy packets.
Also emulates the fragment shader's float32 world-ray plane intersection.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

EXPECTED_BANK_SHA='ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340'


def patch_coordinate(view, proxy, depth, pixel_x, pixel_y, width, rect_wh, axis=2, precision='double'):
    """Re-evaluate the original plane in float64 or GLSL-like float32 arithmetic."""
    lo=proxy[32:35];hi=proxy[36:39]
    inv=proxy[16:32].reshape(4,4).T
    transverse=[k for k in range(3) if k!=axis]
    if precision=='single':
        x=np.float32((pixel_x+.5)*2/width-1)
        y=np.float32((pixel_y+.5)*2/width-1)
        ray=view[12:15]+(view[4:7]*x-view[8:11]*y)*view[18]
        eye=inv[:3,:3]@view[:3]+inv[:3,3]
        direction=inv[:3,:3]@ray
        plane=np.float32(hi[axis]-depth)
        t=np.float32((plane-eye[axis])/direction[axis])
        p=eye+direction*t
        c=((p[transverse]-lo[transverse])/(hi[transverse]-lo[transverse]))*np.asarray(rect_wh,dtype=np.float32)
    elif precision=='double':
        v=view.astype(float); q=proxy.astype(float); i=q[16:32].reshape(4,4).T
        x=(pixel_x+.5)*2/width-1;y=(pixel_y+.5)*2/width-1
        ray=v[12:15]+(v[4:7]*x-v[8:11]*y)*v[18]
        eye=i[:3,:3]@v[:3]+i[:3,3]
        direction=i[:3,:3]@ray
        plane=float(hi[axis])-float(depth)
        t=(plane-eye[axis])/direction[axis]
        p=eye+direction*t
        c=((p[transverse]-lo[transverse])/(hi[transverse]-lo[transverse]))*np.asarray(rect_wh,dtype=float)
    else:raise ValueError('precision must be single or double')
    return {'capture_xy':[float(z) for z in c], 'local_t':float(t),
            'local_xyz':[float(z) for z in p]}


def inspect(captures: Path,bank: Path,pose=1,x=416,y=434,instance=8,cell_x=29,cell_y=36,layer=3):
    bank_sha=hashlib.file_digest((bank/'library.bin').open('rb'),'sha256').hexdigest()
    if bank_sha!=EXPECTED_BANK_SHA: raise ValueError('Not the authenticated attributed LIE capture bank')
    proof=json.loads((bank/'direct'/'surface.json').read_text())
    if proof['schema']!='lie-layered-surface/1':raise ValueError('Unexpected capture layout')
    width=720
    view=np.fromfile(captures/f'{pose}-native-views.bin','<f4')
    if len(view)<20:raise ValueError('Native view packet too short')
    view=view[:20]
    proxies=np.fromfile(captures/f'{pose}-native-proxies.bin','<f4').reshape(97,48)
    proxy=proxies[instance]
    if instance>=96:raise ValueError('This diagnostic is for one brick instance, not mortar')
    face=proof['boxes'][0]['first_face']+4
    rect=proof['faces'][face]
    if not (0<=cell_x<rect['width'] and 0<=cell_y<rect['height'] and 0<=layer<4):
        raise ValueError('Selected atlas cell out of bounds')
    samples=np.fromfile(bank/'direct'/'depth.bin','<f4').reshape(proof['height'],proof['width'],4)
    normals=np.fromfile(bank/'direct'/'normal.bin','<f2').reshape(4,proof['height'],proof['width'],4)
    depth=samples[rect['y']+cell_y,rect['x']+cell_x,layer]
    surface_id=float(normals[layer,rect['y']+cell_y,rect['x']+cell_x,3])+float(proxy[42])+1
    if depth<0:raise ValueError('Selected patch not occupied')
    native=np.fromfile(captures/f'{pose}-native-world.bin','<f4').reshape(-1,4)[y*width+x]
    regions=np.fromfile(captures/f'{pose}-regions-world.bin','<f4').reshape(-1,4)[y*width+x]
    d=patch_coordinate(view,proxy,depth,x,y,width,(rect['width'],rect['height']),precision='double')
    f=patch_coordinate(view,proxy,depth,x,y,width,(rect['width'],rect['height']),precision='single')
    cell=np.asarray([cell_x,cell_y],dtype=float)
    sizes=(proxy[36:39]-proxy[32:35])[:2]/np.asarray([rect['width'],rect['height']])
    delta_double=np.asarray(d['capture_xy'])-cell
    delta_single=np.asarray(f['capture_xy'])-cell
    sweeps=[]
    for delta in (-.01,-.001,-.0001,-.00005,0,.00005,.0001,.001,.01):
        dp=patch_coordinate(view,proxy,depth,x+delta,y,width,(rect['width'],rect['height']),precision='double')
        fp=patch_coordinate(view,proxy,depth,x+delta,y,width,(rect['width'],rect['height']),precision='single')
        sweeps.append({'x_offset_pixels':delta,'double_capture_x':dp['capture_xy'][0],
                       'single_capture_x':fp['capture_xy'][0],
                       'double_inside_selected_cell':bool(np.all(np.asarray(dp['capture_xy'])>=cell) and np.all(np.asarray(dp['capture_xy'])<cell+1)),
                       'single_inside_selected_cell':bool(np.all(np.asarray(fp['capture_xy'])>=cell) and np.all(np.asarray(fp['capture_xy'])<cell+1))})
    out={'schema':'lie-native-edge-forensics/1','source':'authenticated captured bank and actual native Vulkan packets; NOT original Blender mesh',
         'pose':pose,'pixel':[x,y],'instance':instance,'instance_first_owner':float(proxy[42])+1,
         'surface_id_from_layer':surface_id,'patch':{'face':4,'cell':[cell_x,cell_y],'layer':layer,'depth_m':float(depth),
             'cell_sizes_m':[float(z) for z in sizes]},
         'native_owner':float(native[3]),'regions_owner':float(regions[3]),
         'native_world_xyz':[float(z) for z in native[:3]],
         'regions_world_xyz':[float(z) for z in regions[:3]],
         'double':d,'single':f,'double_relative_cell_xy':delta_double.tolist(),
         'single_relative_cell_xy':delta_single.tolist(),
         'signed_double_distance_from_left_x_edge_m':float(delta_double[0]*sizes[0]),
         'signed_single_distance_from_left_x_edge_m':float(delta_single[0]*sizes[0]),
         'double_inside':bool(np.all(delta_double>=0)&np.all(delta_double<1)),
         'single_inside':bool(np.all(delta_single>=0)&np.all(delta_single<1)),
         'subpixel_sweep':sweeps,'limitations':['IEEE float32 emulation uses NumPy operations, not actual shader instruction-level trace',
           'A proximity-to-boundary classification is not a general proof of all LIE defects',
           'This is captured-cell fidelity only, not a comparison to original mesh']}
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--pose',type=int,default=1)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--assert-critical',action='store_true',help='Require observed 80-vs-83 float32-boundary-inversion regression')
    args=p.parse_args()
    data=inspect(args.captures,args.bank,args.pose)
    if args.assert_critical and not (data['native_owner']==80 and data['regions_owner']==83
       and data['surface_id_from_layer']==80 and not data['double_inside'] and data['single_inside']):
        raise AssertionError('Archived critical case did not reproduce; inspect provenance and shader changes')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    print(json.dumps({key:data[key] for key in ('pose','pixel','native_owner','regions_owner','double_relative_cell_xy',
        'single_relative_cell_xy','signed_double_distance_from_left_x_edge_m',
        'signed_single_distance_from_left_x_edge_m','double_inside','single_inside')},indent=2))


if __name__=='__main__':main()
