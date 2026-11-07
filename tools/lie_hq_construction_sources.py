"""Metre-scale authored components with source-preserving photographic PBR.

These are detailed authored shapes, not whole-object scans. Original files
are shared within each material directory and remain byte-for-byte intact.
"""
import argparse,json,math,shutil,urllib.request,hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image,ImageDraw
from lie_heightfield_source import read_map,sample_array,file_sha
from lie_hq_materials import verify_color_encoding
SPECS={
 'mortar_bed':dict(material='mortar',size=[.207519617,.008,.094],bevel=.0006,relief=.0005,concave=.0012),
 'mortar_head':dict(material='mortar',size=[.008,.057407229,.094],bevel=.0005,relief=.0005,concave=.001,vertical_crop=True),
 'mortar_return':dict(material='mortar',size=[.094,.008,.094],bevel=.0005,relief=.0005,concave=.001,corner=True),
 'concrete_lintel':dict(material='concrete',size=[.82,.062,.14],bevel=.0025,relief=.0015),
 'concrete_sill':dict(material='concrete',size=[.68,.042,.16],bevel=.002,relief=.0012,slope=.004),
 'concrete_plinth':dict(material='concrete',size=[1.66,.08,.22],bevel=.003,relief=.0015),
 'wood_head':dict(material='wood',size=[.61,.032,.06],bevel=.0015,relief=.00025),
 'wood_jamb':dict(material='wood',size=[.47,.032,.06],bevel=.0015,relief=.00025),
 'wood_door_jamb':dict(material='wood',size=[2.06,.05,.075],bevel=.002,relief=.0003),
 'wood_beam':dict(material='wood',size=[1.,.07,.07],bevel=.002,relief=.0003),
 'wood_door_leaf':dict(material='wood',size=[.82,2.05,.04],bevel=.0015,relief=.00025,grain_axis=1,planks=4),
 'wood_shingle':dict(material='wood',size=[.18,.012,.28],bevel=.001,relief=.00025,grain_axis=2)}
RECTANGLES={'bed':[4300,632,5524,685],'head':[3790,105,3837,443]}
def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n')
def acquire_mortar(root):
    root.mkdir(parents=True,exist_ok=True)
    req=urllib.request.Request('https://api.polyhaven.com/files/brick_wall_04',headers={'User-Agent':'LIE detailed construction; Powered by Poly Haven'})
    d=json.load(urllib.request.urlopen(req,timeout=60))
    items=[(k,d[k]['8k'][fmt]) for k,fmt in [('Diffuse','exr'),('Rough','exr'),('Displacement','png'),('nor_gl','exr')]]+[('ColorReference',d['Diffuse']['8k']['jpg']),('source',d['blend']['8k']['blend'])]
    def get(item):
        key,spec=item;path=root/(key+'.'+spec['url'].rsplit('.',1)[1])
        if not path.exists():
            req=urllib.request.Request(spec['url'],headers={'User-Agent':'LIE construction; Powered by Poly Haven'})
            with urllib.request.urlopen(req,timeout=180) as r,path.open('wb') as f:shutil.copyfileobj(r,f)
        with path.open('rb') as f:md5=hashlib.file_digest(f,'md5').hexdigest()
        if md5!=spec['md5'] or path.stat().st_size!=spec['size']:raise ValueError('source_download_hash')
        print('SOURCE',key,path.stat().st_size,flush=True);return key,{**spec,'path':path.name,'sha256':file_sha(path)}
    with ThreadPoolExecutor(max_workers=4) as pool:lock=dict(pool.map(get,items))
    write(root/'maps.lock.json',lock)
def grid(length,r,spacing):
    h=length/2;r=min(r,h*.3)
    return np.unique(np.round(np.r_[np.linspace(-h,h,max(3,math.ceil(length/spacing)+1)),np.linspace(-h,-h+2*r,9),np.linspace(h-2*r,h,9)],12))
def box(spec,height,dims,crop=None,offset=(0,0,0),uv_offset=(0,0)):
    size=np.asarray(spec['size']);half=size/2;r=spec['bevel'];g=[grid(v,r,.002 if spec.get('planks') else .0015) for v in size];points=[];triangles=[];tex=[];start=0
    for axis in range(3):
        for sign in (-1,1):
            u,v=[i for i in range(3) if i!=axis]
            if np.cross(np.eye(3)[u],np.eye(3)[v])[axis]*sign<0:u,v=v,u
            U,V=np.meshgrid(g[u],g[v]);original=np.zeros((U.size,3));original[:,axis]=half[axis]*sign;original[:,u]=U.ravel();original[:,v]=V.ravel()
            inner=half-r;core=np.clip(original,-inner,inner);delta=original-core;p=core+delta/np.maximum(np.linalg.norm(delta,axis=1,keepdims=True),1e-12)*r
            if crop is None:
                grain=spec.get('grain_axis',0);a=grain if grain in (u,v) else u;b=v if a==u else u
                uv=np.column_stack([original[:,a]/dims[0]+.5+uv_offset[0],original[:,b]/dims[1]+.5+uv_offset[1]])
            else:
                x0,y0,x1,y1=crop
                first,second=(0,1) if axis==2 else (u,v) if (size[u]>=size[v])==((x1-x0)>=(y1-y0)) else (v,u)
                uv=np.column_stack([x0+(original[:,first]/size[first]+.5)*(x1-x0),y0+(original[:,second]/size[second]+.5)*(y1-y0)])
            fade=np.clip(np.minimum.reduce([U.ravel()/size[u]+.5,.5-U.ravel()/size[u],V.ravel()/size[v]+.5,.5-V.ravel()/size[v]])/.05,0,1)**2
            h=sample_array(height,uv);p[:,axis]+=sign*(h-float(h.mean()))*spec['relief']*fade
            if axis==2 and spec.get('concave'):
                groove=0 if spec.get('vertical_crop') else 1
                p[:,2]-=sign*spec['concave']*(1-(original[:,groove]/(size[groove]/2))**2)*fade
            if spec.get('slope'):p[:,1]+=spec['slope']*(.5-p[:,2]/size[2])
            ids=np.arange(U.size).reshape(U.shape);a=ids[:-1,:-1].ravel();b=a+1;c=a+U.shape[1];e=c+1
            triangles.append(np.concatenate([np.column_stack([a,b,e]),np.column_stack([a,e,c])])+start);points.append(p+offset);tex.append(uv);start+=len(p)
    return np.concatenate(points),np.concatenate(triangles),np.concatenate(tex)
def closed(vertices,faces):
    _,idx=np.unique(np.round(vertices,8),axis=0,return_inverse=True);tri=idx[faces];edges=np.sort(np.concatenate([tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]]]),axis=1);_,n=np.unique(edges,axis=0,return_counts=True)
    return bool((n==2).all())
def join(parts):
    return np.concatenate([p[0] for p in parts]),np.concatenate([p[1]+sum(len(x[0]) for x in parts[:i]) for i,p in enumerate(parts)]),np.concatenate([p[2] for p in parts])
def prepare(materials,output):
    output.mkdir(parents=True,exist_ok=True);manifest={};loaded={}
    for key in ('mortar','wood','concrete'):
        src=materials/key;dst=output/key;dst.mkdir(exist_ok=True)
        if key=='mortar':
            lock=json.loads((src/'maps.lock.json').read_text());info=dict(title='Brick Wall 04 / selected real mortar joints',author='Dimitrios Savva; Dario Barresi; Rico Cilliers',source_url='https://polyhaven.com/a/brick_wall_04',provider_dimensions_m=[1.3899999857,1.3899999857])
        else:
            info=json.loads((src/'material-source.json').read_text());lock={k:{**v,'path':k+'.'+v['url'].rsplit('.',1)[1]} for k,v in info['maps'].items()}
        for name in ('Diffuse','Rough','Displacement','nor_gl','ColorReference'):
            a=src/lock[name]['path'];b=dst/a.name
            if not b.exists():
                try:b.hardlink_to(a)
                except OSError:shutil.copy2(a,b)
        write(dst/'material-source.json',info);write(dst/'maps.lock.json',lock);write(dst/'color-encoding.json',verify_color_encoding(dst,'srgb'))
        loaded[key]=(dst,info,lock,read_map(dst/'Displacement.png','Displacement'))
    im=Image.open(materials/'mortar/ColorReference.jpg');overlay=im.copy();draw=ImageDraw.Draw(overlay)
    for key,rect in RECTANGLES.items():im.crop(rect).save(output/('mortar-reviewed-'+key+'.png'));draw.rectangle(rect,outline=(255,30,70),width=8)
    overlay.thumbnail((1500,1500));overlay.save(output/'mortar-source-selected.png');write(output/'mortar-region-review.json',{'source_resolution':list(im.size),'rectangles_pixels':RECTANGLES,'scope':'visually selected actual joints; not chemical or physical-depth certification'})
    for name,spec in SPECS.items():
        root,info,lock,height=loaded[spec['material']];crop=None
        if spec['material']=='mortar':
            x0,y0,x1,y1=RECTANGLES['head' if spec.get('vertical_crop') else 'bed'];crop=[x0/8192,1-y1/8192,x1/8192,1-y0/8192]
        if spec.get('corner'):
            parts=[box({**spec,'size':[.094,.008,.008]},height,info['provider_dimensions_m'],crop,(0,0,-.043)),box({**spec,'size':[.008,.008,.086]},height,info['provider_dimensions_m'],crop,(-.043,0,.004))]
        elif spec.get('planks'):
            width=spec['size'][0]/spec['planks'];parts=[box({**spec,'size':[width,spec['size'][1],spec['size'][2]]},height,info['provider_dimensions_m'],None,((i-(spec['planks']-1)/2)*width,0,0),(i*.17,i*.11)) for i in range(spec['planks'])]
        else:parts=[box(spec,height,info['provider_dimensions_m'],crop)]
        component_closure=[closed(p[0],p[1]) for p in parts]
        if not all(component_closure):raise ValueError('source_not_closed: '+name)
        vertices,faces,uv=join(parts);mesh=root/(name+'.npz');np.savez_compressed(mesh,vertices=vertices.astype('<f4'),faces=faces.astype('<u4'),uv=uv.astype('<f4'))
        maps={k:{'path':lock[k]['path'],'sha256':lock[k]['sha256']} for k in ('Diffuse','Rough','nor_gl','Displacement','ColorReference')}
        source=root/(name+'.photomesh.json');write(source,{'schema':'lie-photographic-mesh/1','mesh':{'path':mesh.name,'sha256':file_sha(mesh)},'maps':maps,'diffuse_encoding':'srgb','geometry_spec':spec,'whole_object_scan':False,'source_uv_crop':crop,'closed_components':component_closure,'physical_depth_metrology':False,'mapping_note':'side/back UV assignments and profile/relief amplitude are authored; source maps untouched'})
        profile=dict(master=name,source_to_lie=np.eye(3).tolist(),meters_per_source_unit=1.,source_pivot=[0,0,0],material_zone=10,source_material_policy='declared_opaque_override',optical_material=dict(metallic=0.,transmission=0.,ior=1.5,roughness_origin='source_map'),clip_support_to_source_aabb=True,capture_optical_normals=True,max_capture_radius_m=.004)
        write(root/(name+'-profile.json'),profile)
        write(root/(name+'-provenance.json'),dict(title=name+' / '+info['title'],author='LIE authored geometry; photographic material '+info['author'],license='CC0 1.0',source_url=info['source_url'],capture_kind='detailed authored 3D component and photographed PBR, not whole-object scan',expected_sha256=file_sha(source)))
        manifest[name]=dict(source=str(source.relative_to(output)),triangles=len(faces),vertices=len(vertices),bounds_min=vertices.min(0).tolist(),bounds_max=vertices.max(0).tolist(),spec=spec,closed_components=component_closure);print('COMPONENT',name,len(faces),'triangles',flush=True)
    write(output/'manifest.json',manifest)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--materials',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--acquire-mortar',action='store_true');a=p.parse_args()
    if a.acquire_mortar:acquire_mortar(a.materials/'mortar')
    prepare(a.materials,a.output)
