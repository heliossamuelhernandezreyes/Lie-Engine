"""Wall adapter for shared source strata, BLAS and a small instance hierarchy."""
import json,math
from pathlib import Path
import numpy as np
from lie_asset_surface import sha,partition_selection,selection_metrics,compile_blas,compile_scene
ROOT=Path(__file__).resolve().parents[1]
def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text());raw=(root/'library.bin').read_bytes()
    if sha(raw)!=cat['sha256']:raise ValueError('surface source identity')
    a=np.frombuffer(raw,dtype='<f4').reshape(-1,20);refs=np.fromfile(root/'sample-refs.bin',dtype='<u4');new=refs.copy();reports=[]
    for lod,budget in enumerate([4000,1300,240]):
        level=cat['masters']['real_scan_wall']['levels'][lod];start,count=level['start'],level['count'];source=a[start:start+count]
        choices=partition_selection(source,budget);metrics=[]
        for v in range(len(choices)):metrics.append(selection_metrics(source,choices[v]))
        baseline=[];selected=[];unique=set()
        for owner,job in enumerate(cat['wall05']['instance_jobs'][lod][:-1]):
            at,n,_,_=job;rng=np.random.default_rng(571577+lod*1000003+owner*7919)
            variant=rng.integers(0,len(choices),size=n);selection=choices[variant,np.arange(n)];new[at:at+n]=selection+start;unique.add(sha(selection.tobytes()))
            if owner<4:baseline.append(selection_metrics(source,refs[at:at+n]-start));selected.append(selection_metrics(source,selection))
        reports.append({'lod':lod,'budget':budget,'variants':metrics,'baseline_first_four_instances':baseline,'selected_first_four_instances':selected,'distinct_instance_selections':len(unique)})
    ranges=[(0,220000)]
    joint=cat['masters']['joint_photo']['levels'][0];ranges.append((joint['start'],joint['count']))
    nodes,leaf_ids,roots=compile_blas(a,ranges)
    dims=cat['wall06']['aligned_bbox_m'];scale=np.array([(dims[0]+.0085-.003)/dims[0],(dims[1]+.0085-.003)/dims[1],1.])
    instances=[]
    for pose in cat['wall05']['poses']:
        c,s=math.cos(pose['yaw_rad']),math.sin(pose['yaw_rad']);matrix=np.eye(4);matrix[:3,:3]=np.diag(scale)@np.array([[c,0,s],[0,1,0],[-s,0,c]]);matrix[:3,3]=pose['center']
        instances.append({'root':0,'matrix':matrix.tolist()})
    instances.append({'root':1,'matrix':np.eye(4).tolist()});scene=compile_scene(instances,roots)
    packets={'references':('surface-refs.bin',new.astype('<u4').tobytes()),'nodes':('surface-bvh.bin',nodes),'leaves':('surface-leaves.bin',leaf_ids),'scene':('surface-scene.bin',scene)}
    proof={'schema':'lie-source-surface/1','source_bank_sha256':sha(raw),'source_samples':len(a),'reference_bytes':new.nbytes,'legacy_reference_sha256':sha(refs.tobytes()),'selection':'normal-hemisphere balanced spatial strata, four authentic ID variants','coverage':reports,'roots':roots,'instances':len(instances),'packets':{},'scope':'captured tangent disks; static affine source instances; camera independent short visibility; no original meshes rendered','bank_modified':False,'work_modified':False}
    for key,(name,blob) in packets.items():(root/name).write_bytes(blob);proof['packets'][key]={'file':name,'bytes':len(blob),'sha256':sha(blob)}
    (root/'surface-source.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
if __name__=='__main__':
    p=prepare();print(json.dumps({'packets':p['packets'],'roots':p['roots'],'coverage':p['coverage']},indent=2))
