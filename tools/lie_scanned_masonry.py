"""Seeded whole-brick recipes. Captured scan is immutable and never stretched.

Stack bond is explicit: this prototype has no fabricated half-brick source.
Openings omit complete cells; authored mortar panels are split at those cells.
"""
import argparse,hashlib,json,math,shutil
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank

VERSION='lie-scanned-masonry/1'
def noise(seed,section,row,col,channel):
    h=2166136261
    for value in (seed,section,row,col,channel):
        h=((h^(int(value)&0xffffffff))*16777619)&0xffffffff
        h^=h>>13
    return h/4294967295.

def recipe(size,bank_sha,seed=2102,mode='wall'):
    if type(seed) is not int or not 0<=seed<=0xffffffff:raise ValueError('seed_uint32')
    if mode not in ('brick','wall','house'):raise ValueError('mode')
    x,y,z=map(float,size);gap=.008;px=x+gap;py=y+gap
    rows=8 if mode=='wall' else 36;cols=12 if mode=='wall' else 22;side_cols=16
    W=cols*px-gap;H=rows*py-gap;D=side_cols*px-gap+2*(z+gap)
    entries=[];openings=[]
    def add(master,origin,yaw=0,scale=(1,1,1),id=''):
        entries.append(dict(id=id,master=master,origin=list(origin),yaw=float(yaw),scale=list(scale)))
    if mode=='brick':add('scanned_brick',(0,0,0),id='brick/0');bounds=[x,y,z]
    else:
        sections=[(cols,0,0,0)] if mode=='wall' else [(cols,0,D/2-z/2,0),(cols,0,-D/2+z/2,math.pi),(side_cols,W/2-z/2,0,math.pi/2),(side_cols,-W/2+z/2,0,-math.pi/2)]
        for s,(n,cx,cz,yaw) in enumerate(sections):
            holes=[]
            if mode=='house':
                if s==0:holes.append((8+int(noise(seed,s,0,0,8)*2),0,4,29,'door'))
                if s!=0:holes.append((3+int(noise(seed,s,0,0,9)*3),13,5,12,'window'))
            else:holes=[(4,2,3,4,'window')]
            for c,r,w,h,kind in holes:openings.append(dict(section=s,column=c,row=r,columns=w,rows=h,kind=kind,clear_width_m=w*px-gap,clear_height_m=h*py-gap))
            width=n*px-gap
            for r in range(rows):
                for c in range(n):
                    if any(a<=c<a+w and b<=r<b+h for a,b,w,h,_ in holes):continue
                    local=(c*px-width/2+x/2,r*py+y/2,0)
                    # Bounded jitter leaves >=6mm between conservative boxes.
                    dx=(noise(seed,s,r,c,0)-.5)*.0007;dy=(noise(seed,s,r,c,1)-.5)*.0007
                    angle=(noise(seed,s,r,c,2)-.5)*math.radians(.6)
                    flip=math.pi if noise(seed,s,r,c,3)>.5 else 0
                    ox=cx+math.cos(yaw)*local[0];oz=cz-math.sin(yaw)*local[0]
                    add('scanned_brick',(ox+dx,local[1]+dy,oz),yaw+angle+flip,id=f'brick/{s}/{r}/{c}')
                    # One shallow rear mortar cell per occupied brick, recessed
                    # 5mm from the deepest source face. No bridging openings.
                    recess=-.006
                    add('authored_box',(ox+math.sin(yaw)*recess,local[1],oz+math.cos(yaw)*recess),yaw,(px,py,z-.012),id=f'mortar/{s}/{r}/{c}')
        bounds=[W,H,z if mode=='wall' else D]
        if mode=='house':
            add('authored_box',(0,-.025,0),scale=(W+.08,.05,D+.08),id='floor')
            add('authored_roof',(0,H+.045,0),scale=(W+.16,.09,D+.16),id='roof')
    return dict(schema=VERSION,seed=seed,mode=mode,bank_sha256=bank_sha,brick_bounds_m=list(size),bounds_m=bounds,bond='whole-brick stack bond',joint_m=gap,
                source_color_variation=False,opening_rule='omit complete cells and their mortar; roof/floor remain separate authored assets',openings=openings,instances=entries)

def canonical_bytes(value):return (json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()

def box_samples(res,color):
    a=[]
    # Unit cube with actual surface samples and face-clipped support.
    for axis in range(3):
        other=[v for v in range(3) if v!=axis]
        for sign in (-1,1):
            for i in range(res):
                for j in range(res):
                    p=np.zeros(3);p[axis]=sign*.5;p[other]=[(i+.5)/res-.5,(j+.5)/res-.5]
                    n=np.zeros(3);n[axis]=sign
                    a.append([*p,1.6/res,*n,0,4,axis*2+(sign>0),.95,0,*color,1,-.5,-.5,.5,.5])
    return np.array(a,dtype='<f4')

def build(capture,output,seeds=(2102,7319)):
    if not seeds or any(type(s) is not int or not 0<=s<=0xffffffff for s in seeds):raise ValueError('seed_uint32')
    output.mkdir(parents=True,exist_ok=True);catalog=json.loads((capture/'catalog.json').read_text());raw=bytearray((capture/'library.bin').read_bytes())
    original_sha=catalog['sha256']
    for name,color in [('authored_box',(.22,.205,.18)),('authored_roof',(.07,.085,.10))]:
        levels=[]
        for res in (48,24,12,8,4):
            a=box_samples(res,color);levels.append(dict(start=len(raw)//80,count=len(a)));raw.extend(a.tobytes())
        catalog['masters'][name]=dict(levels=levels,bounds_size=[1,1,1],bounds_center=[0,0,0],provenance='authored unit-box surface, no photograph or scan',optical_material=dict(metallic=0,transmission=0,ior=1.5,roughness_origin='authored'))
    catalog.update(sha256=hashlib.sha256(raw).hexdigest(),sample_count=len(raw)//80,bytes=len(raw),original_brick_bank_sha256=original_sha)
    (output/'library.bin').write_bytes(raw);(output/'catalog.json').write_bytes(canonical_bytes(catalog));(output/'asset-contract.json').write_bytes(canonical_bytes(inspect_bank(raw,catalog)))
    for name in ('provenance.json','asset-profile.json'):shutil.copy2(capture/name,output/name)
    for mode in ('brick','wall','house'):
        for seed in dict.fromkeys(seeds):
            value=recipe(catalog['masters']['scanned_brick']['bounds_size'],catalog['sha256'],seed,mode)
            (output/f'{mode}-{seed}.json').write_bytes(canonical_bytes(value))
    print('MASONRY BANK',catalog['sha256'],len(raw),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--capture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--seed',type=int,action='append',help='Repeat for any uint32 seeds; native demo ships 2102 and 7319');a=p.parse_args();build(a.capture,a.output,a.seed or (2102,7319))
