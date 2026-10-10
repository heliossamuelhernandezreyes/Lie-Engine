#[compute]
#version 450
// LIE-15: moving rigid masters, analytic visibility and a direct irradiance split.
// All powers and colors are LINEAR RGB. No screen pixels or visible source mesh.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
struct Patch { vec4 center_area; vec4 normal_gray; vec4 filter_absorption; };
struct Light { vec4 position_radius; vec4 power; };
struct Blocker { vec4 lo; vec4 hi; };
struct Triangle { vec4 a; vec4 b; vec4 c; };
struct Sheet { vec4 center_thickness; vec4 right_width; vec4 up_height; vec4 sigma_ior; };
layout(set=0,binding=13,std430) readonly buffer Sheets { Sheet values[]; } sheets;
layout(set=0,binding=0,std430) readonly buffer Patches { Patch values[]; } patches;
layout(set=0,binding=1,std430) readonly buffer Lights { Light values[]; } lights;
layout(set=0,binding=2,std430) readonly buffer Factors { float values[]; } factors;
layout(set=0,binding=3,std430) buffer Weights { float values[]; } weights;
layout(set=0,binding=4,std430) buffer Caps { float values[]; } caps;
layout(set=0,binding=5,std430) buffer FrontierA { vec4 values[]; } frontier_a;
layout(set=0,binding=6,std430) buffer FrontierB { vec4 values[]; } frontier_b;
layout(set=0,binding=7,std430) buffer Received { vec4 values[]; } received;
layout(set=0,binding=8,std430) readonly buffer Config { ivec4 dims; vec4 tuning; vec4 radii; } cfg;
layout(set=0,binding=12,std430) readonly buffer RadiusScale { float values[]; } radius_scale;
layout(set=0,binding=9,std430) readonly buffer Blockers { Blocker values[]; } blockers;
layout(set=0,binding=11,std430) readonly buffer Triangles { Triangle values[]; } triangles;
layout(rgba32f,set=0,binding=10) uniform writeonly image2D irradiance;
layout(push_constant,std430) uniform Phase { ivec4 data; } phase;
const float PI=3.141592653589793;
layout(rgba32f,set=0,binding=15) uniform writeonly image2D direct_irradiance;

struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 shape; vec4 material; vec4 pbr; };
layout(set=0,binding=14,std430) readonly buffer Instances { Instance values[]; } instances;
vec3 local_point(vec3 p, Instance s) {
    vec3 q=p-s.origin.xyz;
    return vec3(dot(q,s.x.xyz)/dot(s.x.xyz,s.x.xyz),dot(q,s.y.xyz)/dot(s.y.xyz,s.y.xyz),dot(q,s.z.xyz)/dot(s.z.xyz,s.z.xyz));
}
vec3 world_point(vec3 p, Instance s) { return s.origin.xyz+s.x.xyz*p.x+s.y.xyz*p.y+s.z.xyz*p.z; }
vec3 world_normal(vec3 n, Instance s) {
    return normalize(s.x.xyz*n.x/dot(s.x.xyz,s.x.xyz)+s.y.xyz*n.y/dot(s.y.xyz,s.y.xyz)+s.z.xyz*n.z/dot(s.z.xyz,s.z.xyz));
}
bool box_hit(vec3 a,vec3 b,Instance s) {
    if(s.pbr.w<.5) return false;
    vec3 p=local_point(a,s),d=local_point(b,s)-p;
    float lo=.001,hi=.999;
    for(int axis=0;axis<3;axis++) {
        if(abs(d[axis])<1e-10) { if(abs(p[axis])>s.shape[axis]) return false; }
        else {
            float u=(-s.shape[axis]-p[axis])/d[axis],v=(s.shape[axis]-p[axis])/d[axis];
            lo=max(lo,min(u,v)); hi=min(hi,max(u,v));
        }
    }
    return lo<=hi;
}
bool rigid_blocked(vec3 a,vec3 b) {
    for(int k=0;k<15;k++) if(box_hit(a,b,instances.values[k])) return true;
    return false;
}

vec3 transmittance(vec3 a, vec3 b) {
    vec3 value=vec3(1.0), delta=b-a;
    float distance=length(delta);
    if(distance<1e-10) return value;
    for(int k=0;k<int(cfg.radii.w);k++) {
        Sheet s=sheets.values[k];
        vec3 n=cross(s.right_width.xyz,s.up_height.xyz);
        float denominator=dot(delta,n);
        if(abs(denominator)<1e-8) continue;
        float t=dot(s.center_thickness.xyz-a,n)/denominator;
        if(t<=0.001 || t>=0.999) continue;
        vec3 local=a+t*delta-s.center_thickness.xyz;
        if(abs(dot(local,s.right_width.xyz))>s.right_width.w || abs(dot(local,s.up_height.xyz))>s.up_height.w) continue;
        float ci=clamp(abs(denominator)/distance,0.0,1.0), eta=s.sigma_ior.w;
        float ct=sqrt(max(0.0,1.0-(1.0-ci*ci)/(eta*eta)));
        float rs=(ci-eta*ct)/max(ci+eta*ct,1e-8);
        float rp=(eta*ci-ct)/max(eta*ci+ct,1e-8);
        float f=(rs*rs+rp*rp)*0.5;
        value*=pow(1.0-f,2.0)*exp(-s.sigma_ior.rgb*s.center_thickness.w/max(ct,1e-6));
    }
    return value;
}

bool blocked(vec3 a, vec3 b) {
    if(rigid_blocked(a,b)) return true;
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
    for(int k=0;k<int(cfg.tuning.z);k++) {
        Triangle tri=triangles.values[k];
        vec3 e1=tri.b.xyz-tri.a.xyz, e2=tri.c.xyz-tri.a.xyz;
        vec3 h=cross(delta,e2);
        float det=dot(e1,h);
        if(abs(det)<1e-8) continue;
        vec3 s=a-tri.a.xyz;
        float u=dot(s,h)/det;
        if(u<0.0 || u>1.0) continue;
        vec3 q=cross(s,e1);
        float v=dot(delta,q)/det;
        if(v<0.0 || u+v>1.0) continue;
        float t=dot(e2,q)/det;
        if(t>=0.001 && t<=0.999) return true;
    }
    return false;
}

vec3 rho(uint i) {
    Patch p=patches.values[i];
    return clamp(p.filter_absorption.rgb,vec3(0),vec3(1))
        *(1.0-clamp(p.filter_absorption.a,0.0,1.0))
        *clamp(p.normal_gray.w,0.0,1.0);
}

float reach(uint i, float parent, vec3 power) {
    if(cfg.tuning.w<0.5) return 0.0;
    float energy=max(power.r,max(power.g,power.b));
    vec3 survival=rho(i);
    float reflection=max(survival.r,max(survival.g,survival.b));
    return min(min(parent*cfg.radii.y*sqrt(reflection),cfg.radii.x*sqrt(energy/cfg.radii.z)),cfg.radii.x)*radius_scale.values[i];
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
        if(d2>1e-10 && radius>0.0 && !blocked(patches.values[p].center_area.xyz+patches.values[p].normal_gray.xyz*.003,lights.values[l].position_radius.xyz)) {
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
        float parent=0.0;
        for(uint l=0u;l<count;l++) {
            vec3 power=lights.values[l].power.rgb;
            float w=weights.values[l*n+i]/caps.values[l];
            incoming+=power*w*transmittance(patches.values[i].center_area.xyz,lights.values[l].position_radius.xyz);
            if(w*max(power.r,max(power.g,power.b))>0.0) parent=max(parent,lights.values[l].position_radius.w);
        }
        received.values[i]=vec4(incoming,0.0);
        imageStore(direct_irradiance,ivec2(i,0),vec4(incoming/max(patches.values[i].center_area.w,1e-8),1.0));
        frontier_a.values[i]=vec4(incoming*rho(i),reach(i,parent,incoming*rho(i)));
        frontier_b.values[i]=vec4(0.0);
        return;
    }
    if(phase.data.x==3) {
        // Each generation consumes ONLY the preceding frontier. Never feed
        // accumulated total power back into the transport graph.
        vec3 incoming=vec3(0.0);
        float parent=0.0;
        for(uint source=0u;source<n;source++) {
            vec4 emitted=phase.data.y==0?frontier_a.values[source]:frontier_b.values[source];
            float weight=factors.values[source*n+i];
            if(cfg.tuning.w>0.5) {
                float d=distance(patches.values[source].center_area.xyz,patches.values[i].center_area.xyz);
                weight*=emitted.w>0.0?pow(max(0.0,1.0-pow(d/emitted.w,4.0)),2.0):0.0;
            }
            if(weight>0.0) incoming+=emitted.rgb*weight*transmittance(patches.values[source].center_area.xyz,patches.values[i].center_area.xyz);
            if(weight*max(emitted.r,max(emitted.g,emitted.b))>0.0) parent=max(parent,emitted.w);
        }
        received.values[i].rgb+=incoming;
        vec3 reflected=incoming*rho(i);
        if(max(reflected.r,max(reflected.g,reflected.b))<cfg.tuning.y) reflected=vec3(0.0);
        float radius=reach(i,parent,reflected);
        if(phase.data.y==0) frontier_b.values[i]=vec4(reflected,radius);
        else frontier_a.values[i]=vec4(reflected,radius);
        return;
    }
    if(phase.data.x==4) {
        vec3 e=received.values[i].rgb/max(patches.values[i].center_area.w,1e-8);
        imageStore(irradiance,ivec2(int(i),0),vec4(e,1.0));
    }
}
