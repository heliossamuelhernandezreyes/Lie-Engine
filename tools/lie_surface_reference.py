"""Independent float64 visibility oracle: exhaustive bounded pixel-plane hits.

Unlike the GPU march, this enumerates ALL observed cells and solves each
intersection analytically. Fixtures deliberately include coplanar receivers,
holes and rigid transforms. They are not synthetic replacements for wall QA.
"""
import json,math
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
SIZE=64
PITCH=.0005
def exact_visibility(points,normals,active,world,normal,light,right,up,reach=.025,bias=.0003):
    delta=light-world;distance=np.linalg.norm(delta)
    if distance<=bias or normal@delta<=0:return 1.
    direction=delta/distance;origin=world+normal*bias;limit=min(reach,distance-bias)
    if limit<=bias:return 1.
    denominator=normals@direction
    hit=np.divide(np.sum(normals*(points-origin),axis=1),denominator,out=np.full(len(points),-1.),where=abs(denominator)>1e-6)
    locations=origin+hit[:,None]*direction
    screen=np.stack((locations@right,locations@up),axis=1)/PITCH+SIZE/2
    q=np.stack((np.arange(SIZE*SIZE)%SIZE,np.arange(SIZE*SIZE)//SIZE),axis=1)
    valid=active & (hit>bias) & (hit<limit) & np.all((screen>=q)&(screen<q+1),axis=1)
    if not valid.any():return 1.
    u=np.clip((hit[valid]-.75*limit)/(.25*limit),0,1)
    return float(np.min(u*u*(3-2*u)))
def fixture():
    xy=(np.stack(np.meshgrid(np.arange(SIZE),np.arange(SIZE)),axis=-1).reshape(-1,2)+.5-SIZE/2)*PITCH
    cases=[]
    specifications=[('flat',0.,False,False,False),('sloped',.15,False,False,False),('contact_step',0.,True,False,False),('real_hole',0.,True,True,False),('light_reversed',0.,True,False,True),('rotated_step',0.,True,False,False),('translated_step',0.,True,False,False),('outside_contact_range',0.,True,False,False)]
    for name,slope,step,hole,reverse in specifications:
        points=np.column_stack((xy,xy[:,0]*slope));normals=np.tile(np.array([-slope,0,1.])/math.sqrt(1+slope*slope),(len(xy),1));active=np.ones(len(xy),dtype=bool)
        raised=(xy[:,0]>.003)&(xy[:,0]<.015)&(abs(xy[:,1])<.004)
        if step:points[raised,2]+=.003 if name=='outside_contact_range' else .0012
        if hole:active[raised]=False
        # Keep the ray away from exact pixel corners; corner ties are tested
        # separately with the real camera's source coverage acceptance.
        world=np.array([.000137,.000091,slope*.000137]);normal=np.array([-slope,0.,1.]);normal/=np.linalg.norm(normal);light=world+np.array([-1. if reverse else 1.,0.,.1])
        rotation=np.eye(3);translation=np.zeros(3)
        if name=='rotated_step':
            a=.63;b=-.4;rz=np.array([[math.cos(a),-math.sin(a),0],[math.sin(a),math.cos(a),0],[0,0,1]])
            ry=np.array([[math.cos(b),0,math.sin(b)],[0,1,0],[-math.sin(b),0,math.cos(b)]]);rotation=rz@ry
        if name=='translated_step':translation=np.array([.03,-.05,.02])
        points=points@rotation.T+translation;normals=normals@rotation.T;world=rotation@world+translation;normal=rotation@normal;light=rotation@light+translation
        right=rotation[:,0];up=rotation[:,1]
        # Projection subtracts the metric camera origin; oracle equivalent.
        expected=exact_visibility(points-translation,normals,active,world-translation,normal,light-translation,right,up)
        values=np.concatenate((np.column_stack((points,active.astype(float))),np.column_stack((normals,np.zeros(len(xy))))),axis=1).astype('<f4')
        header=np.array([list(world)+[.025],list(normal)+[.0003],list(light)+[32.],list(right)+[PITCH],list(up)+[SIZE],list(translation)+[0]],dtype='<f4')
        cases.append({'name':name,'header_hex':header.tobytes().hex(),'planes_hex':values.tobytes().hex(),'visibility':expected})
    return {'schema':'lie-surface-reference/1','oracle':'exhaustive float64 bounded plane intersections; no ray marching','cases':cases}
def prepare():
    result=fixture();path=ROOT/'gpu_compute/fixtures/surface-reference.json';path.write_text(json.dumps(result,separators=(',',':'))+'\n');return result
def generate_shader():
    shared=(ROOT/'gpu_compute/shaders/lib/lie_contact_surface.glslinc').read_text()
    direct=(ROOT/'gpu_compute/shaders/lib/lie_surface_direct.glslinc').read_text()
    s='''#[compute]
#version 450
layout(local_size_x=64) in;
const float PI=3.141592653589793;
struct Plane {vec4 point;vec4 normal;};
layout(set=0,binding=0,std430) readonly buffer Query {vec4 world;vec4 normal;vec4 light;vec4 right;vec4 up;vec4 origin;} query;
layout(set=0,binding=1,std430) readonly buffer Planes {Plane values[];} planes;
layout(set=0,binding=2,std430) buffer Result {vec4 visibility;vec4 contact_only;vec4 detailed;vec4 source;} result;
layout(set=0,binding=3,std430) readonly buffer Lights {uvec4 header;vec4 values[];} surface_lights;
vec2 lie_surface_project(vec3 world) {vec3 p=world-query.origin.xyz;return vec2(dot(p,query.right.xyz),dot(p,query.up.xyz))/query.right.w+query.up.w*.5;}
bool lie_surface_observed(ivec2 q,out vec3 point,out vec3 normal) {
    int size=int(query.up.w);if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,ivec2(size))))return false;
    Plane p=planes.values[q.y*size+q.x];point=p.point.xyz;normal=p.normal.xyz;return p.point.w>.5;
}
'''+shared+direct+'''
void main() {
    if(gl_GlobalInvocationID.x!=0u)return;
    result.visibility=vec4(lie_contact_visibility(query.world.xyz,query.normal.xyz,query.light.xyz,query.world.w,query.normal.w,int(query.light.w)));
    result.contact_only=vec4(lie_surface_refined(vec3(.2,.3,.4),vec3(.4,.6,.8),vec3(.5),vec3(2.),.25,false),1);
    result.detailed=vec4(lie_surface_refined(vec3(.2,.3,.4),vec3(.4,.6,.8),vec3(.5),vec3(2.),.25,true),1);
    result.source=vec4(lie_surface_unoccluded(0u,vec3(0),vec3(0,0,1)),1);
}
'''
    (ROOT/'gpu_compute/shaders/lie_surface_test.glsl').write_text(s)
if __name__=='__main__':generate_shader();r=prepare();print([(c['name'],c['visibility']) for c in r['cases']])
