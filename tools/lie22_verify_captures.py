"""Independent surface/volume acceptance for neutral captured masters."""
import json
import struct
from pathlib import Path
import sys
import numpy as np


def verify(root):
    root=Path(root);catalog=json.loads((root/'captures/modular22/catalog.json').read_text())
    surfaces=json.loads((root/'assets/lie22/source-surfaces.json').read_text())
    data=np.frombuffer((root/'captures/modular22/library.bin').read_bytes(),dtype='<f4').reshape(-1,12)
    assert np.isfinite(data).all() and (data[:,3]>0).all()
    assert np.max(np.abs(np.linalg.norm(data[:,4:7],axis=1)-1))<1e-5
    assert ((data[:,7]>=0)&(data[:,7]<=1)).all()
    assert (data[:,8]==np.floor(data[:,8])).all() and ((data[:,8]>=0)&(data[:,8]<=7)).all()
    max_surface_error=0.;volumes={}
    for name,metadata in catalog['masters'].items():
        source=surfaces[name];vertices=np.array(source['vertices']);triangles=vertices[np.array(source['triangles'])]
        volumes[name]=abs(np.einsum('ij,ij->i',triangles[:,0],np.cross(triangles[:,1],triangles[:,2])).sum()/6)
        a=triangles[:,0];e=triangles[:,1]-a;f=triangles[:,2]-a
        n=np.cross(e,f);n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15)
        ee=(e*e).sum(axis=1);ff=(f*f).sum(axis=1);ef=(e*f).sum(axis=1);den=ee*ff-ef*ef
        level=metadata['levels'][0];samples=data[level['start']:level['start']+level['count']]
        for i in np.linspace(0,len(samples)-1,80,dtype=int):
            p=samples[i,:3];delta=p-a;distance=(delta*n).sum(axis=1);q=delta-distance[:,None]*n
            qe=(q*e).sum(axis=1);qf=(q*f).sum(axis=1)
            y=(ff*qe-ef*qf)/np.maximum(den,1e-20);z=(ee*qf-ef*qe)/np.maximum(den,1e-20)
            inside=(y>=-1e-4)&(z>=-1e-4)&(y+z<=1.0001)&(den>1e-20)
            assert inside.any(),(name,i,'no source triangle')
            error=np.min(np.abs(distance[inside]));max_surface_error=max(max_surface_error,float(error))
            assert error<5e-6,(name,i,error)
        if name.startswith('fragment'):
            assert (samples[:,8]==6).any(),(name,'missing cut interior')
            assert np.all(np.abs(vertices)<=np.array([.12,.0325,.055])+1e-6)
    partition_error=abs(sum(volumes['fragment_%d'%i] for i in range(4))-volumes['brick'])
    assert partition_error<1e-8,partition_error
    result={'masters':len(catalog['masters']),'sample_count':len(data),'library_bytes':data.nbytes,
            'checked_source_points':len(catalog['masters'])*80,'max_surface_error_m':max_surface_error,
            'brick_volume_m3':volumes['brick'],'fragment_volume_error_m3':partition_error,'original_mesh_drawn':False}
    (root/'lie22-capture-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('LIE22 CAPTURE PASS',json.dumps(result))

if __name__=='__main__':verify(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'gpu_compute')
