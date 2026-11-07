"""Compile a first construction kit and compose it through bank-bound asset sets."""
import argparse,copy,hashlib,json,math,shutil
from pathlib import Path
from collections import defaultdict
import numpy as np
from lie_construction_sources import SPECS,generate
from lie_brick02_capture_scan import capture
from lie_asset_contract import inspect_bank,bound_source_support
from lie_asset_sets import compile_set
from lie_scanned_masonry import canonical_bytes
from lie_masonry_bond import turn,subtract,FLIPS

def node_from_entry(e):
    return dict(id=e['id'],asset=e['master'],origin=e['origin'],basis_columns=e.get('basis_columns',turn(1,e.get('yaw',0)).T.tolist()),scale=e.get('scale',[1,1,1]),tint=e.get('tint',[1,1,1]),roughness_delta=e.get('roughness_delta',0),lod=e.get('lod',3),properties=e)
def entry(master,id,origin,R=np.eye(3),scale=(1,1,1),**data):return dict(master=master,id=id,origin=list(origin),basis_columns=np.asarray(R).T.tolist(),scale=list(scale),yaw=0.,**data)

def add_architecture(r,catalog,raw):
    """Replace one course above/below openings, then build actual joint runs.

    Mortar front uses observed adjacent source edge percentiles. This is an
    explicit conservative fit, not exact contact at every irregular pore.
    """
    r=copy.deepcopy(r);x,y,z=r['brick_bounds_m'];g=r['joint_m'];pitch=x+g;half=pitch/2;py=y+g;W,H,D=r['bounds_m'];house=r['mode']=='house'
    sections=[(W,0,0,0)] if not house else [(W,0,D/2-z/2,0),(W,0,-D/2+z/2,math.pi),(D-2*(z+g),W/2-z/2,0,math.pi/2),(D-2*(z+g),-W/2+z/2,0,-math.pi/2)]
    slots=[]
    for i,h in enumerate(r['openings']):
        n=round((sections[h['section']][0]+g)/pitch);a=max(0,2*(h['column']-1));b=min(2*n,2*(h['column']+h['columns']+1))
        slots.append(dict(section=h['section'],row=h['row']+h['rows'],a=a,b=b,master='concrete_lintel',id='opening-head/'+str(i)))
        if h['kind']=='window' and h['row']>0:slots.append(dict(section=h['section'],row=h['row']-1,a=a,b=b,master='concrete_sill',id='opening-sill/'+str(i)))
    bricks=[];base=[]
    for e in r['instances']:
        if e['master'] not in ('scanned_brick','half_left','half_right'):
            if e['id'] in ('roof','floor'):base.append(e)
            continue
        a,b=e['interval_half_cells'];cuts=[(s['a'],s['b']) for s in slots if s['section']==e['section'] and s['row']==e['row']]
        for c,d in subtract((a,b),cuts):
            part=copy.deepcopy(e)
            if (c,d)!=(a,b):
                if b-a!=2 or d-c!=1:raise ValueError('unsupported_boundary_cut')
                cut_right=c==a;original_right=cut_right if FLIPS[e['orientation']][0,0]>0 else not cut_right;name='half_left' if original_right else 'half_right';info=catalog['masters'][name]['modifications'];pivot=(info['bounds_min'][0]+info['bounds_max'][0])/2
                R=np.array(e['basis_columns']).T;part.update(master=name,origin=(np.array(e['origin'])+R@np.array([pivot,0,0])).tolist(),id=e['id']+'/opening-trim',interval_half_cells=[c,d],cut_face='right' if cut_right else 'left')
            bricks.append(part)
    structural=[]
    for s in slots:
        width,cx,cz,yaw=sections[s['section']];R=turn(1,yaw);a,b=s['a'],s['b'];length=(b-a)*half-g;local=np.array([(a+b)*half/2-width/2-g/2,s['row']*py+y/2,0.])
        if s['master']=='concrete_sill':local[2]=.008
        structural.append(entry(s['master'],s['id'],R@local+[cx,0,cz],R,(length,y/SPECS[s['master']]['dimensions'][1],1),section=s['section'],row=s['row'],interval_half_cells=[a,b],lod=2))
    rows=defaultdict(list);front={};points=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
    for e in bricks+structural:
        rows[e['section'],e['row']].append(e);wallR=turn(1,sections[e['section']][3]);R=wallR.T@np.array(e['basis_columns']).T;master=catalog['masters'][e['master']];level=master['levels'][2];a=points[level['start']:level['start']+level['count']];p=(a[:,:3]*np.array(e['scale']))@R.T;n=a[:,4:7]@R.T;mask=(n[:,2]>.65)&(p[:,2]>0);f=p[mask]
        if len(f)<8:raise ValueError('joint_missing_front_source')
        local_center=wallR.T@(np.array(e['origin'])-[sections[e['section']][1],0,sections[e['section']][2]])
        edge={}
        for key,axis,sign in [('l',0,-1),('r',0,1),('b',1,-1),('t',1,1)]:
            values=f[:,axis]*sign;selection=values>=np.quantile(values,.72);edge[key]=float(np.quantile(f[selection,2],.20)+local_center[2])
        front[e['id']]=edge
    joints=[]
    for (section,row),items in rows.items():
        width,cx,cz,yaw=sections[section];R=turn(1,yaw);items.sort(key=lambda e:e['interval_half_cells'][0])
        for left,right in zip(items,items[1:]):
            u=left['interval_half_cells'][1]
            if u!=right['interval_half_cells'][0]:continue
            zf=float(np.clip(min(front[left['id']]['r'],front[right['id']]['l'])-.0015,.018,.057));back=-.025;depth=zf-back
            local=[u*half-width/2-g/2,row*py+y/2,(zf+back)/2]
            joints.append(entry('mortar_head',f'joint-head/{section}/{row}/{u}',R@local+[cx,0,cz],R,(1,1,depth/.05),section=section,row=row,interval_half_cells=[u,u],joint_kind='head',touch_rows=[row],front_reference_m=zf,front_fit_recipe='adjacent observed front-edge p20 minus 1.5 mm; approximate',lod=4 if house else 2))
        # Horizontal beds exist only where both courses contain solid pieces.
        lower=rows.get((section,row-1),[]) if row else items
        intersections=[]
        for upper in items:
            for below in lower:
                a=max(upper['interval_half_cells'][0],below['interval_half_cells'][0]);b=min(upper['interval_half_cells'][1],below['interval_half_cells'][1])
                if b>a:intersections.append((a,b,upper,below))
        runs=[]
        for a,b,_,_ in sorted(intersections,key=lambda v:(v[0],v[1])):
            if runs and a<=runs[-1][1]:runs[-1]=(runs[-1][0],max(runs[-1][1],b))
            else:runs.append((a,b))
        for i,(a,b) in enumerate(runs):
            for c in range(a,b,2):
                d=min(c+2,b);length=(d-c)*half;neighbors=[v for a0,b0,upper,below in intersections if a0<d and b0>c for v in (front[upper['id']]['b'],front[below['id']]['t'])]
                zf=float(np.clip(min(neighbors)-.0015,.018,.057));back=-.025;depth=zf-back
                local=[(c+d)*half/2-width/2-g/2,row*py-g/2,(zf+back)/2]
                joints.append(entry('mortar_bed',f'joint-bed/{section}/{row}/{i}/{c}',R@local+[cx,0,cz],R,(length/SPECS['mortar_bed']['dimensions'][0],1,depth/.05),section=section,row=row,interval_half_cells=[c,d],joint_kind='bed',touch_rows=[row] if row==0 else [row-1,row],front_reference_m=zf,front_fit_recipe='adjacent observed front-edge p20 minus 1.5 mm; approximate',lod=4 if house else 2))
    r.update(instances=bricks+structural+joints+base,construction_version='lie-construction-kit/1',joint_fit='explicit joint meshes, observed source edge percentile; no photographic mortar claim',slots=slots)
    return r

def package(base,sources,out):
    out.mkdir(parents=True,exist_ok=True);manifest=generate(sources);catalog=json.loads((base/'catalog.json').read_text());raw=bytearray((base/'library.bin').read_bytes());base_sha=catalog['sha256'];defs=dict(schema='lie-asset-sets/1',bank_sha256='',assets={},sets={})
    for name,spec in manifest.items():
        root=out.parent/('capture-'+name);profile=json.loads((sources/(name+'-profile.json')).read_text());part=capture(sources/(name+'.glb'),sources/(name+'-provenance.json'),root,counts=(6000,1536,384),seed=6102,asset_profile=profile);data=bytearray((root/'library.bin').read_bytes());desc=part['masters'][name]
        low=np.array(spec['bounds_min']);high=np.array(spec['bounds_max']);levels=desc['levels']
        for count in (128,64):
            source=levels[2];a=np.frombuffer(data,dtype='<f4').reshape(-1,20)[source['start']:source['start']+source['count']][:count].copy();a[:,3]*=math.sqrt(source['count']/count)
            # Keep the same authored face-group bounds at every LOD; only
            # support radius changes with point density.
            bound_source_support(a,low,high);levels.append(dict(start=len(data)//80,count=count));data.extend(a.tobytes())
        offset=len(raw)//80
        for level in levels:level['start']+=offset
        desc.update(bounds_size=(high-low).tolist(),bounds_center=((high+low)/2).tolist(),source_provenance=json.loads((sources/(name+'-provenance.json')).read_text()),asset_profile=profile,scale_policy='authored_positive')
        catalog['masters'][name]=desc;raw.extend(data)
    if len(raw)>64*1024*1024:raise ValueError('kit_shared_bank_cap')
    catalog.update(sha256=hashlib.sha256(raw).hexdigest(),sample_count=len(raw)//80,bytes=len(raw),construction_kit_version='lie-construction-kit/1',previous_bank_sha256=base_sha)
    for name in catalog['masters']:
        defs['assets'][name]=dict(master=name,role=manifest.get(name,{}).get('role','scanned_masonry' if name in ('scanned_brick','half_left','half_right') else 'authored_backing'),scale_policy='rigid' if name in ('scanned_brick','half_left','half_right') else 'authored_positive')
    defs['bank_sha256']=catalog['sha256'];recipes={}
    # Preserve every earlier recipe and its immutable source prefix.
    for p in base.glob('*.json'):
        if not p.name.startswith(('brick-','wall-','house-')):continue
        r=json.loads(p.read_text());r['bank_sha256']=catalog['sha256']
        if r['mode'] in ('wall','house') and '-legacy-' not in p.name:r=add_architecture(r,catalog,raw)
        for e in r['instances']:
            if 'lod' not in e:e['lod']=0 if r['mode']=='brick' else 2 if r['mode']=='wall' else 3
        defs['sets'][p.stem]=dict(nodes=[node_from_entry(e) for e in r['instances']]);r['instances']=compile_set(defs,p.stem,catalog);recipes[p.name]=r
    gallery=[]
    for i,name in enumerate(SPECS):
        dim=catalog['masters'][name]['bounds_size'];gallery.append(entry(name,'piece/'+name,[(i%4-1.5)*1.2,dim[1]/2+(1-i//4)*.72,0],lod=1))
    defs['sets']['kit-gallery']=dict(nodes=[node_from_entry(e) for e in gallery])
    roof_nodes=[]
    for i,z in enumerate((-.22,.22)):roof_nodes.append(node_from_entry(entry('timber_beam','beam/'+str(i),[0,.04,z],lod=1)))
    for row in range(2):
        for col in range(4):roof_nodes.append(node_from_entry(entry('ceramic_tile',f'tile/{row}/{col}',[(col-1.5)*.16,.092+row*.005,(row-.5)*.22],lod=1)))
    defs['sets']['roof-frame']=dict(nodes=roof_nodes[:2]);defs['sets']['roof-cover']=dict(nodes=roof_nodes[2:]);defs['sets']['roof-patch']=dict(nodes=[dict(id='structure',set='roof-frame'),dict(id='covering',set='roof-cover')])
    # A reusable independent opening frame, also available for later builders.
    frame=[entry('concrete_lintel','head',[0,.59,0],lod=1),entry('concrete_sill','sill',[0,.03,.015],lod=1)]
    for side in (-1,1):frame.append(entry('concrete_lintel','jamb/'+str(side),[side*.47,.31,0],turn(2,math.pi/2),(.52,1,1),lod=1))
    defs['sets']['opening-frame']=dict(nodes=[node_from_entry(e) for e in frame])
    for seed in (2102,7319):
        for mode,setname,bounds in [('kit','kit-gallery',[4.6,1.3,.5]),('roof','roof-patch',[1.1,.14,.65]),('frame','opening-frame',[1.05,.64,.18])]:
            recipes[f'{mode}-{seed}.json']=dict(schema='lie-asset-set-scene/1',seed=seed,mode=mode,bank_sha256=catalog['sha256'],bounds_m=bounds,instances=compile_set(defs,setname,catalog),set_id=setname)
        for name in SPECS:
            dim=catalog['masters'][name]['bounds_size'];sid='single-'+name;defs['sets'][sid]=dict(nodes=[node_from_entry(entry(name,'source',[0,dim[1]/2,0],lod=0))]);recipes[f'asset_{name}-{seed}.json']=dict(schema='lie-asset-set-scene/1',seed=seed,mode='asset_'+name,bank_sha256=catalog['sha256'],bounds_m=dim,instances=compile_set(defs,sid,catalog),set_id=sid)
    catalog['kit_modes']=['kit','frame','roof']+['asset_'+name for name in SPECS];catalog['collections']={'masonry':['scanned_brick','half_left','half_right','mortar_bed','mortar_head','mortar_corner'],'openings':['concrete_lintel','concrete_sill'],'finish_and_roof':['plaster_panel','timber_beam','ceramic_tile']}
    (out/'library.bin').write_bytes(raw);(out/'catalog.json').write_bytes(canonical_bytes(catalog));(out/'asset-contract.json').write_bytes(canonical_bytes(inspect_bank(raw,catalog)));(out/'asset-sets.json').write_bytes(canonical_bytes(defs))
    for name,r in recipes.items():(out/name).write_bytes(canonical_bytes(r))
    for name in ('asset-profile.json','provenance.json'):shutil.copy2(base/name,out/name)
    proof=dict(schema='lie-construction-kit-proof/1',previous_bank_prefix_unchanged=raw[:(base/'library.bin').stat().st_size]==(base/'library.bin').read_bytes(),bank_sha256=catalog['sha256'],bytes=len(raw),masters=len(catalog['masters']),new_assets=list(SPECS),sets=len(defs['sets']),scenes=len(recipes))
    (out/'kit-proof.json').write_text(json.dumps(proof,indent=2)+'\n');print('CONSTRUCTION KIT',proof,flush=True);return catalog,defs
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();package(a.base,a.sources,a.output)
