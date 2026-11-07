"""Independent triangle-ray reference against actual Vulkan readback.

No LIE points or reconstruction shader are used by the reference. The source
mesh, original UV maps and declared captured GGX model are evaluated afresh.
This is a bounded material/component acceptance, not a house/mobile benchmark.
"""
import argparse,json,math,subprocess,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy.ndimage import binary_erosion
from lie_heightfield_source import read_map,sample_array,linear_albedo

def unit(a):return a/np.maximum(np.linalg.norm(a,axis=-1,keepdims=True),1e-12)
def srgb(a):return np.where(a<=.0031308,a*12.92,1.055*np.maximum(a,0)**(1/2.4)-.055)
def image(path,rgb,mask):Image.fromarray(np.uint8(np.clip(np.dstack([rgb,mask]),0,1)*255)).save(path)
def verify_one(sources,stage,out,name,prefix=None):
    prefix=prefix or "asset_"+name
    import trimesh
    from trimesh.ray.ray_pyembree import RayMeshIntersector
    spec=json.loads((sources/'manifest.json').read_text())[name];source=sources/spec['source'];doc=json.loads(source.read_text());root=source.parent
    meshdata=np.load(root/doc['mesh']['path'],allow_pickle=False);mesh=trimesh.Trimesh(vertices=meshdata['vertices'],faces=meshdata['faces'],process=False);uvs=meshdata['uv']
    n=960;packet=np.fromfile(stage/(prefix+'-parameters.bin'),dtype='<f4');eye=packet[0:3];right=packet[4:7];up=packet[8:11];forward=packet[12:15];tangent=packet[16]
    x,y=np.meshgrid((np.arange(n)+.5)/n*2-1,1-(np.arange(n)+.5)/n*2);rays=forward+right*x[...,None]*tangent+up*y[...,None]*tangent;rays=rays.reshape(-1,3);starts=np.broadcast_to(eye,rays.shape)
    ray=RayMeshIntersector(mesh);points,pixels,triangle=ray.intersects_location(starts,rays,multiple_hits=False);order=np.argsort(pixels);triangle=triangle[order];pixels=pixels[order];points=points[order]
    faces=mesh.faces[triangle];p=mesh.vertices[faces];bary=trimesh.triangles.points_to_barycentric(p,points);uv=np.einsum('ij,ijk->ik',bary,uvs[faces]);face_normals=mesh.face_normals[triangle];vn=np.einsum('ij,ijk->ik',bary,mesh.vertex_normals[faces]);geometry=unit(.7*face_normals+.3*vn)
    albedo=sample_array(linear_albedo(read_map(root/doc['maps']['Diffuse']['path'],'Diffuse'),doc['diffuse_encoding']),uv);rough=np.clip(sample_array(read_map(root/doc['maps']['Rough']['path'],'Rough'),uv),.2,.95)
    # Derivatives are obtained from each triangle's UV inverse, then an
    # independently evaluated orthonormal tangent frame (including handedness).
    q=uvs[faces];duv=np.stack([q[:,1]-q[:,0],q[:,2]-q[:,0]],axis=1);edges=np.stack([p[:,1]-p[:,0],p[:,2]-p[:,0]],axis=1);derivatives=np.linalg.solve(duv.astype('float64'),edges)
    t=unit(derivatives[:,0]-geometry*np.einsum('ij,ij->i',derivatives[:,0],geometry)[:,None]);b=unit(np.cross(geometry,t));b*=np.where(np.einsum('ij,ij->i',b,derivatives[:,1])<0,-1.,1.)[:,None]
    mapped=unit(np.clip(sample_array(read_map(root/doc['maps']['nor_gl']['path'],'nor_gl'),uv),0,1)*2-1);normal=unit(t*mapped[:,0,None]+b*mapped[:,1,None]+geometry*mapped[:,2,None])
    delta=packet[24:27]-points;distance2=(delta**2).sum(-1);l=unit(delta);v=unit(eye-points);h=unit(v+l);nl=np.where((geometry*l).sum(-1)>0,np.maximum((normal*l).sum(-1),0),0);nv=np.maximum((normal*v).sum(-1),1e-5);nh=np.maximum((normal*h).sum(-1),0);vh=np.maximum((v*h).sum(-1),0)
    fresnel=.04+.96*(1-vh)**5;a2=rough**4;denom=nh**2*(a2-1)+1;D=a2/(np.pi*denom**2)
    def lam(c):return .5*(np.sqrt(1+a2*np.maximum(1-c*c,0)/np.maximum(c*c,1e-8))-1)
    G=1/(1+lam(nv)+lam(nl));li=packet[28:31]*(packet[27]/(4*np.pi*distance2))[:,None];diffuse=(1-fresnel)[:,None]*(li*nl[:,None]/np.pi+packet[32:35]*.12);specular=li*(fresnel*D*G/(4*nv)*(nl>0))[:,None]
    linear=np.maximum((np.clip(albedo,0,1)*diffuse+specular)*packet[35],0);rgb=np.zeros((n*n,3));rgb[pixels]=srgb(linear/(1+linear));rgb=rgb.reshape(n,n,3);mask=np.zeros(n*n,bool);mask[pixels]=True;mask=mask.reshape(n,n)
    depth=np.zeros(n*n);depth[pixels]=np.einsum('ij,j->i',points-eye,forward);depth=depth.reshape(n,n)
    actual=np.fromfile(stage/(prefix+'-color.f32'),dtype='<f4').reshape(n,n,4);z=np.fromfile(stage/(prefix+'-depth.f32'),dtype='<f4').reshape(n*2,n*2)[1::2,1::2];interior=binary_erosion(mask,iterations=4);covered=actual[:,:,3]>.99;valid=interior&covered&np.isfinite(z)
    mse=float(np.mean((actual[:,:,:3][valid]-rgb[valid])**2));rmse=float(np.sqrt(np.mean((z[valid]-depth[valid])**2)));coverage=float(covered[interior].mean());psnr=-10*math.log10(max(mse,1e-15));outside=(~mask)&binary_erosion(~mask,iterations=3)
    result=dict(source_triangles=len(mesh.faces),interior_pixels=int(interior.sum()),interior_coverage=coverage,rgb_psnr_db=psnr,depth_rmse_m=rmse,outside_coverage_fraction=float((actual[:,:,3][outside]>.01).mean()),source_model='original triangle mesh, photographic albedo/roughness/OpenGL normals; GGX F0=.04; no shadows',passed=coverage>=.995 and rmse<.002 and psnr>=23)
    out.mkdir(parents=True,exist_ok=True);image(out/(prefix+'-reference.png'),rgb,mask)
    unlit=np.zeros((n*n,3));unlit[pixels]=srgb(np.clip(albedo,0,1));image(out/(prefix+'-albedo.png'),unlit.reshape(n,n,3),mask)
    (out/(prefix+'.json')).write_text(json.dumps(result,indent=2)+'\n');print(name,json.dumps(result),flush=True)
    return result

def verify(sources,stage,out,all_components=False):
    names=list(json.loads((sources/'manifest.json').read_text())) if all_components else ['mortar_bed','concrete_lintel','wood_beam'];out.mkdir(parents=True,exist_ok=True)
    cases=[(name,'quality_'+name+'_'+view) for name in names for view in ('front','back')] if all_components else [(name,'asset_'+name) for name in names]
    for name,prefix in cases:
        subprocess.run([sys.executable,__file__,'--sources',str(sources),'--stage',str(stage),'--output',str(out),'--name',name,'--prefix',prefix],check=True)
    reports={prefix:json.loads((out/(prefix+'.json')).read_text()) for name,prefix in cases};result=dict(schema='lie-photographic-construction-reference/1',passed=all(r['passed'] for r in reports.values()),components=reports,whole_object_scan=False,hero_quality_certification=False,physical_android_tested=False)
    (out/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    if not result['passed']:raise SystemExit('Source comparison failed; keep the evidence')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--stage',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--name');p.add_argument('--prefix');p.add_argument('--all-components',action='store_true');a=p.parse_args()
    if a.name:verify_one(a.sources,a.stage,a.output,a.name,a.prefix)
    else:verify(a.sources,a.stage,a.output,a.all_components)
