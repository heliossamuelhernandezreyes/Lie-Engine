"""Generate independent float64 camera-free disk-intersection GPU fixtures."""
import json,struct,math
from pathlib import Path
import numpy as np
from lie_asset_surface import compile_blas,compile_scene,reference_rays
ROOT=Path(__file__).resolve().parents[1]
def pack_queries(queries):
    return b''.join(np.array([q['point']+[q.get('reach',.025)],q['normal']+[q.get('bias',.0003)],q['light']+[0.]],dtype='<f4').tobytes()+struct.pack('<4I',q.get('instance',0xffffffff),q.get('source',0xffffffff),q.get('camera',0),0) for q in queries)
def cases():
    out=[]
    def add(name,a,instances,queries):
        nodes,refs,roots=compile_blas(a,[(0,len(a))]);scene=compile_scene(instances,roots);values=reference_rays(a,instances,roots,queries)
        out.append({'name':name,'bank_hex':a.astype('<f4').tobytes().hex(),'nodes_hex':nodes.hex(),'leaves_hex':refs.hex(),'scene_hex':scene.hex(),'queries_hex':pack_queries(queries).hex(),'expected':values})
    xx,yy=np.meshgrid(np.linspace(-.018,.018,37),np.linspace(-.006,.006,13));xy=np.column_stack((xx.ravel(),yy.ravel()))
    for name,slope,step,hole,reverse in [('flat',0,False,False,False),('slope',.15,False,False,False),('hidden_step',0,True,False,False),('opening',0,True,True,False),('reverse',0,True,False,True),('range',0,True,False,False),('rotation',0,True,False,False),('nonuniform_scale',0,True,False,False)]:
        a=np.zeros((len(xy),20),dtype='<f4');a[:,:2]=xy;a[:,2]=xy[:,0]*slope;a[:,3]=.0009;a[:,4:7]=[-slope,0,1];a[:,4:7]/=np.linalg.norm(a[:,4:7],axis=1)[:,None]
        raised=(xy[:,0]>.003)&(xy[:,0]<.015)&(abs(xy[:,1])<.004)
        if step:a[raised,2]+=.004 if name=='range' else .0012
        if hole:a=a[~raised]
        matrix=np.eye(4)
        if name=='rotation':
            r=.63;matrix[:3,:3]=[[math.cos(r),0,math.sin(r)],[0,1,0],[-math.sin(r),0,math.cos(r)]];matrix[:3,3]=[.07,-.04,.03]
        if name=='nonuniform_scale':matrix[:3,:3]=np.diag([1.3,.8,1.1])
        point=np.array([.000137,.000091,slope*.000137]);normal=np.array([-slope,0.,1.]);normal/=np.linalg.norm(normal);light=point+[-1. if reverse else 1.,0,.1]
        p=(matrix@np.r_[point,1])[:3];n=np.linalg.inv(matrix[:3,:3]).T@normal;n/=np.linalg.norm(n);l=(matrix@np.r_[light,1])[:3]
        q={'point':p.tolist(),'normal':n.tolist(),'light':l.tolist()}
        add(name,a,[{'root':0,'matrix':matrix.tolist()}],[dict(q,camera=c) for c in [0,17,99]])
    # Receiver source ID is skipped in its own instance only. The SAME source
    # in another instance must still occlude (shared master, distinct pose).
    a=np.zeros((1,20),dtype='<f4');a[0,3]=.003;a[0,6]=1
    transform=np.eye(4);transform[:3,3]=[.009,0,.0012]
    add('same_master_other_instance',a,[{'root':0,'matrix':np.eye(4).tolist()},{'root':0,'matrix':transform.tolist()}],[{'point':[0.,0.,0.],'normal':[0.,0.,1.],'light':[1.,0.,.1],'instance':0,'source':0}])
    return out
def prepare():
    result={'schema':'lie-source-visibility-reference/1','oracle':'float64 exhaustive disk intersections, independent of BVH traversal','cases':cases()}
    (ROOT/'gpu_compute/fixtures/source-visibility-reference.json').write_text(json.dumps(result,separators=(',',':'))+'\n');return result
def generate_shader():
    common=(ROOT/'gpu_compute/shaders/lib/lie_source_visibility.glslinc').read_text()
    s='''#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Samples {vec4 values[];} bank;
layout(set=0,binding=1,std430) readonly buffer BLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=2,std430) readonly buffer Leaves {uint values[];} lie_visibility_refs;
layout(set=0,binding=3,std430) readonly buffer Scene {uint values[];} lie_visibility_scene;
struct Query {vec4 point;vec4 normal;vec4 light;uvec4 identity;};
layout(set=0,binding=4,std430) readonly buffer Queries {Query values[];} queries;
layout(set=0,binding=5,std430) buffer Results {float values[];} results;
layout(push_constant,std430) uniform Count {uint size;} count;
vec4 lie_visibility_position_radius(uint id) {return bank.values[id*5u];}
vec3 lie_visibility_normal(uint id) {return bank.values[id*5u+1u].xyz;}
'''+common+'''
void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=count.size)return;
    Query q=queries.values[i];
    results.values[i]=lie_source_world_visibility(q.point.xyz,q.normal.xyz,q.light.xyz,q.point.w,q.normal.w,q.identity.x,q.identity.y);
}
'''
    (ROOT/'gpu_compute/shaders/lie_source_visibility_test.glsl').write_text(s)
if __name__=='__main__':generate_shader();r=prepare();print([(c['name'],c['expected']) for c in r['cases']])
