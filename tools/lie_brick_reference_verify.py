"""Verify captures against original triangles, independently of the capturer."""
import argparse
import json
from pathlib import Path
import struct
import numpy as np
from lie_asset_contract import inspect_bank


def verify(fixture):
    catalog=json.loads((fixture/'catalog.json').read_text()); source=json.loads((fixture/'source-surfaces.json').read_text())
    raw=(fixture/'library.bin').read_bytes();inspect_bank(raw,catalog)
    a=np.frombuffer(raw,dtype='<f4').reshape(-1,20);checked=0;maximum=0.;areas={}
    for name,meta in catalog['masters'].items():
        original=source[name];vertices=np.array(original['vertices']);tri=vertices[np.array(original['triangles'])]
        edge1,edge2=tri[:,1]-tri[:,0],tri[:,2]-tri[:,0];cross=np.cross(edge1,edge2);area=np.linalg.norm(cross,axis=1)*.5
        normals=cross/(area[:,None]*2);nodes=meta['light_nodes'];areas[name]=float(area.sum())
        if abs(sum(n['area'] for n in nodes)-area.sum())>1e-10:raise ValueError('Quadrature changes source area')
        polygon=np.array(original['triangle_polygons'])
        for i,n in enumerate(nodes):
            first,count=n['group'];group=nodes[first:first+count]
            if not first<=i<first+count or any(x['source_polygon']!=n['source_polygon'] for x in group):raise ValueError('Group crosses an authored source face/opening')
        for level in meta['levels']:
            records=a[level['start']:level['start']+level['count']]
            for s in records[np.linspace(0,len(records)-1,min(150,len(records)),dtype=int)]:
                node=nodes[int(s[9])];selected=np.where(polygon==node['source_polygon'])[0]
                t=tri[selected];e=edge1[selected];f=edge2[selected];n=normals[selected]
                delta=s[:3]-t[:,0];distance=(delta*n).sum(1);q=delta-distance[:,None]*n
                ee=(e*e).sum(1);ff=(f*f).sum(1);ef=(e*f).sum(1);den=ee*ff-ef*ef
                qe=(q*e).sum(1);qf=(q*f).sum(1);u=(ff*qe-ef*qf)/den;v=(ee*qf-ef*qe)/den
                compatible=(u>=-1e-4)&(v>=-1e-4)&(u+v<=1.0001)&(n@s[4:7]>.9999)
                if not compatible.any():raise ValueError('Captured point outside its source polygon')
                error=float(abs(distance[compatible]).min());maximum=max(maximum,error)
                if error>5e-6:raise ValueError('Capture left the source surface')
                checked+=1
        np.testing.assert_allclose(vertices.max(0)-vertices.min(0),meta['bounds_size'],atol=1e-7)
    glb=(fixture/'brick.glb').read_bytes();magic,version,length=struct.unpack_from('<III',glb)
    if (magic,version,length)!=(0x46546c67,2,len(glb)):raise ValueError('Invalid editable GLB')
    count,kind=struct.unpack_from('<II',glb,12);doc=json.loads(glb[20:20+count]);accessors=doc['accessors']
    positions=[accessors[p['attributes']['POSITION']] for mesh in doc['meshes'] for p in mesh['primitives']]
    low=np.min([p['min'] for p in positions],0);high=np.max([p['max'] for p in positions],0)
    np.testing.assert_allclose(high-low,[.24,.07,.12],atol=1e-7)
    report={'schema':'lie-brick-source-verification/1','checked_surface_samples':checked,'max_source_surface_error_m':maximum,
            'surface_areas_m2':areas,'bank_sha256':catalog['sha256'],'glb_dimensions_verified':True,'authored_face_groups_verified':True}
    (fixture/'source-verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print('BRICK SOURCE VERIFICATION PASS',json.dumps(report));return report


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);a=p.parse_args();verify(a.fixture)
