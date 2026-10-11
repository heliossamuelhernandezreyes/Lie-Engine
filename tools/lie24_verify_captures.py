"""Verify per-assembly seams, exclusive ownership and rigid capture packets."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import numpy as np


def verify(project):
    root=Path(project)/'captures/face24';m=json.loads((root/'master.json').read_text());seam=json.loads((root/'seam.json').read_text())
    for name,meta in m['buffers'].items():
        data=(root/name).read_bytes()
        assert len(data)==meta['bytes'] and hashlib.sha256(data).hexdigest()==meta['sha256']
    v=np.frombuffer((root/'vertices.bin').read_bytes(),dtype='<f4').reshape(-1,24)
    t=np.frombuffer((root/'triangles.bin').read_bytes(),dtype='<u4').reshape(-1,4)
    s=np.frombuffer((root/'samples.bin').read_bytes(),dtype='<f4').reshape(-1,20)
    assert len(v)==m['vertex_count']<m['original_vertex_count'] and np.isfinite(v).all()
    assert len(t)==m['triangle_count'] and t[:,:3].max()<len(v)
    assert len(s)==m['sample_count']==m['face_sample_count']+m['eye_sample_count'] and np.isfinite(s).all()
    assert m['invocation_count']==m['face_sample_count']+2*m['eye_sample_count']<=1000000
    face=s[:m['face_sample_count']];rigid=face[:,3]==-2;deforming=face[~rigid]
    assert rigid.sum()==m['rigid_face_sample_count']>100000
    assert (deforming[:,3]>=0).all() and (deforming[:,3]<len(t)).all()
    assert np.max(abs(deforming[:,:3].sum(1)-1))<.0002
    assert np.max(abs(np.linalg.norm(face[rigid,16:19],axis=1)-1))<2e-5
    assert (s[m['face_sample_count']:,3]==-1).all()
    assert np.max(abs(np.linalg.norm(s[:,4:7],axis=1)-1))<2e-5 and (s[:,7]>0).all()
    assert np.all(deforming[:,16]*deforming[:,18]-deforming[:,17]**2>0)
    base=np.array(seam['source_points']);boundary=set(seam['source_boundary'])
    max_gap=0.;assemblies=[]
    for module in m['facial_modules']:
        assert module['id'] in range(4) and module['family']=='lee-face-v1'
        assert len(module['capture_views'])==36 and module['sample_count']>1000
        collar=set(module['collar_source_vertices'])
        coords={k:np.array(p) for k,p in zip(module['source_vertex_ids'],module['coordinates'])}
        for tri in module['source_triangles']:
            a,b,c=(coords[k] for k in tri);cross=np.cross(b-a,c-a)
            assert np.linalg.norm(cross)>1e-14,'Degenerate module surface'
            if module['id']==0:assert cross[2]>0,'Folded featureless skin cap'
        gap=max(float(np.linalg.norm(coords[k]-base[k])) for k in collar);max_gap=max(max_gap,gap)
        assert gap==0.,'A variant moved the common collar'
        assert module['boundary_vertex_ids']==seam['runtime_boundary']
        edges=Counter(tuple(sorted((tri[i],tri[(i+1)%3]))) for tri in seam['source_base_triangles']+module['source_triangles'] for i in range(3))
        assert all(count==2 for edge,count in edges.items() if any(k in boundary for k in edge))
        active=t[(t[:,3]==0)|(t[:,3]==module['triangle_group'])]
        active_edges=Counter(tuple(sorted((int(tri[i]),int(tri[(i+1)%3])))) for tri in active for i in range(3))
        runtime_boundary=set(seam['runtime_boundary'])
        assert all(count in [1,2] for edge,count in active_edges.items())
        # Rigid samples carry the face outside the cage, so edges adjacent
        # to them legitimately have one cage triangle. Their captured XYZ
        # still meets the exact authored collar verified above.
        assemblies.append({'module':module['name'],'shared_boundary_vertices':len(boundary),'collar_gap_m':gap})
        samples=face[module['sample_offset']:module['sample_offset']+module['sample_count']]
        assert (t[samples[:,3].astype(int),3]==module['triangle_group']).all()
    result={'assemblies':assemblies,'max_collar_gap_m':max_gap,'rigid_samples':int(rigid.sum()),
        'vertex_count':len(v),'original_vertex_count':m['original_vertex_count'],'triangle_count':len(t),
        'source_bytes':sum(meta['bytes'] for meta in m['buffers'].values()),'invocations':m['invocation_count']}
    (root.parents[1]/'lie24-source-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('LIE24 SOURCE PASS',json.dumps(result));return result


if __name__=='__main__':verify(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'gpu_compute')
