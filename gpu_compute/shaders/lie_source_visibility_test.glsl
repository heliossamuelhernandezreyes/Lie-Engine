#[compute]
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
// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};
LieSourceNode lie_blas_node(uint i) {
    LieSourceNode n;n.lo=lie_visibility_blas.values[i*2u];n.hi=lie_visibility_blas.values[i*2u+1u];return n;
}
vec4 lie_scene_vec(uint at) {
    return uintBitsToFloat(uvec4(lie_visibility_scene.values[at],lie_visibility_scene.values[at+1u],lie_visibility_scene.values[at+2u],lie_visibility_scene.values[at+3u]));
}
LieSourceNode lie_scene_node(uint i) {
    LieSourceNode n;n.lo=lie_scene_vec(4u+i*8u);n.hi=lie_scene_vec(8u+i*8u);return n;
}
bool lie_source_box(vec3 o,vec3 d,vec3 low,vec3 high,float minimum,float maximum) {
    float enter=minimum,leave=maximum;
    for(int k=0;k<3;k++) {
        if(abs(d[k])<1e-12) {if(o[k]<low[k] || o[k]>high[k])return false;}
        else {float a=(low[k]-o[k])/d[k],b=(high[k]-o[k])/d[k];enter=max(enter,min(a,b));leave=min(leave,max(a,b));}
    }
    return enter<=leave;
}
float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {
    uint end=floatBitsToUint(lie_blas_node(root).lo.w),i=root;
    float nearest=maximum;
    while(i<end) {
        LieSourceNode n=lie_blas_node(i);uint escape=floatBitsToUint(n.lo.w),leaf=floatBitsToUint(n.hi.w);
        if(!lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest)){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint count=lie_visibility_refs.values[leaf];
        for(uint k=0u;k<count;k++) {
            uint sid=lie_visibility_refs.values[leaf+1u+k];if(sid==skip)continue;
            vec4 source=lie_visibility_position_radius(sid);vec3 normal=lie_visibility_normal(sid);
            float denominator=dot(normal,d);if(abs(denominator)<1e-8)continue;
            float t=dot(normal,source.xyz-o)/denominator;if(t<=minimum || t>=nearest)continue;
            vec3 delta=o+t*d-source.xyz;
            if(dot(delta,delta)>source.w*source.w)continue;
            nearest=t;if(nearest<=early)return nearest;
        }
        i=escape;
    }
    return nearest;
}
float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {
    vec3 delta=light-point;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 o=point+normal*bias,d=delta/distance_to_light;
    float limit=min(reach,distance_to_light-bias),nearest=limit;
    if(limit<=bias)return 1.;
    uint i=0u,end=lie_visibility_scene.values[0];
    while(i<end) {
        LieSourceNode node=lie_scene_node(i);uint escape=floatBitsToUint(node.lo.w),leaf=floatBitsToUint(node.hi.w);
        if(!lie_source_box(o,d,node.lo.xyz,node.hi.xyz,bias,nearest)){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint list=lie_visibility_scene.values[1]+leaf,count=lie_visibility_scene.values[list];
        for(uint k=0u;k<count;k++) {
            uint instance=lie_visibility_scene.values[list+1u+k];uint at=lie_visibility_scene.values[2]+instance*16u;
            vec4 x=lie_scene_vec(at),y=lie_scene_vec(at+4u),z=lie_scene_vec(at+8u);
            vec3 local_o=vec3(dot(x,vec4(o,1)),dot(y,vec4(o,1)),dot(z,vec4(o,1)));
            vec3 local_d=vec3(dot(x.xyz,d),dot(y.xyz,d),dot(z.xyz,d));
            uint root=lie_visibility_scene.values[at+12u];
            nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu);
            if(nearest<=.75*limit)return 0.;
        }
        i=escape;
    }
    return smoothstep(.75*limit,limit,nearest);
}

void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=count.size)return;
    Query q=queries.values[i];
    results.values[i]=lie_source_world_visibility(q.point.xyz,q.normal.xyz,q.light.xyz,q.point.w,q.normal.w,q.identity.x,q.identity.y);
}
