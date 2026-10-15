"""Float64 references for all eight persistent visibility channels and updates."""
import json,struct
from pathlib import Path
import numpy as np
from lie_source_visibility_fixture import cases,pack_queries
from lie_asset_surface import compile_blas,compile_scene,reference_rays
ROOT=Path(__file__).resolve().parents[1]
def prepare():
    result=cases()
    a=np.zeros((1,20),dtype='<f4');a[0,:4]=[.022,0,.0025,.003];a[0,6]=1
    nodes,refs,roots=compile_blas(a,[(0,1)]);instances=[{'root':0,'matrix':np.eye(4).tolist()}]
    q={'point':[0.,0.,0.],'normal':[0.,0.,1.],'light':[1.,0.,.1]}
    result.append({'name':'metric_fade','bank_hex':a.tobytes().hex(),'nodes_hex':nodes.hex(),'leaves_hex':refs.hex(),'scene_hex':compile_scene(instances,roots).hex(),'queries_hex':pack_queries([q]).hex(),'expected':reference_rays(a,instances,roots,[q])})
    for case in result:
        raw=bytes.fromhex(case['queries_hex']);values=np.frombuffer(raw[:48],dtype='<f4').reshape(3,4)
        owner,sid,_,_=struct.unpack('<4I',raw[48:64]);case['projection']=[*values[0,:3].tolist(),0,*values[1,:3].tolist(),0,0,0,float(owner if owner!=0xffffffff else 1000000),float(sid if sid!=0xffffffff else 0)]
        case['light']=values[2,:3].tolist();case['moved_light']=(2*values[0,:3]-values[2,:3]).tolist()
        # Reconstruct the independently packed inverse scene for the float64
        # oracle, not its BVH traversal. The fixture has one master BLAS root.
        scene=bytes.fromhex(case['scene_hex']);_,_,at,n=struct.unpack('<4I',scene[:16]);instances=[]
        for i in range(n):
            inverse=np.eye(4);inverse[:3]=np.frombuffer(scene,dtype='<f4',count=12,offset=(at+i*16)*4).reshape(3,4);instances.append({'root':0,'matrix':np.linalg.inv(inverse).tolist()})
        a=np.frombuffer(bytes.fromhex(case['bank_hex']),dtype='<f4').reshape(-1,20);_,_,roots=compile_blas(a,[(0,len(a))])
        q={'point':values[0,:3].tolist(),'normal':values[1,:3].tolist(),'reach':float(values[0,3]),'bias':float(values[1,3]),'instance':owner,'source':sid,'light':case['moved_light']}
        case['moved_expected']=reference_rays(a,instances,roots,[q])[0]
        q['reach']=.02;q['bias']=.00033
        case['metric_moved_expected']=reference_rays(a,instances,roots,[q])[0]
        q['light']=case['light'];case['metric_expected']=reference_rays(a,instances,roots,[q])[0]
    path=ROOT/'gpu_compute/fixtures/persistent-visibility-reference.json';path.write_text(json.dumps({'schema':'lie-persistent-reference/1','oracle':'exhaustive float64 source-disk intersections','cases':result},separators=(',',':'))+'\n')
    return result
if __name__=='__main__':print([(c['name'],c['expected'][0],c['moved_expected']) for c in prepare()])
