"""Sparse scene bridge for the LIE35 passive angular budgets.

Existing WALL04 CSR visibilities are retained; diffuse and glossy opaque
frontiers use captured material means and a power-weighted incident direction.
Transmission remains in the isolated LIE35 oracle, not this opaque wall graph.
"""
from pathlib import Path
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]

def generate():
 s=(ROOT/'gpu_compute/shaders/lie_wall04_transport_sparse.glsl').read_text()
 s=replace(s,'const float PI=3.141592653589793;',r'''
const float PI=3.141592653589793;
struct Optical { vec4 albedo_roughness; vec4 properties; vec4 sigma; vec4 normal_pad; };
layout(set=0,binding=18,std430) buffer IncidentDirections { vec4 values[]; } incidents;
layout(set=0,binding=19,std430) readonly buffer OpticalCodes { uvec4 config; Optical values[]; } optical;
layout(set=0,binding=20,std430) buffer AngularCaps { vec4 values[]; } angular_caps;
layout(set=0,binding=21,std430) readonly buffer OutgoingGraph { uint values[]; } outgoing_graph;
layout(set=0,binding=22,std430) readonly buffer SourceFrontCaps { vec4 values[]; } front_caps;
vec3 incident(uint source,int ping) {return incidents.values[source*2u+uint(ping)].xyz;}
void parts(uint source,vec3 direction,out vec3 D,out vec3 R) {
    Optical o=optical.values[source];vec3 n=normalize(o.normal_pad.xyz);
    float ci=clamp(-dot(n,direction),0.,1.);
    if(ci<=1e-8) {D=vec3(0);R=vec3(0);return;}
    float metal=o.properties.x,ior=o.properties.z;
    float f_dielectric=pow((ior-1.)/(ior+1.),2.);
    vec3 f0=mix(vec3(f_dielectric),o.albedo_roughness.rgb,metal);
    vec3 f=f0+(vec3(1)-f0)*pow(1.-ci,5.);
    float absorb=clamp(patches.values[source].filter_absorption.w,0.,1.);
    D=(1.-metal)*(vec3(1)-f)*o.albedo_roughness.rgb*(1.-absorb);
    R=f*(1.-absorb);
    vec3 cap=max(vec3(1),D+R);D/=cap;R/=cap;
}
vec2 angular_weight(uint source,uint dst,float F,vec3 travel,float radius) {
    vec3 delta=patches.values[dst].center_area.xyz-patches.values[source].center_area.xyz;
    float d=length(delta);if(d<=1e-8)return vec2(0);
    vec3 out_dir=delta/d,n=normalize(optical.values[source].normal_pad.xyz);
    float baseline=max(dot(patches.values[source].normal_gray.xyz,out_dir),1e-6);
    float diffuse=max(dot(n,out_dir),0.);
    float rough=max(optical.values[source].albedo_roughness.w,.025);
    float expo=clamp(2./(rough*rough)-2.,1.,2048.);
    float gloss=diffuse>0.?pow(max(dot(reflect(travel,n),out_dir),0.),expo):0.;
    float fade=cfg.tuning.w>.5?(radius>0.?pow(max(0.,1.-pow(d/radius,4.)),2.):0.):1.;
    // F already contains receiver geometry/visibility and cosine of the old
    // source normal. Replace that source angular factor once, never twice.
    return F*fade*vec2(diffuse,gloss)/baseline;
}
''')
 # Clip a light-only AABB against an exposed-front plane measured from the
 # source scan. This never alters the visual surface or spatial collider.
 s=replace(s,'        if(lo<=hi) return true;',r'''        if(optical.config.z!=0u && lo<=hi) {
            vec4 plane=front_caps.values[k];
            float side=dot(plane.xyz,a)-plane.w, rate=dot(plane.xyz,delta);
            if(abs(rate)<1e-9) {if(side>0.){lo=1.;hi=0.;}}
            else if(rate>0.)hi=min(hi,-side/rate);
            else lo=max(lo,-side/rate);
        }
        if (lo <= hi) return true;''')
 # Locate exact current source text rather than silently generate stale code.
 s=replace(s,'        frontier_a.values[i]=vec4(incoming*rho(i),reach(i,parent,incoming*rho(i)));',r'''
        vec3 travel=vec3(0);
        for(uint l=0u;l<uint(cfg.dims.y);l++) {
            float w=weights.values[l*n+i]/caps.values[l];
            vec3 flux=lights.values[l].power.rgb*w*transmittance(patches.values[i].center_area.xyz,lights.values[l].position_radius.xyz);
            travel+=normalize(patches.values[i].center_area.xyz-lights.values[l].position_radius.xyz)*max(flux.r,max(flux.g,flux.b));
        }
        travel=dot(travel,travel)>1e-16?normalize(travel):-patches.values[i].normal_gray.xyz;
        incidents.values[i*2u]=vec4(travel,0);
        vec3 power=incoming*rho(i);
        if(optical.config.x!=0u) {vec3 D,R;parts(i,travel,D,R);power=incoming*(D+R);}
        frontier_a.values[i]=vec4(optical.config.x!=0u?incoming:power,reach(i,parent,power));''')
 s=replace(s,'    if(phase.data.x==3) {',r'''
    if(phase.data.x==5) {
        if(optical.config.x==0u)return;
        vec4 frontier=phase.data.y==0?frontier_a.values[i]:frontier_b.values[i];
        vec2 sum=vec2(0);uint ob=outgoing_graph.values[2],eb=outgoing_graph.values[3];
        for(uint e=outgoing_graph.values[ob+i];e<outgoing_graph.values[ob+i+1u];e++) {
            uint dst=outgoing_graph.values[eb+e*2u];float F=uintBitsToFloat(outgoing_graph.values[eb+e*2u+1u]);
            sum+=angular_weight(i,dst,F,incident(i,phase.data.y),frontier.w);
        }
        angular_caps.values[i]=vec4(max(sum,vec2(1)),0,0);return;
    }
    if(phase.data.x==3 && optical.config.x!=0u) {
        uint ob=factors.values[2],eb=factors.values[3];vec3 incoming=vec3(0),travel_sum=vec3(0);float parent=0.;
        for(uint e=factors.values[ob+i];e<factors.values[ob+i+1u];e++) {
            uint src=factors.values[eb+e*2u];float F=uintBitsToFloat(factors.values[eb+e*2u+1u]);
            vec4 emitted=phase.data.y==0?frontier_a.values[src]:frontier_b.values[src];
            vec3 D,R;parts(src,incident(src,phase.data.y),D,R);
            vec2 w=angular_weight(src,i,F,incident(src,phase.data.y),emitted.w)/angular_caps.values[src].xy;
            vec3 flux=emitted.rgb*(D*w.x+R*w.y)*transmittance(patches.values[src].center_area.xyz,patches.values[i].center_area.xyz);
            incoming+=flux;
            float strength=max(flux.r,max(flux.g,flux.b));
            if(strength>0.) {parent=max(parent,emitted.w);travel_sum+=normalize(patches.values[i].center_area.xyz-patches.values[src].center_area.xyz)*strength;}
        }
        received.values[i].rgb+=incoming;
        vec3 travel=dot(travel_sum,travel_sum)>1e-16?normalize(travel_sum):-patches.values[i].normal_gray.xyz;
        incidents.values[i*2u+uint(1-phase.data.y)]=vec4(travel,0);
        vec3 D,R;parts(i,travel,D,R);float radius=reach(i,parent,incoming*(D+R));
        if(phase.data.y==0)frontier_b.values[i]=vec4(incoming,radius);
        else frontier_a.values[i]=vec4(incoming,radius);
        return;
    }
    if(phase.data.x==3) {''')
 return s
if __name__=='__main__':(ROOT/'gpu_compute/shaders/lie_wall05_directional_sparse.glsl').write_text(generate())
