"""Check immutable source bytes and genuinely closed, correctly oriented cuts."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from lie_gltf_vertex_color import load_colored_glb
from lie_asset_contract import inspect_bank
def verify(base,bank,half_sources):
    raw=(bank/'library.bin').read_bytes();original=(base/'library.bin').read_bytes();assert raw[:len(original)]==original
    catalog=json.loads((bank/'catalog.json').read_text());inspect_bank(raw,catalog);cuts=json.loads((half_sources/'cuts.json').read_text());results={}
    for name,info in cuts.items():
        source=half_sources/info['file'];assert hashlib.sha256(source.read_bytes()).hexdigest()==info['sha256'];meshes=load_colored_glb(source);assert len(meshes)==2
        vertices=np.concatenate([m.vertices for m in meshes]);faces=np.concatenate([m.faces+sum(len(x.vertices) for x in meshes[:i]) for i,m in enumerate(meshes)])
        unique,inv=np.unique(vertices,axis=0,return_inverse=True);f=inv[faces];edges=np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),axis=1);_,count=np.unique(edges,axis=0,return_counts=True);assert (count==2).all(),'cut not closed'
        cap=meshes[1];assert len(cap.faces)==info['authored_cap_triangles'];assert np.max(abs(cap.vertices[cap.faces.ravel(),0]-info['cut_plane_m']))<2e-7
        expected=np.array(info['cut_normal']);assert np.min(cap.face_normals@expected)>.99999
        master=catalog['masters'][name];clip=master['cut_clip'];levels=master['levels'];points=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
        for level in levels:
            a=points[level['start']:level['start']+level['count']];assert np.max((a[:,0]-clip['plane_m'])*clip['sense'])<2e-7
        results[name]=dict(closed_edges=True,cut_normal_verified=True,original_surface_triangles=info['original_surface_triangles'],authored_cap_triangles=info['authored_cap_triangles'],source_sha256=info['sha256'])
    report=dict(schema='lie-running-bond-verification/1',original_bank_prefix_unchanged=True,bank_sha256=catalog['sha256'],bytes=len(raw),cuts=results)
    (bank/'construction-verification.json').write_text(json.dumps(report,indent=2)+'\n');print('CONSTRUCTION VERIFIED',catalog['sha256'],'immutable source and two closed cuts');return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--bank',type=Path,required=True);p.add_argument('--half-sources',type=Path,required=True);a=p.parse_args();verify(a.base,a.bank,a.half_sources)
