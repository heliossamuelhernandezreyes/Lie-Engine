"""Independent source triangle, GLB and 4K material acceptance for robot masters."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import numpy as np
from PIL import Image
from lie28_verify_captures import bilinear

def verify(root,materials,bank_name='robot_modular'):
    root,materials=Path(root),Path(materials)
    bank=root/'captures'/bank_name
    catalog=json.loads((bank/'catalog.json').read_text());source=json.loads((root/'assets/robot_modular/source-surfaces.json').read_text())
    raw=(bank/'library.bin').read_bytes();assert len(raw)==catalog['bytes']==catalog['sample_count']*96<=64*1024*1024
    assert hashlib.sha256(raw).hexdigest()==catalog['sha256'];data=np.frombuffer(raw,dtype='<f4').reshape(-1,24)
    assert np.isfinite(data).all() and (data[:,3]>0).all()
    assert np.max(abs(np.linalg.norm(data[:,4:7],axis=1)-1))<1e-5
    assert np.max(abs(np.linalg.norm(data[:,20:23],axis=1)-1))<1e-5
    assert ((data[:,12:15]>=0)&(data[:,12:15]<=1)).all() and ((data[:,11]>=0)&(data[:,11]<=1)).all()
    assert (data[:,16:18]<=data[:,18:20]).all()
    maps={}
    for item in catalog['materials']:
        path=materials/item['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']
        pixels=np.asarray(Image.open(path).convert('RGB'),dtype=np.float64)/255
        assert pixels.shape[:2]==(4096,4096),(item['file'],'not 4K')
        maps[(item['asset'],item['map'])]=pixels
    max_surface=0.;max_material=0.;points_checked=0;material_checked=0
    for name,metadata in catalog['masters'].items():
        mesh=source[name];vertices=np.array(mesh['vertices']);triangles=vertices[np.array(mesh['triangles'])]
        glb=(root/'assets/robot_modular'/f'{name}.glb').read_bytes();magic,version,length=struct.unpack_from('<III',glb);assert magic==0x46546c67 and version==2 and length==len(glb)
        count,kind=struct.unpack_from('<II',glb,12);assert kind==0x4e4f534a;gltf=json.loads(glb[20:20+count]);accessors=gltf['accessors']
        positions=[accessors[p['attributes']['POSITION']] for m in gltf['meshes'] for p in m['primitives']]
        assert np.max(abs(np.min([p['min'] for p in positions],axis=0)-(vertices.min(axis=0)+mesh['origin_offset'])))<1e-6
        assert np.max(abs(np.max([p['max'] for p in positions],axis=0)-(vertices.max(axis=0)+mesh['origin_offset'])))<1e-6
        if name.startswith('plate'):assert all('bufferView' in image for image in gltf['images']) and len(gltf['images'])>=3
        assert len(metadata['capture_views'])==36 and all(v['valid_pixels']>0 for v in metadata['capture_views'])
        level=metadata['levels'][0];samples=data[level['start']:level['start']+level['count']]
        a=triangles[:,0];e=triangles[:,1]-a;f=triangles[:,2]-a;n=np.cross(e,f);n/=np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15)
        ee=(e*e).sum(axis=1);ff=(f*f).sum(axis=1);ef=(e*f).sum(axis=1);den=ee*ff-ef*ef
        for i in np.linspace(0,len(samples)-1,120,dtype=int):
            s=samples[i];delta=s[:3]-a;distance=(delta*n).sum(axis=1);q=delta-distance[:,None]*n;qe=(q*e).sum(axis=1);qf=(q*f).sum(axis=1)
            y=(ff*qe-ef*qf)/np.maximum(den,1e-20);z=(ee*qf-ef*qe)/np.maximum(den,1e-20)
            # At a shared edge multiple triangles own the same position. Require
            # a matching independently computed source normal before choosing.
            inside=(y>=-1e-4)&(z>=-1e-4)&(y+z<=1.0001)&(den>1e-20)&(np.array(mesh['zones'])==int(s[8]))&((n@s[4:7])>.999)
            assert inside.any(),(name,i,'outside source triangles')
            k=np.where(inside)[0][np.argmin(abs(distance[inside]))];error=float(abs(distance[k]));max_surface=max(max_surface,error);assert error<5e-6
            assert np.dot(n[k],s[4:7])>.999 and np.dot(s[20:23],s[4:7])>.29
            axis=np.argmax(abs(s[4:7]));j0,j1=[(2,1),(0,2),(0,1)][axis]
            assert s[16]-1e-5<=s[j0]<=s[18]+1e-5 and s[17]-1e-5<=s[j1]<=s[19]+1e-5
            points_checked+=1
            if int(s[8]) in (1,5):
                tex=np.array(mesh['triangle_uvs'][k]);uv=tex[0]*(1-y[k]-z[k])+tex[1]*y[k]+tex[2]*z[k];asset='blue_metal_plate' if int(s[8])==1 else 'metal_plate_02'
                srgb=bilinear(maps[(asset,'Diffuse')],uv);color=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
                rough=np.clip(bilinear(maps[(asset,'Rough')],uv)[0],.18,.92);metal=bilinear(maps[(asset,'arm' if int(s[8])==1 else 'Metal')],uv)[2 if int(s[8])==1 else 0]
                error=max(float(np.max(abs(color-s[12:15]))),float(abs(rough-s[10])),float(abs(metal-s[11])));max_material=max(max_material,error);assert error<.0004,(name,'source material',error)
                material_checked+=1
    shaft_faces=[]
    if bank_name=='robot_refined':
        for level in catalog['masters']['shaft']['levels']:
            samples=data[level['start']:level['start']+level['count']];radial=np.linalg.norm(samples[:,[0,2]],axis=1)
            band=samples[(abs(samples[:,1])<.025)&(abs(samples[:,5])<.01)&(abs(radial-.018)<.0001)]
            angles=np.unique(np.round(np.mod(np.arctan2(band[:,6],band[:,4]),2*np.pi),4));gap=np.diff(np.r_[angles,angles[:1]+2*np.pi]).max()
            assert len(angles)>=48 and gap<.132,(len(angles),gap,'shaft barrel facet coverage')
            shaft_faces.append(dict(normals=len(angles),maximum_angular_gap_rad=float(gap)))
    result=dict(masters=len(catalog['masters']),sample_count=len(data),library_bytes=len(raw),source_points=points_checked,source_material_points=material_checked,max_surface_error_m=max_surface,max_material_error=max_material,verified_glbs=len(catalog['masters']),maps_4k=len(maps),shaft_barrel_coverage=shaft_faces,original_mesh_drawn=False)
    (root/'robot-capture-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('ROBOT CAPTURE PASS',json.dumps(result));return result

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]/'gpu_compute')
    parser.add_argument('--materials',type=Path,required=True)
    parser.add_argument('--bank-name',default='robot_modular')
    args=parser.parse_args();verify(args.root,args.materials,args.bank_name)
