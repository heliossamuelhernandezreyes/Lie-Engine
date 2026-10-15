"""Independent float64 emitter integral and scatter transport fixtures."""
import copy,json,math
from pathlib import Path
import numpy as np
from lie_light_field import fixture_cases,solve,sources
ROOT=Path(__file__).resolve().parents[1]
def quadrature(center,size,order=2):
    x,w=np.polynomial.legendre.leggauss(order)
    return [(np.asarray(center)+[a*size[0]/2,b*size[1]/2,0],wa*wb/4) for b,wb in zip(x,w) for a,wa in zip(x,w)]
def integral(center,size,receiver,normal,order=64):
    value=0.
    for p,w in quadrature(center,size,order):
        d=np.asarray(receiver)-p;r=np.linalg.norm(d);direction=d/r
        value+=w*max(-direction[2],0)*max(np.dot(normal,-direction),0)/(math.pi*r*r)
    return value
def cases():
    base=fixture_cases()['two_colored_lights'];original=base['model'];pack={k:bytes.fromhex(v) for k,v in base['sources_hex'].items()};result={}
    for name in ['two_panels','key_only','fill_only','all_off','backwards','small_panel','large_panel','point_legacy','edge_occlusion','merged_legacy']:
        model=copy.deepcopy(original);lights=[];normals=[];desc=np.zeros((8,4),dtype='<f4')
        for side in range(2):
            center=[-.7 if side==0 else .7,.1 if side==0 else -.1,2.5];power=np.array([12.,3.,1.] if side==0 else [1.,4.,14.])
            if name=='all_off' or name=='key_only' and side==1 or name=='fill_only' and side==0:power*=0
            size=[.03,.02] if name=='small_panel' else [.9,.7] if name=='large_panel' else [.3,.225]
            samples=[(np.array(center),1.)] if name=='point_legacy' else quadrature(center,size)
            for position,weight in samples:
                i=len(lights);n=None if name=='point_legacy' else [0.,0.,1. if name=='backwards' else -1.]
                lights.append({'position':position.tolist(),'radius':6.,'power_rgb':(power*weight).tolist()});normals.append(n)
                if n is not None:desc[i]=[*n,1.]
        model['lights']=lights;packets=copy.deepcopy(pack)
        if name=='edge_occlusion':
            model['blockers']=[[[.35,-1.,1.2],[.6,1.,1.3]]]
        separate=name!='merged_legacy'
        result[name]={'model':model,'sources_hex':{k:v.hex() for k,v in packets.items()},'separate':separate,'emission_hex':desc.tobytes().hex(),'output':solve(model,packets,separate,emission_normals=normals)}
    return result
def prepare():
    result={'schema':'lie-area-reference/1','reference':'float64 scatter; independent Gaussian positions and hemisphere emission','cases':cases()}
    path=ROOT/'gpu_compute/fixtures/area-field-reference.json';path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps({'cases':len(prepare()['cases'])}))
