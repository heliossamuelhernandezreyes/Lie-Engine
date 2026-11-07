"""Eight openly authored opaque masters, in explicit Y-up meters.

No downloaded photographs are synthesized or claimed. Grain is authored vertex
geometry/color. The common compiler, not this source writer, creates LIE data.
"""
import argparse,hashlib,json,struct
from pathlib import Path
import numpy as np
import trimesh

SPECS={
 'mortar_bed':dict(dimensions=[.207519617,.009,.05],shape='grooved_bed',color=[.30,.285,.255],roughness=.96,role='horizontal_joint'),
 'mortar_head':dict(dimensions=[.009,.057407229,.05],shape='grooved_head',color=[.30,.285,.255],roughness=.96,role='vertical_joint'),
 'mortar_corner':dict(dimensions=[.05,.009,.05],shape='corner',color=[.30,.285,.255],roughness=.96,role='joint_return'),
 'concrete_lintel':dict(dimensions=[1.,.057407229,.14],shape='beam',color=[.27,.265,.25],roughness=.9,role='opening_head'),
 'concrete_sill':dict(dimensions=[1.,.057407229,.16],shape='sill',color=[.34,.33,.30],roughness=.88,role='opening_sill'),
 'plaster_panel':dict(dimensions=[.6,.5,.025],shape='panel',color=[.61,.58,.51],roughness=.92,role='opaque_finish'),
 'timber_beam':dict(dimensions=[1.,.08,.08],shape='timber',color=[.26,.13,.055],roughness=.8,role='opaque_beam'),
 'ceramic_tile':dict(dimensions=[.18,.014,.28],shape='tile',color=[.35,.105,.055],roughness=.73,role='roof_cover')}

def glb(path,vertices,faces,colors,roughness,name):
    arrays=[np.asarray(vertices,dtype='<f4'),np.asarray(colors,dtype='<f4'),np.asarray(faces,dtype='<u4').ravel()];data=bytearray();views=[];accessors=[]
    for a,kind in zip(arrays,['VEC3','VEC4','SCALAR']):
        views.append(dict(buffer=0,byteOffset=len(data),byteLength=a.nbytes));data.extend(a.tobytes());data.extend(b'\0'*((-len(data))%4));spec=dict(bufferView=len(views)-1,componentType=5125 if kind=='SCALAR' else 5126,count=len(a),type=kind)
        if kind=='VEC3':spec.update(min=a.min(0).tolist(),max=a.max(0).tolist())
        accessors.append(spec)
    doc=dict(asset=dict(version='2.0',generator='LIE explicitly authored construction source/1'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0)],meshes=[dict(primitives=[dict(attributes=dict(POSITION=0,COLOR_0=1),indices=2,material=0)])],materials=[dict(name=name,pbrMetallicRoughness=dict(metallicFactor=0,roughnessFactor=roughness))],buffers=[dict(byteLength=len(data))],bufferViews=views,accessors=accessors)
    text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*((-len(text))%4);path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(text)+len(data))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(data),0x004e4942)+data)

def triangulate_profile(profile):
    p=np.asarray(profile,float);indices=list(range(len(p)));triangles=[]
    area=sum(p[i,0]*p[(i+1)%len(p),1]-p[(i+1)%len(p),0]*p[i,1] for i in range(len(p)))
    if area<0:indices.reverse()
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    while len(indices)>3:
        found=False
        for i,b in enumerate(indices):
            a=indices[i-1];c=indices[(i+1)%len(indices)]
            if cross(p[a],p[b],p[c])<=1e-14:continue
            if any(min(cross(p[a],p[b],p[j]),cross(p[b],p[c],p[j]),cross(p[c],p[a],p[j]))>=-1e-14 for j in indices if j not in (a,b,c)):continue
            triangles.append([a,b,c]);indices.pop(i);found=True;break
        if not found:raise ValueError('source_profile_cannot_triangulate')
    triangles.append(indices);return triangles

def loft(length,profile,axis='x',steps=48):
    profile=np.array(profile,float);n=len(profile);vertices=[];faces=[]
    for i in range(steps+1):
        for a,b in profile:vertices.append([length*(i/steps-.5),a,b] if axis=='x' else [a,length*(i/steps-.5),b])
    for i in range(steps):
        for j in range(n):
            a=i*n+j;b=i*n+(j+1)%n;c=b+n;d=a+n;faces.extend([[a,b,c],[a,c,d]])
    cap=triangulate_profile(profile)
    for end in (0,steps):
        for tri in cap:faces.append([end*n+j for j in (tri[::-1] if end==0 else tri)])
    mesh=trimesh.Trimesh(vertices=vertices,faces=faces,process=False);
    mesh.metadata['support_groups']=[[2*(i*n+j)+k for i in range(steps) for k in (0,1)] for j in range(n)]+[list(range(2*steps*n,2*steps*n+len(cap))),list(range(2*steps*n+len(cap),2*steps*n+2*len(cap)))]
    if mesh.volume<0:mesh.invert()
    return mesh

def mesh_for(spec):
    x,y,z=spec['dimensions'];shape=spec['shape']
    if shape in ('grooved_bed','grooved_head'):
        width=y if shape=='grooved_bed' else x;profile=[[-width/2,-z/2],[width/2,-z/2]]+[[v,z/2-.0012*(1-(v/(width/2))**2)] for v in np.linspace(width/2,-width/2,11)]
        mesh=loft(x if shape=='grooved_bed' else y,profile,'x' if shape=='grooved_bed' else 'y',48 if shape=='grooved_bed' else 20)
    elif shape=='corner':
        # Closed L footprint, extruded vertically. Exact simple polygon ears.
        points=np.array([[-x/2,-z/2],[x/2,-z/2],[x/2,-z/2+.01],[-x/2+.01,-z/2+.01],[-x/2+.01,z/2],[-x/2,z/2]])
        vertices=np.array([[a,h,b] for h in (-y/2,y/2) for a,b in points]);cap=[[0,1,2],[0,2,3],[0,3,5],[3,4,5]];faces=[]
        for f in cap:faces.extend([f,[v+6 for v in f[::-1]]])
        for j in range(6):k=(j+1)%6;faces.extend([[j,k+6,k],[j,j+6,k+6]])
        mesh=trimesh.Trimesh(vertices=vertices,faces=faces,process=False);
        mesh.metadata['support_groups']=[[0,2],[4,6],[1,3],[5,7]]+[[8+2*j,9+2*j] for j in range(6)]
        if mesh.volume<0:mesh.invert()
    elif shape=='tile':
        # Shallow curved roof tile with finite thickness and closed edges.
        profile=[[v,-y/2+.006*(1-(v/(x/2))**2)] for v in np.linspace(-x/2,x/2,13)]+[[v,y/2+.006*(1-(v/(x/2))**2)] for v in np.linspace(x/2,-x/2,13)]
        mesh=loft(z,profile,'x',24);mesh.vertices=mesh.vertices[:,[1,2,0]];
        if mesh.volume<0:mesh.invert()
    else:
        bevel=min(.002,min(y,z)*.12);profile=[[-y/2+bevel,-z/2], [y/2-bevel,-z/2],[y/2,-z/2+bevel],[y/2,z/2-bevel],[y/2-bevel,z/2],[-y/2+bevel,z/2],[-y/2,z/2-bevel],[-y/2,-z/2+bevel]]
        if shape=='sill':profile=[[a-.008*(b/z+.5)*max(0,(a+y/2)/y),b] for a,b in profile]
        mesh=loft(x,profile,steps=80 if shape=='timber' else 32)
    if not mesh.is_watertight or not mesh.is_winding_consistent:raise ValueError('authored_source_not_closed')
    return mesh

def generate(out):
    out.mkdir(parents=True,exist_ok=True);manifest={}
    for name,spec in SPECS.items():
        mesh=mesh_for(spec);p=np.asarray(mesh.vertices);grain=np.sin(p[:,0]*719+p[:,1]*1231+p[:,2]*937)*np.sin(p[:,0]*151+p[:,2]*273)
        if spec['shape']=='timber':grain=.65*np.sin(p[:,2]*1271+p[:,1]*39+np.sin(p[:,0]*7))+.35*np.sin(p[:,2]*373)
        colors=np.column_stack([np.clip(np.array(spec['color'])*(1+grain[:,None]*.055),0,1),np.ones(len(p))]);path=out/(name+'.glb');glb(path,p,mesh.faces,colors,spec['roughness'],name)
        profile=dict(master=name,source_to_lie=np.eye(3).tolist(),meters_per_source_unit=1.,source_pivot=[0,0,0],material_zone=4,source_material_policy='preserve_source',clip_support_to_source_aabb=True,max_capture_radius_m=.08,source_planar_groups=[mesh.metadata['support_groups']],optical_material=dict(metallic=0.,transmission=0.,ior=1.5,roughness_origin='authored'))
        provenance=dict(title='LIE authored construction kit / '+name,author='Helios Samuel / LIE project',license='CC0 1.0',source_url='https://github.com/heliossamuelhernandezreyes/Lie-Engine',capture_kind='explicitly authored closed mesh and vertex material; not photographed or scanned',expected_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),authored_generator='lie_construction_sources/1',spec=spec)
        (out/(name+'-profile.json')).write_text(json.dumps(profile,indent=2)+'\n');(out/(name+'-provenance.json')).write_text(json.dumps(provenance,indent=2)+'\n');manifest[name]=dict(**spec,source_sha256=provenance['expected_sha256'],triangles=len(mesh.faces),bounds_min=p.min(0).tolist(),bounds_max=p.max(0).tolist(),closed=True,scale_policy='authored_positive')
    (out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');return manifest
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();generate(a.output)
