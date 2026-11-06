"""Compile the authorized whole-object scan through the common asset compiler.

The fixed frame declares source +Y as the broad front, +Z as up, -X as right.
A measured front selection then supplies a proper rigid planar alignment.
No aspect-ratio orientation heuristic, geometric flattening or invented RGB.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from lie_brick02_capture_scan import capture, load_source, _sample_mesh
from lie_asset_contract import planar_frame, inspect_bank

SOURCE_SHA='b55b9d584fcfa6d7baf9e1d815c02578d91e092efc4cf88a47c23bbee643031b'


def prepare(source, provenance, output):
    if hashlib.sha256(source.read_bytes()).hexdigest()!=SOURCE_SHA:raise ValueError('Different original scan; review source before substituting')
    meshes=load_source(source);vertices=np.concatenate([m.vertices for m in meshes]);center=(vertices.min(0)+vertices.max(0))*.5
    # Publisher's nominal eight-inch length is assigned to the authored source X.
    scale=.2032/np.ptp(vertices[:,0]);initial=np.array([[-1.,0,0],[0,0,1],[0,1,0]])
    rng=np.random.default_rng(2102);areas=np.array([m.area for m in meshes]);pilot=[]
    for m,n in zip(meshes,rng.multinomial(60000,areas/areas.sum())):
        if n:pilot.append(_sample_mesh(m,n,rng,np.arange(3),scale,center,.001,initial))
    pilot=np.concatenate(pilot);selection=np.flatnonzero((pilot[:,6]>.85)&(pilot[:,2]>.02)&(abs(pilot[:,0])<.08))
    fit=planar_frame(pilot,selection,forward_hint=(0,0,1),right_hint=(1,0,0))
    rotation=fit['rotation']@initial
    aligned=(vertices-center)@rotation.T*scale;mid=(aligned.min(0)+aligned.max(0))*.5
    pivot=center+rotation.T@(mid/scale)
    rough=float(meshes[0].metadata.get('lie_material_roughness',.6))
    profile={'master':'scanned_brick','source_to_lie':rotation.tolist(),'meters_per_source_unit':float(scale),'source_pivot':pivot.tolist(),
             'material_zone':3,'source_material_policy':'preserve_source',
             'optical_material':{'metallic':0.,'transmission':0.,'ior':1.5,'roughness_origin':'source_factor'},
             'frame_recipe':{'source_front':'+Y','source_up':'+Z','source_right':'-X','front_selection':'normal.z > .85, position.z > .02 m, abs(position.x) < .08 m after authored initial rotation',
                             'front_points':len(selection),'proper_rotation_determinant':float(np.linalg.det(rotation)),'planarity_ratio':float(fit['planarity_ratio'])},
             'material_provenance':{'color':'original glTF COLOR_0 linear vertex RGB; no photographic UV atlas supplied','roughness':rough,
                                    'ior':'authored opaque dielectric assumption; not measured','normal':'source triangle geometry','source_color_delighted_or_measured_albedo':False}}
    output.mkdir(parents=True,exist_ok=True)
    (output/'asset-profile.json').write_text(json.dumps(profile,indent=2)+'\n')
    catalog=capture(source,provenance,output,counts=(480000,64000,4096),seed=2102,asset_profile=profile)
    raw=bytearray((output/'library.bin').read_bytes());master=catalog['masters']['scanned_brick']
    for i,count in enumerate((512,128)):
        rng=np.random.default_rng(9001+i);items=[]
        for m,allocation in zip(meshes,rng.multinomial(count,areas/areas.sum())):
            if allocation:
                radius=float(np.clip(1.55*np.sqrt(m.area*scale**2/allocation),.00020,.04))
                items.append(_sample_mesh(m,allocation,rng,np.arange(3),scale,pivot,radius,rotation))
        a=np.concatenate(items);a[:,8]=3.;rng.shuffle(a)
        master['levels'].append({'start':len(raw)//80,'count':count});raw.extend(a.astype('<f4').tobytes())
    catalog.update(sample_count=len(raw)//80,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),source_material_declarations=profile['material_provenance'])
    master['lod_names']=['hero','near','wall','house','distant']
    master['bounds_size']=np.ptp((vertices-pivot)@rotation.T*scale,axis=0).tolist();master['bounds_center']=[0.,0.,0.]
    master['collision_proxy']='one conservative invisible source-bounds box; does not alter visual shape'
    (output/'library.bin').write_bytes(raw);(output/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    (output/'asset-contract.json').write_text(json.dumps(inspect_bank(raw,catalog),indent=2)+'\n')
    (output/'provenance.json').write_bytes(provenance.read_bytes())
    np.savez_compressed(output/'source-canonical.npz',vertices=((vertices-pivot)@rotation.T*scale).astype('<f4'),
                        triangles=np.concatenate([m.faces+sum(len(x.vertices) for x in meshes[:i]) for i,m in enumerate(meshes)]).astype('<u4'),
                        colors=np.concatenate([m.metadata['lie_vertex_colors_linear'] for m in meshes]).astype('<f4'))
    print('SCANNED BRICK PREPARED',catalog['sha256'],catalog['bytes'],master['bounds_size'],flush=True)
    return catalog


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--provenance',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();prepare(a.source,a.provenance,a.output)
