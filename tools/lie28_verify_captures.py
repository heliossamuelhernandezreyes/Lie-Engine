"""Independent geometry, material and complementary fracture acceptance."""
import hashlib
import json
from pathlib import Path
import sys
import struct
import numpy as np
from PIL import Image

SEEDS=np.array([[-.055,-.015,-.014],[.055,-.017,.008],[-.065,.015,.011],[.063,.016,-.009]])

def bilinear(pixels, uv):
    # PIL origin is top-left. UV origin is bottom-left, with pixel-centre sampling.
    h,w=pixels.shape[:2];x=(uv[0]%1)*w-.5;y=(1-uv[1]%1)*h-.5
    a,b=int(np.floor(x)),int(np.floor(y));u,v=x-a,y-b
    return pixels[b%h,a%w]*(1-u)*(1-v)+pixels[b%h,(a+1)%w]*u*(1-v)+pixels[(b+1)%h,a%w]*(1-u)*v+pixels[(b+1)%h,(a+1)%w]*u*v

def verify(root, materials):
    root,materials=Path(root),Path(materials)
    catalog=json.loads((root/'captures/building28/catalog.json').read_text())
    source=json.loads((root/'assets/lie28/source-surfaces.json').read_text())
    raw=(root/'captures/building28/library.bin').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==catalog['sha256']
    assert len(raw)==catalog['bytes']==catalog['sample_count']*80 and len(raw)<=64*1024*1024
    data=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
    assert np.isfinite(data).all() and (data[:,3]>0).all()
    assert np.max(abs(np.linalg.norm(data[:,4:7],axis=1)-1))<1e-5
    assert ((data[:,12:15]>=0)&(data[:,12:15]<=1)).all()
    assert ((data[:,10]>=.2)&(data[:,10]<=.98)).all()
    assert (data[:,16:18]<=data[:,18:20]).all()
    maps={}
    for item in catalog['materials']:
        path=materials/item['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']
        maps[(item['asset'],item['map'])]=np.asarray(Image.open(path).convert('RGB'),dtype=np.float64)/255
    volumes={};surface_error=0.;material_error=0.;points_checked=0;material_checked=0
    for name,metadata in catalog['masters'].items():
        mesh=source[name];vertices=np.array(mesh['vertices']);triangles=vertices[np.array(mesh['triangles'])]
        glb=(root/'assets/lie28'/f'{name}.glb').read_bytes()
        magic,version,length=struct.unpack_from('<III',glb)
        assert magic==0x46546c67 and version==2 and length==len(glb)
        count,kind=struct.unpack_from('<II',glb,12);assert kind==0x4e4f534a
        gltf=json.loads(glb[20:20+count]);accessors=gltf['accessors']
        positions=[accessors[p['attributes']['POSITION']] for m in gltf['meshes'] for p in m['primitives']]
        low=np.min([p['min'] for p in positions],axis=0);high=np.max([p['max'] for p in positions],axis=0)
        assert np.max(abs(low-(vertices.min(axis=0)+mesh['origin_offset'])))<1e-6,(name,'GLB axes/origin')
        assert np.max(abs(high-(vertices.max(axis=0)+mesh['origin_offset'])))<1e-6,(name,'GLB axes/origin')
        assert len(gltf.get('images',[]))>=2 and all('bufferView' in image for image in gltf['images']),(name,'embedded material maps')
        volumes[name]=abs(np.einsum('ij,ij->i',triangles[:,0],np.cross(triangles[:,1],triangles[:,2])).sum()/6)
        a=triangles[:,0];e=triangles[:,1]-a;f=triangles[:,2]-a
        n=np.cross(e,f);n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15)
        ee=(e*e).sum(axis=1);ff=(f*f).sum(axis=1);ef=(e*f).sum(axis=1);den=ee*ff-ef*ef
        level=metadata['levels'][0];samples=data[level['start']:level['start']+level['count']]
        for level in metadata['levels']:
            assert 0<=level['start']<len(data) and 0<level['count']<=len(data)-level['start']
        assert len(metadata['capture_views'])==36 and all(v['valid_pixels']>0 for v in metadata['capture_views'])
        for i in np.linspace(0,len(samples)-1,100,dtype=int):
            s=samples[i];delta=s[:3]-a;distance=(delta*n).sum(axis=1);q=delta-distance[:,None]*n
            qe=(q*e).sum(axis=1);qf=(q*f).sum(axis=1)
            y=(ff*qe-ef*qf)/np.maximum(den,1e-20);z=(ee*qf-ef*qe)/np.maximum(den,1e-20)
            inside=(y>=-1e-4)&(z>=-1e-4)&(y+z<=1.0001)&(den>1e-20)&(np.array(mesh['zones'])==int(s[8]))&(np.array(mesh['cells'])==int(s[9]))
            assert inside.any(),(name,i,'outside source triangles')
            k=np.where(inside)[0][np.argmin(abs(distance[inside]))]
            error=float(abs(distance[k]));surface_error=max(surface_error,error);assert error<5e-6,(name,error)
            assert np.dot(n[k],s[4:7])>.999,(name,'source normal mismatch')
            points_checked+=1
            if int(s[8]) in (3,5,7):
                uvs=np.array(mesh['triangle_uvs'][k]);uv=uvs[0]*(1-y[k]-z[k])+uvs[1]*y[k]+uvs[2]*z[k]
                asset='factory_brick' if int(s[8])==3 else 'concrete'
                srgb=bilinear(maps[(asset,'Diffuse')],uv)
                color=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
                rough=np.clip(bilinear(maps[(asset,'Rough')],uv)[0],.2,.98)
                error=max(float(np.max(abs(color-s[12:15]))),float(abs(rough-s[10])))
                material_error=max(material_error,error);assert error<.0002,(name,'source material mismatch',error)
                material_checked+=1
        if name.startswith('fragment'):
            assert (samples[:,8]==6).any(),(name,'missing cut surface')
            world=vertices+mesh['origin_offset'];index=int(name.split('_')[1])
            distances=((world[:,None,:]-SEEDS[None,:,:])**2).sum(axis=2)
            assert (distances[:,index,None]<=distances+1e-7).all(),(name,'outside own Voronoi cell')
            assert (abs(world)<=np.array([.12,.035,.06])+1e-6).all()
            # Closed triangle boundaries: each undirected edge belongs to two faces.
            edges={}
            for tri in mesh['triangles']:
                for a,b in zip(tri,(tri[1],tri[2],tri[0])):
                    key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
            assert all(count==2 for count in edges.values()),(name,'open fracture mesh')
    partition_error=abs(sum(volumes[f'fragment_{i}'] for i in range(4))-volumes['brick'])
    assert partition_error<1e-8,partition_error
    # No source triangle can cover the clear centre of these openings.
    for name in ('window_wall','door_base','door_head'):
        mesh=source[name];triangles=np.array(mesh['vertices'])[np.array(mesh['triangles'])]
        hole=catalog['masters'][name]['opening'];cx=(hole[0]+hole[1])/2;cy=(hole[2]+hole[3])/2
        lower=triangles[:,:,:2].min(axis=1);upper=triangles[:,:,:2].max(axis=1)
        assert not ((lower[:,0]<cx)&(upper[:,0]>cx)&(lower[:,1]<cy)&(upper[:,1]>cy)).any(),name
    result=dict(masters=len(catalog['masters']),sample_count=len(data),library_bytes=len(raw),checked_source_points=points_checked,
        checked_material_points=material_checked,max_surface_error_m=surface_error,max_material_error=material_error,
        brick_volume_m3=volumes['brick'],fragment_volume_error_m3=partition_error,closed_fragments=4,verified_glb_masters=len(catalog['masters']),original_mesh_drawn=False)
    (root/'lie28-capture-verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print('LIE28 CAPTURE PASS',json.dumps(result))
    return result

if __name__=='__main__':verify(sys.argv[1],sys.argv[2])
