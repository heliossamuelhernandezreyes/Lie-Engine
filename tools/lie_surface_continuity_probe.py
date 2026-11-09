"""Independent camera-disk/opaque-owner oracle and actual Vulkan regression.

Authored analytic TEST fixtures, not replacement photographic assets. The
oracle intersects rays with planes/circles; it does not use shader conics,
projected bounds, row scans or GPU depth reconstruction. All unchanged source
banks remain subject to the separate real-bank compositor suites.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
TANGENT=math.tan(math.radians(21))

def disk(**changes):
    result=dict(center=[0.,0.,1.],normal=[0.,0.,-1.],radius=180*2*TANGENT/256,
                color=[1.,1.,1.],bank=0,bounds=[[-4.,-4.,-4.],[4.,4.,4.]],
                support=[-4.,-4.,4.,4.],clip_sense=0.,clip_plane=0.)
    result.update(changes);return result

def cases():
    r=2**-.5
    result=[
      dict(name='large_disk',disks=[disk()]),
      dict(name='offscreen_center',disks=[disk(center=[(-100/256*2-1)*TANGENT,0,1])]),
      dict(name='near_center',disks=[disk(center=[0,0,.0004],radius=.002,normal=[-r,0,-r])]),
      dict(name='grazing_center',disks=[disk(radius=.5,normal=[math.sqrt(1-.014**2),0,-.014])]),
      dict(name='center_behind_eye',disks=[disk(center=[.005,0,-.0001],radius=.05,normal=[-math.sqrt(1-.01**2),0,-.01])]),
      dict(name='center_beyond_far',disks=[disk(center=[0,0,100.1],radius=1.,normal=[r,0,-r],bounds=[[-200,-200,-200],[200,200,200]],support=[-200,-200,200,200])]),
      dict(name='source_support',disks=[disk(support=[-.05,-.04,.05,.04])]),
      dict(name='source_bounds',disks=[disk(bounds=[[-.05,-.04,.9],[.05,.04,1.1]])]),
      dict(name='source_cut',disks=[disk(clip_sense=1.,clip_plane=0.)]),
      dict(name='opaque_close',disks=[disk(radius=.03,color=[1,0,0]),disk(center=[0,0,1.0001],radius=.03,color=[0,0,1])]),
      dict(name='opaque_control',disks=[disk(radius=.03,color=[1,0,0]),disk(center=[0,0,1.0005],radius=.03,color=[0,0,1])]),
      dict(name='opaque_two_banks',disks=[disk(radius=.03,color=[1,0,0]),disk(center=[0,0,1.0001],radius=.03,color=[0,0,1],bank=1)]),
      dict(name='opaque_equal_depth',disks=[disk(radius=.03,color=[1,0,0]),disk(radius=.03,color=[0,0,1],bank=1)]),
      dict(name='small_front_large_back',disks=[disk(radius=.03,color=[1,0,0]),disk(center=[0,0,1.0001],color=[0,0,1],bank=1)]),
      dict(name='large_front_small_back',disks=[disk(color=[1,0,0]),disk(center=[0,0,1.0001],radius=.03,color=[0,0,1],bank=1)]),
    ]
    for px in [61.,63.9,64.,64.1,67.]:
        result.append(dict(name='radius_'+str(px).replace('.','_'),disks=[disk(radius=px*2*TANGENT/256)]))
    result.append(dict(name='dense_large_queue',disks=[disk(radius=.24,color=[1,0,0] if i==0 else [0,0,1],bank=i%2) for i in range(70)]))
    rng=np.random.default_rng(650)
    for i in range(8):
        n=rng.normal(size=3);n[2]=-abs(n[2])-.15;n/=np.linalg.norm(n)
        result.append(dict(name='tilted_'+str(i),disks=[disk(center=[*rng.uniform(-.2,.2,size=2),1.],normal=n.tolist(),radius=float(rng.uniform(.02,.4)))]))
    return result

def rays(size=256):
    uv=(np.arange(size,dtype=np.float64)+.5)/size
    x,y=np.meshgrid((2*uv-1)*TANGENT,(1-2*uv)*TANGENT)
    return np.stack([x,y,np.ones_like(x)],axis=-1)

def oracle(scene,size=256):
    ray=rays(size);depth=np.full((size,size),np.inf);owner=np.full((size,size),-1,dtype=np.int32)
    colors=np.zeros((size,size,3));ambiguous=np.zeros((size,size),dtype=bool)
    for i,entry in enumerate(scene['disks']):
        # Use the exact float32 input values sent to the GPU, with independent
        # float64 geometric arithmetic after decoding those values.
        p=np.asarray(entry['center'],dtype=np.float32).astype(np.float64)
        n=np.asarray(entry['normal'],dtype=np.float32).astype(np.float64);n/=np.linalg.norm(n)
        radius=float(np.float32(entry['radius']));den=ray@n
        with np.errstate(divide='ignore',invalid='ignore'):
            d=(p@n)/den;hit=ray*d[...,None]
        dist=np.sum((hit-p)**2,axis=-1)/(radius*radius)
        valid=(den<0)&(d>.0005)&(d<100.)&(dist<=1.)
        lo,hi=np.asarray(entry['bounds']);valid&=np.all(hit>=lo-2e-6,axis=-1)&np.all(hit<=hi+2e-6,axis=-1)
        axis=int(np.argmax(abs(n)));axes=[2,1] if axis==0 else [0,2] if axis==1 else [0,1]
        q=hit[...,axes];support=np.asarray(entry['support'])
        valid&=np.all(q>=support[:2]-2e-6,axis=-1)&np.all(q<=support[2:]+2e-6,axis=-1)
        if entry['clip_sense']>0:valid&=hit[...,0]<=entry['clip_plane']+1e-7
        if entry['clip_sense']<0:valid&=hit[...,0]>=entry['clip_plane']-1e-7
        # A tiny geometric boundary band is retained explicitly for diagnostics;
        # it is never silently removed from the reported mismatch count.
        ambiguous|=(abs(dist-1.)<2e-5)|(abs(d-.0005)<1e-8)|(abs(d-100.)<2e-3)
        wins=valid&(d<depth)
        depth[wins]=d[wins];owner[wins]=i;colors[wins]=entry['color']
    return dict(depth=depth,owner=owner,color=colors,boundary=ambiguous)

def write_fixture(folder,scene,size=256):
    folder.mkdir(parents=True,exist_ok=True);entries=scene['disks'];count=len(entries)
    instances=np.zeros((count,24),dtype='<f4');jobs=[];banks={}
    for i,e in enumerate(entries):
        bank=int(e['bank']);bank_data=banks.setdefault(bank,dict(samples=[],jobs=[],limits=[]))
        sid=len(bank_data['samples']);sample=np.zeros(20,dtype='<f4')
        sample[:3]=e['center'];sample[3]=e['radius'];sample[4:7]=e['normal'];sample[7]=1.;sample[10]=.5
        sample[12:16]=1.;sample[16:20]=e['support'];bank_data['samples'].append(sample)
        bank_data['jobs'].append([len(bank_data['jobs']),i,i,0])
        bank_data['limits'].append(struct.pack('<4I8f',sid,sid+1,0,0,*e['bounds'][0],0,*e['bounds'][1],0))
        instances[i,[0,5,10]]=1.;instances[i,17:20]=[bank,e['clip_sense'],e['clip_plane']]
        instances[i,20:23]=e['color'];jobs.append([sid,1,i,i])
    params=np.zeros(64,dtype='<f4');params[4]=params[9]=params[14]=1.
    params[16:20]=[TANGENT,1.,.0005,100.];params.view('<i4')[20:24]=[count,count,size,size]
    params[36:40]=[0.,1.,.0007,.00022];params[60:64]=[2102.,1.,0.,0.]
    (folder/'common-1.bin').write_bytes(instances.tobytes())
    (folder/'common-2.bin').write_bytes(np.asarray(jobs,dtype='<u4').tobytes())
    (folder/'common-6.bin').write_bytes(params.tobytes())
    for bank,data in sorted(banks.items()):
        prefix=np.asarray(data['jobs'],dtype='<u4').tobytes();work=len(data['jobs'])
        par=params.copy();par.view('<i4')[20:22]=[work,work];par[52:56]=[work,len(prefix)//16,0,1];par[62]=bank
        for binding,raw in {0:np.asarray(data['samples'],dtype='<f4').tobytes(),6:par.tobytes(),14:bytes(16),
             15:b''.join(data['limits']),20:prefix+struct.pack('<8I',0,1,1,0,0,0,0,0)+bytes(work*8)}.items():
            (folder/f'bank-{bank}-{binding}.bin').write_bytes(raw)
    layout=f'{size} {count} {len(banks)}\n'+''.join(f'{bank} {len(data["jobs"])}\n' for bank,data in sorted(banks.items()))
    (folder/'layout.txt').write_text(layout);(folder/'projection-stride.txt').write_text('64');(folder/'surface-pipeline.txt').write_text('650')

def run(stage,output,replay,godot):
    output.mkdir(parents=True,exist_ok=True)
    p=subprocess.run([str(godot),'--headless','--path',str(stage),'--script','res://export_lie_surface_shaders.gd'],capture_output=True,text=True)
    (output/'shader-export.log').write_text(p.stdout+p.stderr)
    if p.returncode or 'ERROR:' in p.stderr:raise RuntimeError('surface shader export failed: '+p.stdout+p.stderr)
    shaders=stage/'surface-shaders';rows=[]
    for scene in cases():
        folder=output/scene['name'];write_fixture(folder,scene)
        p=subprocess.run([str(replay),str(folder),str(shaders),'native'],capture_output=True,text=True)
        (folder/'replay.log').write_text(p.stdout+p.stderr)
        if p.returncode:raise RuntimeError(scene['name']+': '+p.stderr)
        ref=oracle(scene);owner=np.fromfile(folder/'native-5.bin',dtype='<u4').reshape(256,256)
        depth=np.fromfile(folder/'native-4.bin',dtype='<f4').reshape(256,256)
        acc=np.fromfile(folder/'native-7.bin',dtype='<u4').reshape(256,256,8)
        visible=owner!=0xffffffff;expected=ref['owner']>=0;mismatch=visible!=expected
        owners_wrong=visible&expected&(owner!=ref['owner'])
        stable=expected&visible&~ref['boundary']
        error=np.abs(depth[stable]-ref['depth'][stable]);peak=float(np.max(error,initial=0.))
        color=acc[...,:3]/np.maximum(acc[...,3,None],1)
        color_error=float(np.max(abs(color[stable]-ref['color'][stable]),initial=0.))
        queues=[]
        for pth in sorted(folder.glob('native-queue-*.bin')):queues.append(list(struct.unpack('<8I',pth.read_bytes())))
        if any(any(q[4:]) for q in queues):raise RuntimeError('production shader contains probe counters')
        probe=dict(available=False)
        if scene['name'] in ['large_disk','grazing_center','opaque_close','small_front_large_back','dense_large_queue']:
            before={b:(folder/f'native-{b}.bin').read_bytes() for b in [4,5,7]}
            pp=subprocess.run([str(replay),str(folder),str(stage/'surface-probe-shaders'),'native'],capture_output=True,text=True)
            (folder/'probe-replay.log').write_text(pp.stdout+pp.stderr)
            if pp.returncode:raise RuntimeError('probe: '+pp.stderr)
            exact=all(before[b]==(folder/f'native-{b}.bin').read_bytes() for b in before)
            pq=[list(struct.unpack('<8I',x.read_bytes())) for x in sorted(folder.glob('native-queue-*.bin'))]
            probe=dict(available=True,pixel_buffers_exact=exact,queues=pq)
            if not exact or any(q[7]!=0 for q in pq) or sum(q[6] for q in pq)<int(visible.sum()):raise RuntimeError('instrumented kernel output/counters')
        row=dict(name=scene['name'],device=json.loads(p.stdout)['device'],reference_pixels=int(expected.sum()),pixels=int(visible.sum()),
                 coverage_mismatches=int(mismatch.sum()),nonboundary_mismatches=int((mismatch&~ref['boundary']).sum()),
                 owner_mismatches=int(owners_wrong.sum()),depth_max_abs=peak,color_max_abs=color_error,queues=queues,probe=probe)
        row['passed']=row['nonboundary_mismatches']==0 and row['owner_mismatches']==0 and peak<2e-3 and color_error<1e-6 and all(q[7]==0 for q in queues)
        rows.append(row);print(json.dumps(row),flush=True)
    result=dict(schema='lie-surface-continuity-probe/1',cases=rows,passed=all(r['passed'] for r in rows),
                physical_android_tested=False,scope='Actual production SPIR-V and Vulkan replay, analytic test geometry and independent float64 ray oracle. Alternating bank order is byte-compared by replay. Boundary discrepancies are reported separately; no phone timing claim.')
    (output/'surface-continuity-results.json').write_text(json.dumps(result,indent=2))
    if not result['passed']:raise RuntimeError('surface continuity regression')
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--replay',type=Path,required=True);p.add_argument('--godot',type=Path,required=True);a=p.parse_args()
    run(a.stage.resolve(),a.output.resolve(),a.replay.resolve(),a.godot.resolve())
