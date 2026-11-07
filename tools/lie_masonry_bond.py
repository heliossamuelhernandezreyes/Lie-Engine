"""Running bond, four proper rigid orientations and authored material variation.

One immutable whole scan plus two genuine saw-cut derivatives. No reflection,
scaling or deformation of a brick. Mortar is a separate authored asset.
"""
import argparse,hashlib,json,math,shutil
from pathlib import Path
import numpy as np
from lie_scanned_masonry import noise as base_noise,canonical_bytes,recipe as legacy_recipe
from lie_asset_contract import inspect_bank
from lie_brick02_capture_scan import capture,load_source,_sample_mesh

VERSION='lie-masonry-running-bond/2'
def noise(*key):
    h=round(base_noise(*key)*4294967295)
    h=((h^(h>>16))*0x7feb352d)&0xffffffff;h=((h^(h>>15))*0x846ca68b)&0xffffffff
    return (h^(h>>16))/4294967295.
FLIPS=(np.diag([1.,1,1]),np.diag([-1.,1,-1]),np.diag([1.,-1,-1]),np.diag([-1.,-1,1]))
def turn(axis,angle):
    c,s=math.cos(angle),math.sin(angle)
    if axis==0:return np.array([[1,0,0],[0,c,-s],[0,s,c]])
    if axis==1:return np.array([[c,0,s],[0,1,0],[-s,0,c]])
    return np.array([[c,-s,0],[s,c,0],[0,0,1]])

def row_cells(columns,row):
    n=columns*2
    return [(i,i+2) for i in range(0,n,2)] if row%2==0 else [(0,1)]+[(i,i+2) for i in range(1,n-1,2)]+[(n-1,n)]
def subtract(interval,holes):
    result=[interval]
    for low,high in holes:
        next=[]
        for a,b in result:
            if high<=a or low>=b:next.append((a,b));continue
            if a<low:next.append((a,low))
            if b>high:next.append((high,b))
        result=next
    return result

def recipe(size,bank_sha,seed=2102,mode='wall',varied=True):
    if type(seed) is not int or not 0<=seed<=0xffffffff:raise ValueError('seed_uint32')
    if mode not in ('brick','wall','house') or type(varied) is not bool:raise ValueError('recipe_mode')
    x,y,z=[round(float(v),9) for v in size];g=.008;pitch=x+g;half=pitch/2;py=y+g
    rows=12 if mode=='wall' else 36;columns=12 if mode=='wall' else 22;side_columns=16;W=columns*pitch-g;H=rows*py-g;D=side_columns*pitch-g+2*(z+g)
    entries=[];openings=[]
    def add(master,origin,R=np.eye(3),scale=(1,1,1),id='',**extra):
        entries.append(dict(master=master,origin=list(origin),yaw=0.,basis_columns=np.asarray(R).T.tolist(),scale=list(scale),id=id,**extra))
    if mode=='brick':
        add('scanned_brick',(0,0,0),id='brick/0',orientation=0,tint=[1,1,1],roughness_delta=0.);bounds=[x,y,z]
    else:
        sections=[(columns,0,0,0)] if mode=='wall' else [(columns,0,D/2-z/2,0),(columns,0,-D/2+z/2,math.pi),(side_columns,W/2-z/2,0,math.pi/2),(side_columns,-W/2+z/2,0,-math.pi/2)]
        for section,(n,cx,cz,yaw) in enumerate(sections):
            holes=[(4,2,3,4,'window')] if mode=='wall' else [(8+int(noise(seed,section,0,0,8)*2),0,4,29,'door')] if section==0 else [(3+int(noise(seed,section,0,0,9)*3),13,5,12,'window')]
            for c,r,w,h,kind in holes:openings.append(dict(section=section,column=c,row=r,columns=w,rows=h,kind=kind,clear_width_m=w*pitch-g,clear_height_m=h*py-g))
            width=n*pitch-g;wall_R=turn(1,yaw)
            for row in range(rows):
                cuts=[(2*c,2*(c+w)) for c,r,w,h,_ in holes if r<=row<r+h]
                for begin,end in row_cells(n,row):
                    for a,b in subtract((begin,end),cuts):
                        code=min(3,int(noise(seed,section,row,a,30)*4)) if varied else 0
                        eps=[(noise(seed,section,row,a,31+i)-.5)*math.radians(v) for i,v in enumerate((.7,.8,.45))] if varied else [0,0,0]
                        R=wall_R@turn(0,eps[0])@turn(1,eps[1])@turn(2,eps[2])@FLIPS[code]
                        master='scanned_brick';cut_face=None
                        if b-a==1:
                            # The cut end belongs at the shortened side. A
                            # 180-degree turn swaps the correct source half.
                            cut_right=(a==begin) if end-begin==2 else a==0
                            original_right=cut_right if FLIPS[code][0,0]>0 else not cut_right
                            master='half_left' if original_right else 'half_right';cut_face='right' if cut_right else 'left'
                        local=np.array([(a+b)*half/2-width/2-g/2,row*py+y/2,0.])
                        jitter=np.array([(noise(seed,section,row,a,40+i)-.5)*.0006 for i in range(3)]) if varied else np.zeros(3)
                        pos=wall_R@(local+jitter)+[cx,0,cz]
                        gain=.88+.24*noise(seed,section,row,a,50) if varied else 1.;warm=(noise(seed,section,row,a,51)-.5)*.10 if varied else 0.
                        tint=[gain*(1+warm),gain*(1+warm*.15),gain*(1-warm*.75)]
                        rough=(noise(seed,section,row,a,52)-.5)*.09 if varied else 0.
                        add(master,pos,R,id=f'brick/{section}/{row}/{a}',orientation=code,tint=tint,roughness_delta=rough,section=section,row=row,interval_half_cells=[a,b],cut_face=cut_face)
                # Authored recessed mortar, split around openings and into
                # short two-brick spans to bound the existing splat footprint.
                for first,last in subtract((0,2*n),cuts):
                    for a in range(first,last,4):
                        b=min(a+4,last);length=(b-a)*half-g
                        pos=wall_R@np.array([(a+b)*half/2-width/2-g/2,row*py+y/2,-.007])+[cx,0,cz]
                        add('authored_box',pos,wall_R,(length,py,z-.014),id=f'mortar/{section}/{row}/{a}',section=section,row=row,interval_half_cells=[a,b])
        bounds=[W,H,z if mode=='wall' else D]
        if mode=='house':
            add('authored_box',(0,-.025,0),scale=(W+.08,.05,D+.08),id='floor');add('authored_roof',(0,H+.045,0),scale=(W+.16,.09,D+.16),id='roof')
    return dict(schema=VERSION,seed=seed,mode=mode,bank_sha256=bank_sha,brick_bounds_m=[x,y,z],bounds_m=bounds,bond='half-lap running bond',joint_m=g,
                source_color_variation=varied,variation=dict(brightness=[.88,1.12],warmth=[-.05,.05],roughness_delta=[-.045,.045],jitter_mm=.3,orientation='proper D2 rotations: identity, Y180, X180, Z180; no reflections',micro_rotation_degrees=[.35,.4,.225]),
                opening_rule='subtract half-module intervals from brick AND mortar; saw-cut sources close boundary pieces',openings=openings,instances=entries)

def half_bank(source,base_provenance,out,name):
    info=json.loads((source.parent/'cuts.json').read_text())[name];identity=json.loads(base_provenance.read_text());identity.update(title=identity['title']+' / '+name+' saw-cut derivative',expected_sha256=info['sha256'],capture_kind='original scan clipped rigidly; exposed cut face explicitly authored',modifications=info)
    out.mkdir(parents=True,exist_ok=True);p=out/'provenance.json';p.write_text(json.dumps(identity,indent=2)+'\n')
    pivot=[(info['bounds_min'][0]+info['bounds_max'][0])/2,0,0]
    profile=dict(master=name,source_to_lie=np.eye(3).tolist(),meters_per_source_unit=1.,source_pivot=pivot,material_zone=3,source_material_policy='preserve_source',optical_material=dict(metallic=0.,transmission=0.,ior=1.5,roughness_origin='source_factor'),material_provenance=info)
    catalog=capture(source,p,out,counts=(40000,8000,2048),seed=7102,asset_profile=profile);raw=bytearray((out/'library.bin').read_bytes());meshes=load_source(source);areas=np.array([m.area for m in meshes])
    for i,count in enumerate((512,128)):
        rng=np.random.default_rng(7710+i);items=[]
        for m,n in zip(meshes,rng.multinomial(count,areas/areas.sum())):
            if n:items.append(_sample_mesh(m,n,rng,np.arange(3),1.,np.array(pivot),float(np.clip(1.55*np.sqrt(m.area/n),.0002,.04)),np.eye(3)))
        a=np.concatenate(items);rng.shuffle(a);catalog['masters'][name]['levels'].append(dict(start=len(raw)//80,count=len(a)));raw.extend(a.astype('<f4').tobytes())
    master=catalog['masters'][name];master.update(bounds_size=[info['bounds_max'][i]-info['bounds_min'][i] for i in range(3)],bounds_center=[0,0,0],modifications=info,cut_clip=dict(sense=1 if name=='half_left' else -1,plane_m=info['cut_plane_m']-pivot[0]))
    catalog.update(sha256=hashlib.sha256(raw).hexdigest(),sample_count=len(raw)//80,bytes=len(raw));(out/'library.bin').write_bytes(raw);(out/'catalog.json').write_bytes(canonical_bytes(catalog));(out/'asset-contract.json').write_bytes(canonical_bytes(inspect_bank(raw,catalog)))
    return raw,master

def build(base,half_sources,out,seeds=(2102,7319)):
    out.mkdir(parents=True,exist_ok=True);catalog=json.loads((base/'catalog.json').read_text());raw=bytearray((base/'library.bin').read_bytes());original_sha=catalog['sha256']
    # Additional 1024-sample whole-brick LOD. Original source bytes stay intact.
    master=catalog['masters']['scanned_brick'];lod=master['levels'][2];a=np.frombuffer(raw,dtype='<f4').reshape(-1,20)[lod['start']:lod['start']+lod['count']:4].copy();a[:,3]*=2
    for axis,(u,v) in enumerate(((2,1),(0,2),(0,1))):
        m=np.argmax(abs(a[:,4:7]),axis=1)==axis;coords=a[m][:,[u,v]];a[m,16:18]=coords-2.3*a[m,3,None];a[m,18:20]=coords+2.3*a[m,3,None]
    master['levels'].insert(3,dict(start=len(raw)//80,count=len(a)));master['lod_names']=['hero','near','wall','house1024','coarse512','distant128'];raw.extend(a.tobytes())
    for name in ('half_left','half_right'):
        half,desc=half_bank(half_sources/(name+'.glb'),base/'provenance.json',out.parent/('capture-'+name),name);offset=len(raw)//80
        for level in desc['levels']:level['start']+=offset
        catalog['masters'][name]=desc;raw.extend(half)
    if len(raw)>64*1024*1024:raise ValueError('shared_bank_byte_budget')
    catalog.update(sha256=hashlib.sha256(raw).hexdigest(),sample_count=len(raw)//80,bytes=len(raw),original_masonry_bank_sha256=original_sha,assembly_version=VERSION)
    (out/'library.bin').write_bytes(raw);(out/'catalog.json').write_bytes(canonical_bytes(catalog));(out/'asset-contract.json').write_bytes(canonical_bytes(inspect_bank(raw,catalog)))
    for name in ('asset-profile.json','provenance.json'):shutil.copy2(base/name,out/name)
    for mode in ('brick','wall','house'):
        for seed in seeds:
            for varied in (False,True):
                r=recipe(master['bounds_size'],catalog['sha256'],seed,mode,varied);(out/f'{mode}{"" if varied else "-uniform"}-{seed}.json').write_bytes(canonical_bytes(r))
            old=legacy_recipe(master['bounds_size'],catalog['sha256'],seed,mode);(out/f'{mode}-legacy-{seed}.json').write_bytes(canonical_bytes(old))
            if mode=='brick':
                for code in (1,2,3):
                    face=recipe(master['bounds_size'],catalog['sha256'],seed,'brick');face['instances'][0].update(basis_columns=FLIPS[code].T.tolist(),orientation=code)
                    (out/f'brick-face-{code}-{seed}.json').write_bytes(canonical_bytes(face))
    print('RUNNING BOND BANK',catalog['sha256'],len(raw),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--half-sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();build(a.base,a.half_sources,a.output)
