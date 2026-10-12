"""Independent packet bounds and native rest-position verification."""
import json
from collections import Counter
from pathlib import Path
import sys
import numpy as np

def verify(root):
    root=Path(root)/'captures/face23';m=json.loads((root/'master.json').read_text());oracle=json.loads((root/'native-oracle.json').read_text())
    vertices=np.frombuffer((root/'vertices.bin').read_bytes(),dtype='<f4').reshape(-1,24)
    triangles=np.frombuffer((root/'triangles.bin').read_bytes(),dtype='<u4').reshape(-1,4)[:,:3]
    samples=np.frombuffer((root/'samples.bin').read_bytes(),dtype='<f4').reshape(-1,20)
    assert m['schema']==2 and m['vertex_stride']==96
    assert m['orbital_boundary_count']>20
    assert m['blink_corrective']=='4*b*(1-b)'
    edge_counts=Counter(tuple(sorted((int(t[i]),int(t[(i+1)%3])))) for t in triangles for i in range(3))
    assert max(edge_counts.values())==2
    boundary_ids=set(json.loads((root/'orbital-boundary.json').read_text())['vertices'])
    assert len(boundary_ids)==m['orbital_boundary_count']
    assert all(count==2 for edge,count in edge_counts.items() if any(k in boundary_ids for k in edge))
    assert np.isfinite(vertices).all() and np.isfinite(samples).all()
    assert len(samples)==m['face_sample_count']+m['eye_sample_count']
    assert m['invocation_count']==m['face_sample_count']+2*m['eye_sample_count']<=1000000
    assert triangles.max()<len(vertices)
    face=samples[:m['face_sample_count']];eye=samples[m['face_sample_count']:]
    assert ((face[:,:3]>=-1e-4)&(face[:,:3]<=1.0001)).all()
    assert np.max(abs(face[:,:3].sum(1)-1))<.0002
    assert (face[:,3]==np.floor(face[:,3])).all() and (face[:,3]>=0).all() and (face[:,3]<len(triangles)).all()
    assert (eye[:,3]==-1).all() and set(eye[:,15])=={1.,2.,3.}
    assert np.max(abs(np.linalg.norm(samples[:,4:7],axis=1)-1))<1e-5 and (samples[:,7]>0).all()
    assert ((samples[:,8]>=0)&(samples[:,8]<=1)).all() and m['lid_sample_count']>100
    assert m.get('deformation_sample_count',0)>100 and len(m.get('deformation_capture_views',[]))==4
    covariance=face[:,16:19]
    assert (covariance[:,0]>0).all() and (covariance[:,2]>0).all()
    assert (covariance[:,0]*covariance[:,2]-covariance[:,1]**2>0).all()
    baseline=oracle['cases'][0];probes=np.array(oracle['skin_probe_indices']);s=face[probes]
    actual=(vertices[triangles[s[:,3].astype(int)],:3]*s[:,:3,None]).sum(1)
    face_error=float(np.linalg.norm(actual-np.array(baseline['skin_positions']),axis=1).max())
    max_eye_error=0.
    for side,anchor in enumerate(m['anchors']):
        actual=np.array([eye[p['sample'],:3] for p in oracle['eye_probes']])+anchor
        max_eye_error=max(max_eye_error,float(np.linalg.norm(actual-np.array(baseline['eye_positions'][side]),axis=1).max()))
    assert face_error<2e-5 and max_eye_error<2e-5,(face_error,max_eye_error)
    max_pose_error=0.
    for case in oracle['cases']:
        blink=case['blink'];head=np.deg2rad(case['head_yaw'])
        points=vertices[:,:3]+vertices[:,4:7]*blink+vertices[:,8:11]*(4*blink*(1-blink))
        pivot=np.array(m['pivot']);rotation=np.array([[np.cos(head),0,np.sin(head)],[0,1,0],[-np.sin(head),0,np.cos(head)]])
        rotated=(points-pivot)@rotation.T+pivot
        points=points+(rotated-points)*vertices[:,3,None]
        actual=(points[triangles[s[:,3].astype(int)]]*s[:,:3,None]).sum(1)
        max_pose_error=max(max_pose_error,float(np.linalg.norm(actual-np.array(case['skin_positions']),axis=1).max()))
    assert max_pose_error<2e-5,max_pose_error
    result={'skin_probes':len(probes),'eye_probes_per_side':len(oracle['eye_probes']),'face_rest_error_m':face_error,'eye_rest_error_m':max_eye_error,
            'max_native_pose_error_m':max_pose_error,'welded_orbital_boundary_vertices':len(boundary_ids),
            'stored_samples':len(samples),'sample_invocations':m['invocation_count'],'eye_library_copies':1,'runtime_source_bytes':sum(v['bytes'] for v in m['buffers'].values()),'original_mesh_drawn':False}
    (root.parents[1]/'lie23-source-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('LIE23 SOURCE PASS',json.dumps(result))

if __name__=='__main__':verify(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'gpu_compute')
