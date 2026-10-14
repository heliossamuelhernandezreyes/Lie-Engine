#[compute]
#version 450

// LIE35: opt-in proof of directional RGB optical-code propagation.
// Float32 GPU equivalent of tools/lie35_directional_reference.py.
// Deliberately small N<=128 and dense weights: NOT a wall runtime shader.
// Phase 0: source->receiver angular weights; 1: energy denominators;
// 2: receiver gathers. No float atomics, no mesh draw, no generated photons.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;

struct Emitter {
    vec4 position_radius;
    vec4 normal_roughness;
    vec4 incident_metallic;
    vec4 albedo_transmission;
    vec4 sigma_thickness;
    vec4 power_ior;
};
struct Receiver { vec4 position_area; vec4 normal_visibility; };

layout(set=0,binding=0,std430) readonly buffer Sources { Emitter items[]; } emitters;
layout(set=0,binding=1,std430) readonly buffer Targets { Receiver items[]; } receivers;
layout(set=0,binding=2,std430) buffer EdgeWeights { vec4 items[]; } edges;
layout(set=0,binding=3,std430) buffer Normalizers { vec4 items[]; } norms;
layout(set=0,binding=4,std430) buffer OutputPower { vec4 items[]; } outputs;
layout(push_constant,std430) uniform Config { ivec4 dims; } cfg;

const float PI=3.14159265358979323846;

float finite_safe(float x) {return isnan(x)||isinf(x)?0.0:x;}
vec3 unit(vec3 v) {return v*inversesqrt(max(dot(v,v),1e-20));}
float abs_fresnel(float f0,float ci) {return f0+(1.0-f0)*pow(max(1.0-ci,0.0),5.0);}

void optical_budget(Emitter src,out vec3 diffuse,out vec3 specular,out vec3 transmitted,
                    out vec3 normal,out vec3 incidence,out vec3 mirror,out vec3 refracted) {
    normal=unit(src.normal_roughness.xyz);
    incidence=unit(src.incident_metallic.xyz);
    diffuse=vec3(0.0);specular=vec3(0.0);transmitted=vec3(0.0);
    mirror=reflect(incidence,normal);refracted=vec3(0.0);
    if(dot(normal,incidence)>=-1e-10) return;
    float metallic=clamp(src.incident_metallic.w,0.0,1.0);
    float transmission=clamp(src.albedo_transmission.w,0.0,1.0);
    float ior=clamp(src.power_ior.w,1.0,3.0);
    float ci=clamp(-dot(incidence,normal),0.0,1.0);
    float eta=1.0/ior;
    float k=1.0-eta*eta*(1.0-ci*ci);
    if(k>=0.0) refracted=unit(eta*incidence+(eta*ci-sqrt(k))*normal);
    float fdielectric=pow((ior-1.0)/(ior+1.0),2.0);
    vec3 albedo=clamp(src.albedo_transmission.xyz,vec3(0),vec3(1));
    vec3 f0=mix(vec3(fdielectric),albedo,metallic);
    vec3 fresnel=f0+(vec3(1.0)-f0)*pow(1.0-ci,5.0);
    if(k<0.0) fresnel=vec3(1.0);
    diffuse=(vec3(1.0)-fresnel)*(1.0-metallic)*(1.0-transmission)*albedo;
    specular=fresnel;
    float ct=k<0.0?1.0:max(-dot(refracted,normal),0.001);
    transmitted=(vec3(1.0)-fresnel)*(1.0-metallic)*transmission
        *exp(-max(src.sigma_thickness.xyz,vec3(0))*src.sigma_thickness.w/ct);
    if(k<0.0) transmitted=vec3(0);
    vec3 total=diffuse+specular+transmitted;
    vec3 cap=max(total,vec3(1.0));
    diffuse/=cap;specular/=cap;transmitted/=cap;
}

vec3 angular_weight(Emitter src,Receiver dst) {
    vec3 dir=dst.position_area.xyz-src.position_radius.xyz;
    float d2=dot(dir,dir),r=src.position_radius.w;
    if(d2<=1e-10 || r<=0.0 || d2>=r*r || dst.position_area.w<=0.0 || dst.normal_visibility.w<0.5)
        return vec3(0);
    float distance=sqrt(d2);
    vec3 outgoing=dir/distance;
    float facing=max(dot(unit(dst.normal_visibility.xyz),-outgoing),0.0);
    if(facing<=0.0) return vec3(0);
    float fade=pow(max(0.0,1.0-pow(distance/r,4.0)),2.0);
    float geometry=dst.position_area.w*facing*fade/(4.0*PI*max(d2,0.0025));
    vec3 diffuse,spec,through,n,incident,mirror,refracted;
    optical_budget(src,diffuse,spec,through,n,incident,mirror,refracted);
    if(dot(n,incident)>=-1e-10) return vec3(0);
    float rough=clamp(src.normal_roughness.w,0.025,1.0);
    float exponent=clamp(2.0/(rough*rough)-2.0,1.0,2048.0);
    float diff=max(dot(n,outgoing),0.0);
    float glossy=diff>0.0?pow(max(dot(unit(mirror),outgoing),0.0),exponent):0.0;
    float refracted_weight=dot(n,outgoing)<0.0&&dot(refracted,refracted)>0.5?
        pow(max(dot(refracted,outgoing),0.0),max(1.0,exponent*0.5)):0.0;
    return geometry*vec3(diff,glossy,refracted_weight);
}

void main() {
    uint id=gl_GlobalInvocationID.x;
    uint ns=uint(cfg.dims.y),nr=uint(cfg.dims.z);
    if(ns==0u||nr==0u||ns>128u||nr>128u) return;
    if(cfg.dims.x==0) {
        if(id>=ns) return;
        Emitter src=emitters.items[id];
        for(uint j=0u;j<nr;j++)
            edges.items[id*nr+j]=vec4(angular_weight(src,receivers.items[j]),0.0);
        return;
    }
    if(cfg.dims.x==1) {
        if(id>=ns) return;
        vec3 total=vec3(0.0);
        for(uint j=0u;j<nr;j++) total+=edges.items[id*nr+j].xyz;
        norms.items[id]=vec4(max(total,vec3(1.0)),0.0);
        return;
    }
    if(cfg.dims.x==2) {
        if(id>=nr) return;
        vec3 received=vec3(0.0);
        for(uint source=0u;source<ns;source++) {
            Emitter src=emitters.items[source];
            vec3 diffuse,spec,transmitted,n,incident,mirror,refracted;
            optical_budget(src,diffuse,spec,transmitted,n,incident,mirror,refracted);
            vec3 weights=edges.items[source*nr+id].xyz/max(norms.items[source].xyz,vec3(1.0));
            vec3 ratio=diffuse*weights.x+spec*weights.y+transmitted*weights.z;
            received+=src.power_ior.rgb*ratio;
        }
        outputs.items[id]=vec4(max(received,vec3(0.0)),1.0);
    }
}
