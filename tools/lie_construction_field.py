"""Authored, scene-scoped finite-patch adapter for photographic assemblies.

Original capture files remain immutable. Coarse geometry is explicit profile
boxes, not a claim that these are source-triangle shadows or measured BSDFs.
"""
import argparse,hashlib,json,math,struct,copy
from pathlib import Path
import numpy as np
from lie_light_field import sources as field_sources
from lie_field_quality import solve as quality_solve

def sha(data):return hashlib.sha256(data).hexdigest()
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2)+'\n')
def sparse_csr(rows,cols,values,n):
    order=np.lexsort((cols,rows));rows=np.asarray(rows)[order];cols=np.asarray(cols)[order];values=np.asarray(values,dtype='<f4')[order];offset=np.r_[0,np.cumsum(np.bincount(rows,minlength=n))].astype('<u4');edges=np.empty((len(rows),2),dtype='<u4');edges[:,0]=cols;edges[:,1]=values.view('<u4')
    return np.array([n,len(rows),4,n+5],'<u4').tobytes()+offset.tobytes()+edges.tobytes()
from lie_field_visibility import clear_segments

def extract_materials(root):
    manifest=json.loads((root/'manifest.json').read_text());result={}
    for bank in manifest['banks']:
        path=root/'banks'/bank;c=json.loads((path/'catalog.json').read_text());raw=np.memmap(path/'library.bin',dtype='<f4',mode='r',shape=(c['sample_count'],20))
        for name,desc in c['masters'].items():
            if bank=='brick' and name not in ['scanned_brick','half_left','half_right']:continue
            level=desc['levels'][0];a=raw[level['start']:level['start']+level['count']];low=np.array(desc.get('bounds_center',[0,0,0]))-np.array(desc['bounds_size'])/2;high=low+desc['bounds_size']
            if 'modifications' in desc:
                low=np.array(desc['modifications']['bounds_min']);high=np.array(desc['modifications']['bounds_max']);pivot=(low[0]+high[0])/2;low[0]-=pivot;high[0]-=pivot
            faces=[]
            for axis in range(3):
                for sign in [1,-1]:
                    mask=(np.argmax(abs(a[:,4:7]),axis=1)==axis)&(a[:,4+axis]*sign>0);selected=a[mask] if mask.any() else a
                    faces.append({'albedo':selected[:,12:15].mean(0,dtype='float64').tolist(),'roughness':float(selected[:,10].mean(dtype='float64')),'source_samples':int(mask.sum())})
            result[bank+'/'+name]={'bounds_low':low.tolist(),'bounds_high':high.tolist(),'faces':faces,'bank_sha256':c['sha256'],'source_kind':'six authored profile faces; captured material averages; not optical shape metrology'}
    return result

def build_scene(recipe,materials,neighbors=32):
    patches=[];optics=[];owners=[];groups=[];boxes=[];face_spans=[];entries=recipe['instances']
    for owner,e in enumerate(entries):
        source=materials[e['bank']+'/'+e['master']];low=np.asarray(source['bounds_low']);high=np.asarray(source['bounds_high']);R=np.asarray(e['basis_columns'],float).T;scale=np.asarray(e['scale']);basis=R*scale;origin=np.asarray(e['origin']);normal_basis=np.linalg.inv(basis).T;center=(low+high)/2;extent=high-low;worldcenter=basis@center+origin;half=abs(basis)@(extent/2);boxes.append([worldcenter-half,worldcenter+half]);spans=[]
        for face in range(6):
            axis=face//2;sign=1 if face%2==0 else -1;u,v=[k for k in range(3) if k!=axis];counts=np.maximum(1,np.ceil(extent[[u,v]]*scale[[u,v]]/.35).astype(int));counts=np.minimum(counts,8);first=len(patches);count=int(np.prod(counts));normal=normal_basis[:,axis]*sign;normal/=np.linalg.norm(normal);area=extent[u]*scale[u]*extent[v]*scale[v]/count;mat=source['faces'][face];albedo=np.clip(np.asarray(mat['albedo'])*e['tint'],0,1);rough=np.clip(mat['roughness']+e['roughness_delta'],.2,.95)
            for row in range(counts[1]):
                for col in range(counts[0]):
                    point=center.copy();point[axis]=high[axis] if sign>0 else low[axis];point[u]=low[u]+(col+.5)*extent[u]/counts[0];point[v]=low[v]+(row+.5)*extent[v]/counts[1];point=basis@point+origin+normal*.0003
                    patches.append({'position':point.tolist(),'normal':normal.tolist(),'area':float(area),'gray_mean':1.,'material':'opaque'});optics.append([*albedo,float(rough),0,0,1.5,0,0,0,0,0,*normal,0]);owners.append(owner);groups.append([first,count])
            spans.append([first,count])
        face_spans.append(spans)
    n=len(patches)
    if not 1<=n<=8192:raise ValueError('explicit field capacity exceeded; partition assembly before capture')
    positions=np.array([p['position'] for p in patches]);normals=np.array([p['normal'] for p in patches]);areas=np.array([p['area'] for p in patches]);owner=np.array(owners);boxes=np.array(boxes)
    # Choose mutually facing candidates before nearest-neighbor truncation;
    # parallel coplanar nodes must not consume the entire neighbor allowance.
    chosen=[]
    for first in range(0,n,128):
        last=min(n,first+128);delta=positions[None,:,:]-positions[first:last,None,:];d2=(delta*delta).sum(-1)
        ca=np.einsum('ijk,ik->ij',delta,normals[first:last]);cb=-np.einsum('ijk,jk->ij',delta,normals)
        distance=np.where((ca>1e-8)&(cb>1e-8)&(d2>1e-10)&(owner[first:last,None]!=owner[None,:]),d2,np.inf)
        k=min(neighbors,n);indices=np.argpartition(distance,k-1,axis=1)[:,:k];rows=np.repeat(np.arange(first,last),k);cols=indices.ravel();keep=np.isfinite(distance[np.repeat(np.arange(last-first),k),cols]);chosen.append(np.column_stack([rows[keep],cols[keep]]))
    pairs=np.unique(np.sort(np.concatenate(chosen),axis=1),axis=0);a,b=pairs.T;delta=positions[b]-positions[a];d2=(delta*delta).sum(-1);direction=delta/np.sqrt(d2[:,None]);cosine=np.maximum((normals[a]*direction).sum(-1),0)*np.maximum(-(normals[b]*direction).sum(-1),0)
    clear=clear_segments(positions[a],positions[b],boxes,owner[a],owner[b]);a,b,d2,cosine=a[clear],b[clear],d2[clear],cosine[clear]
    rows=np.r_[a,b];cols=np.r_[b,a];values=np.r_[areas[b],areas[a]]*np.r_[cosine/d2,cosine/d2]/math.pi;sums=np.bincount(rows,weights=values,minlength=n);values/=np.maximum(1,np.maximum(sums[rows],sums[cols]));values=values.astype('<f4')
    model={'schema':1,'materials':{'opaque':{'tint_linear':[1.,1.,1.],'absorption_code':0,'radius_scale':1.}},'patches':patches,'lights':[{'position':[0.,2.,2.],'power_rgb':[40.,32.,24.],'radius':12.}], 'bounces':2,'blockers':[],'factor_normalization':'symmetric_local','field_quality':{'angular_sectors':6,'area_budget':True,'reference_area':1.0,'roughness_split':.5}}
    empty=np.zeros((1,1));packets=field_sources({'patches':patches,'materials':model['materials']},empty,optical=np.asarray(optics,'<f4'),boxes=boxes,owners=np.asarray(owners,'<u4'))
    packets['factors']=sparse_csr(cols,rows,values,n);packets['outgoing']=sparse_csr(rows,cols,values,n)
    mapping=np.array([len(entries),n,1,0],'<u4').tobytes()+np.array(face_spans,'<u4').reshape(-1,2).tobytes()+np.array(groups,'<u4').tobytes()
    return model,packets,mapping,{'nodes':n,'edges':len(values),'neighbors':neighbors,'profile_boxes':len(boxes),'surface_mapping':'explicit instance + canonical face + compatible same-face stencil','visibility':'conservative world AABB profiles; static CSR connections; not source-triangle or native Godot visibility','patch_grid_max_edge_m':.35}

def prepare(root,output):
    materials=extract_materials(root);write(output/'materials.json',{'schema':'lie-construction-field-materials/1','scene_identity':json.loads((root/'manifest.json').read_text())['scene_identity'],'materials':materials})
    for seed in [2102,7319]:
        recipe=json.loads((root/('corner-'+str(seed)+'.json')).read_text());model,packets,mapping,proof=build_scene(recipe,materials);folder=output/('corner-'+str(seed));folder.mkdir(parents=True,exist_ok=True);write(folder/'model.json',model);(folder/'mapping.bin').write_bytes(mapping);source={}
        for key,data in packets.items():(folder/(key+'.bin')).write_bytes(data);source[key]={'file':key+'.bin','bytes':len(data),'sha256':sha(data)}
        write(folder/'field.json',{'schema':'lie-construction-field/1','scene_identity':recipe['scene_identity'],'set':recipe['set'],'recipe_sha256':sha((root/('corner-'+str(seed)+'.json')).read_bytes()),'model_sha256':sha((folder/'model.json').read_bytes()),'mapping_sha256':sha(mapping),'sources':source,**proof});print(seed,proof,flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();prepare(a.root,a.output)
