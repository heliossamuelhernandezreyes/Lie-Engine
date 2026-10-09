#[compute]
#version 450
// LIE-11: light codes -> node power -> bounded diffuse secondary sources.
// All powers and colors are LINEAR RGB. No screen pixels or visible source mesh.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
struct Patch { vec4 center_area; vec4 normal_gray; vec4 filter_absorption; };
struct Light { vec4 position_radius; vec4 power; };
struct Blocker { vec4 lo; vec4 hi; };
layout(set=0,binding=0,std430) readonly buffer Patches { Patch values[]; } patches;
layout(set=0,binding=1,std430) readonly buffer Lights { Light values[]; } lights;
layout(set=0,binding=2,std430) readonly buffer Factors { float values[]; } factors;
layout(set=0,binding=3,std430) buffer Weights { float values[]; } weights;
layout(set=0,binding=4,std430) buffer Caps { float values[]; } caps;
layout(set=0,binding=5,std430) buffer FrontierA { vec4 values[]; } frontier_a;
layout(set=0,binding=6,std430) buffer FrontierB { vec4 values[]; } frontier_b;
layout(set=0,binding=7,std430) buffer Received { vec4 values[]; } received;
layout(set=0,binding=8,std430) readonly buffer Config { ivec4 dims; vec4 tuning; } cfg;
layout(set=0,binding=9,std430) readonly buffer Blockers { Blocker values[]; } blockers;
layout(rgba32f,set=0,binding=10) uniform writeonly image2D irradiance;
layout(push_constant,std430) uniform Phase { ivec4 data; } phase;
const float PI=3.141592653589793;

bool blocked(vec3 a, vec3 b) {
    vec3 delta=b-a;
    for(int k=0;k<cfg.dims.w;k++) {
        float lo=0.001, hi=0.999;
        for(int axis=0;axis<3;axis++) {
            if(abs(delta[axis])<1e-8) {
                if(a[axis]<blockers.values[k].lo[axis] || a[axis]>blockers.values[k].hi[axis]) {
                    lo=1.0; hi=0.0; break;
                }
            } else {
                float near_t=(blockers.values[k].lo[axis]-a[axis])/delta[axis];
                float far_t=(blockers.values[k].hi[axis]-a[axis])/delta[axis];
                lo=max(lo,min(near_t,far_t)); hi=min(hi,max(near_t,far_t));
            }
        }
        if(lo<=hi) return true;
    }
    return false;
}

vec3 rho(uint i) {
    Patch p=patches.values[i];
    return clamp(p.filter_absorption.rgb,vec3(0),vec3(1))
        *(1.0-clamp(p.filter_absorption.a,0.0,1.0))
        *clamp(p.normal_gray.w,0.0,1.0);
}

void main() {
    uint i=gl_GlobalInvocationID.x;
    uint n=uint(cfg.dims.x), count=uint(cfg.dims.y);
    if(phase.data.x==0) {
        if(i>=n*count) return;
        uint l=i/n, p=i%n;
        vec3 delta=lights.values[l].position_radius.xyz-patches.values[p].center_area.xyz;
        float d2=dot(delta,delta), radius=lights.values[l].position_radius.w;
        float value=0.0;
        if(d2>1e-10 && radius>0.0 && !blocked(patches.values[p].center_area.xyz,lights.values[l].position_radius.xyz)) {
            float cosine=max(dot(patches.values[p].normal_gray.xyz,delta*inversesqrt(d2)),0.0);
            float relative=sqrt(d2)/radius;
            float window=pow(max(0.0,1.0-pow(relative,4.0)),2.0);
            value=patches.values[p].center_area.w*cosine*window/(4.0*PI*max(d2,cfg.tuning.x));
        }
        weights.values[i]=value;
        return;
    }
    if(phase.data.x==1) {
        if(i>=count) return;
        float total=0.0;
        for(uint p=0u;p<n;p++) total+=weights.values[i*n+p];
        caps.values[i]=max(1.0,total);
        return;
    }
    if(i>=n) return;
    if(phase.data.x==2) {
        vec3 incoming=vec3(0.0);
        for(uint l=0u;l<count;l++) incoming+=lights.values[l].power.rgb*weights.values[l*n+i]/caps.values[l];
        received.values[i]=vec4(incoming,0.0);
        frontier_a.values[i]=vec4(incoming*rho(i),0.0);
        frontier_b.values[i]=vec4(0.0);
        return;
    }
    if(phase.data.x==3) {
        // Each generation consumes ONLY the preceding frontier. Never feed
        // accumulated total power back into the transport graph.
        vec3 incoming=vec3(0.0);
        for(uint source=0u;source<n;source++) {
            vec3 power=phase.data.y==0?frontier_a.values[source].rgb:frontier_b.values[source].rgb;
            incoming+=power*factors.values[source*n+i];
        }
        received.values[i].rgb+=incoming;
        vec3 reflected=incoming*rho(i);
        if(max(reflected.r,max(reflected.g,reflected.b))<cfg.tuning.y) reflected=vec3(0.0);
        if(phase.data.y==0) frontier_b.values[i]=vec4(reflected,0.0);
        else frontier_a.values[i]=vec4(reflected,0.0);
        return;
    }
    if(phase.data.x==4) {
        vec3 e=received.values[i].rgb/max(patches.values[i].center_area.w,1e-8);
        imageStore(irradiance,ivec2(int(i),0),vec4(e,1.0));
    }
}
