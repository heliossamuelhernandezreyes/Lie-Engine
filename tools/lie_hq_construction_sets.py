"""Rigid-parent reusable modules; scanned bricks never stretch or reflect."""
import argparse,json,math,copy
from pathlib import Path
import numpy as np
from lie_masonry_bond import FLIPS,turn,row_cells,subtract,noise
from lie_hq_construction_bank import compile_scene,virtual_catalog
from lie_hq_construction_sources import write

def leaf(asset,id,origin,R=None,scale=(1,1,1),lod=1,**extra):
    return dict(id=id,asset=asset,origin=list(origin),basis_columns=(np.eye(3) if R is None else R).T.tolist(),scale=list(scale),lod=lod,**extra)
def build(root):
    m=json.loads((root/'manifest.json').read_text());cats={k:json.loads((root/'banks'/k/'catalog.json').read_text()) for k in m['banks']};doc=json.loads((root/'sets.json').read_text());virtual,_=virtual_catalog(cats)
    size=np.array(cats['brick']['masters']['scanned_brick']['bounds_size']);x,y,z=size;g=.008;half=(x+g)/2;py=y+g;W=16*half-g;H=18*py-g;base=.08;corner_gap=half-z
    if corner_gap<=0:raise ValueError('scan_too_thick_for_half_module_corner')
    for seed in (2102,7319):
        main=[];courses={};centers={};Rside=turn(1,-math.pi/2);start_even=z/2+corner_gap;side_end=start_even+8*half-g
        for section in (0,1):
            Rwall=np.eye(3) if section==0 else Rside
            for row in range(18):
                cells=16-(row%2) if section==0 else 8+(row%2)
                intervals=row_cells(8,row) if section==0 else [(i,min(i+2,cells)) for i in range(0,cells,2)]
                intervals=[(a,min(b,cells)) for a,b in intervals if a<cells]
                holes=[(4,10)] if section==0 and 5<=row<13 else [(3,11)] if section==0 and row in (4,13) else []
                origin=np.array([-W/2,base+row*py+y/2,0.]) if section==0 else np.array([W/2-z/2,base+row*py+y/2,start_even if row%2==0 else -z/2])
                courses[section,row]=[];centers[section,row]=(origin,Rwall,cells)
                for a,b in intervals:
                    for low,high in subtract((a,b),holes):
                        master='scanned_brick' if high-low==2 else 'half_left' if low==a else 'half_right'
                        code=min(3,int(noise(seed,section,row,low,30)*4)) if master=='scanned_brick' else 0
                        R=Rwall@FLIPS[code];position=origin+Rwall@np.array([(low+high)*half/2-g/2,0,0])
                        gain=.94+.12*noise(seed,section,row,low,50);warm=(noise(seed,section,row,low,51)-.5)*.04
                        node=leaf('brick/'+master,f'brick/{section}/{row}/{low}',position,R,lod=2,tint=[gain*(1+warm),gain,gain*(1-warm)],properties={'section':section,'row':row,'interval_half_cells':[low,high],'orientation':code})
                        main.append(node);courses[section,row].append((low,high,node))
                # Recessed photographic mortar body is split around every real opening.
                for a,b in subtract((0,cells),holes):
                    for low in range(a,b,2):
                        high=min(low+2,b);length=(high-low)*half-g;pos=origin+Rwall@np.array([(low+high)*half/2-g/2,0,0])
                        main.append(leaf('mortar/mortar_bed',f'backfill/{section}/{row}/{low}',pos,Rwall,scale=(length/.207519617,(y+g)/.008,.064/.094),lod=4))
                if section==0 and row in (4,13):
                    courses[section,row].append((3,11,None));courses[section,row].sort(key=lambda item:item[0])
                # Explicit head joints and horizontal beds remain separate pieces.
                for (_,left,node),(right,_,other) in zip(courses[section,row],courses[section,row][1:]):
                    if left!=right:continue
                    pos=origin+Rwall@np.array([left*half-g/2,0,0]);main.append(leaf('mortar/mortar_head',f'head/{section}/{row}/{left}',pos,Rwall,scale=(1,1,.073/.094),lod=3))
                lower=courses.get((section,row-1),courses[section,row])
                overlap=[]
                for a,b,_ in courses[section,row]:
                    for c,d,_ in lower:
                        lo,hi=max(a,c),min(b,d)
                        if lo<hi:overlap.append((lo,hi))
                # Union before placement: no duplicated beds at staggered boundaries.
                runs=[]
                for a,b in sorted(overlap):
                    if runs and a<=runs[-1][1]:runs[-1]=(runs[-1][0],max(b,runs[-1][1]))
                    else:runs.append((a,b))
                for a,b in runs:
                    for low in range(a,b,2):
                        high=min(low+2,b);pos=origin+Rwall@np.array([(low+high)*half/2-g/2,-(y+g)/2,0])
                        main.append(leaf('mortar/mortar_bed',f'bed/{section}/{row}/{low}',pos,Rwall,scale=((high-low)*half/.207519617,1,.073/.094),lod=3))
        for row in range(18):
            center=[W/2-z/2,base+row*py+y/2,z/2+corner_gap/2] if row%2==0 else [W/2-half+corner_gap/2,base+row*py+y/2,0]
            main.append(leaf('mortar/mortar_head','elbow/'+str(row),center,Rside if row%2==0 else np.eye(3),scale=(corner_gap/.008,1,.073/.094),lod=3))
            main.append(leaf('mortar/mortar_return','corner-bed/'+str(row),[W/2-z/2,base+row*py-g/2,z/2],lod=3))
        # Structural replacements exactly occupy their authored half-module slots.
        opening_center=-W/2+7*half-g/2;lower=base+4*py+y/2;upper=base+13*py+y/2
        frame=[leaf('concrete/concrete_sill','sill',[opening_center,lower,0],scale=((8*half-g)/.68,1,1),lod=1),leaf('concrete/concrete_lintel','lintel',[opening_center,upper,0],scale=((8*half-g)/.82,1,1),lod=1)]
        bottom=lower+.042/2;top=upper-.062/2;mid=(bottom+top)/2;height=top-bottom-.004;outer_width=.61
        for sign in (-1,1):
            frame.append(leaf('wood/wood_head','rail/'+str(sign),[opening_center,mid+sign*(height/2-.016),z/2-.008],lod=1))
            frame.append(leaf('wood/wood_jamb','jamb/'+str(sign),[opening_center+sign*(outer_width/2-.016),mid,z/2-.008],turn(2,math.pi/2),scale=((height-.064)/.47,1,1),lod=1))
        doc['sets']['opening-'+str(seed)]={'nodes':frame}
        main.append({'id':'opening','set':'opening-'+str(seed)})
        main.append(leaf('concrete/concrete_plinth','foundation/main',[0,.04,0],scale=(W/1.66,1,1),lod=1))
        main.append(leaf('concrete/concrete_plinth','foundation/return',[W/2-z/2,.04,(side_end+z/2)/2],Rside,scale=((side_end-z/2)/1.66,1,1),lod=1))
        doc['sets']['corner-'+str(seed)]={'nodes':main}
        pitch=.23;roof=[];slope=turn(0,math.radians(20))
        for i in (-1,1):roof.append(leaf('wood/wood_beam','beam/'+str(i),[0,.02,i*.33],lod=1))
        for row in range(4):
            for col in range(5):
                pos=slope@np.array([(col-2)*.172,.08+row*.012,(row-1.5)*pitch]);roof.append(leaf('wood/wood_shingle',f'shingle/{row}/{col}',pos,slope,lod=1))
        doc['sets']['roof-'+str(seed)]={'nodes':roof}
        door=[leaf('door/wood_door_leaf','leaf',[0,1.025,.01],lod=0),leaf('wood/wood_beam','head',[0,2.095,0],scale=(.96,1,1),lod=1)]
        for s in (-1,1):door.append(leaf('wood/wood_door_jamb','door-jamb/'+str(s),[s*.45,1.03,0],turn(2,math.pi/2),lod=1))
        doc['sets']['door-'+str(seed)]={'nodes':door}
        doc['sets']['shadow-'+str(seed)]={'nodes':[leaf('concrete/concrete_plinth','receiver',[0,-.04,0],scale=(1,1,4),lod=0),leaf('wood/wood_beam','occluder',[0,.20,.10],lod=1)]}
        doc['sets']['occlusion-'+str(seed)]={'nodes':[leaf('door/wood_door_leaf','back',[0,0,-.04],lod=1),leaf('concrete/concrete_lintel','occluder',[0,0,.06],lod=0)]}
        for aid in doc['assets']:
            bank,name=aid.split('/');key='asset_'+name+'-'+str(seed);doc['sets'][key]={'nodes':[leaf(aid,'source',[0,0,0],lod=0)]}
        for mode in ['corner','opening','roof','door','shadow','occlusion']+['asset_'+a.split('/')[1] for a in doc['assets']]:
            scene=compile_scene(doc,mode+'-'+str(seed),cats);scene.update(seed=seed,mode=mode)
            if mode=='corner':scene.update(bounds_m=[W,H+base,side_end+z/2],target=[0,(H+base)/2,side_end/4],opening={'center':[opening_center,mid,0],'clear_size':[outer_width-.064,height-.064]},corner_gap_m=corner_gap,bond='alternate full/half module interlock; all scan instances rigid')
            elif mode=='opening':scene.update(bounds_m=[.85,height+.13,.18],target=[opening_center,mid,0])
            elif mode=='roof':scene.update(bounds_m=[1.05,.5,1.],target=[0,.06,0],roof_kind='authored wooden shingle patch, not ceramic tile scan')
            elif mode=='door':scene.update(bounds_m=[1.,2.15,.14],target=[0,1.05,0])
            elif mode=='shadow':scene.update(bounds_m=[1.7,.4,1.],target=[0,.06,0])
            elif mode=='occlusion':scene.update(bounds_m=[.9,2.05,.2],target=[0,0,0])
            else:
                entry=scene['instances'][0];desc=cats[entry['bank']]['masters'][entry['master']];scene.update(bounds_m=desc['bounds_size'],target=desc.get('bounds_center',[0,0,0]))
            write(root/(mode+'-'+str(seed)+'.json'),scene)
    write(root/'sets.json',doc);m['modes']=['corner','opening','roof','door','shadow','occlusion']+['asset_'+a.split('/')[1] for a in doc['assets']];write(root/'manifest.json',m)
    return m
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();build(a.root)
