#[compute]
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
// Bounded screen-space contact test. The host supplies projection and a REAL
// observed tangent plane per pixel; recovered holes never become occluders.
// The plane is bounded by its observed pixel cell, not an infinite surface or
// a guessed solid thickness. Missing/off-screen geometry contributes no shadow.
float lie_contact_visibility(vec3 world,vec3 normal,vec3 light,float reach,float bias,int steps) {
    vec3 delta=light-world;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 direction=delta/distance_to_light;
    vec3 origin=world+normal*bias;
    float limit=min(reach,distance_to_light-bias);
    if(limit<=bias)return 1.;
    float visibility=1.;
    for(int k=0;k<32;k++) {
        if(k>=steps)break;
        float t=limit*(float(k)+.5)/float(steps);
        vec2 screen=lie_surface_project(origin+direction*t);
        ivec2 q=ivec2(floor(screen));vec3 point,plane_normal;
        if(!lie_surface_observed(q,point,plane_normal))continue;
        float denominator=dot(plane_normal,direction);
        if(abs(denominator)<1e-6)continue;
        float hit=dot(plane_normal,point-origin)/denominator;
        if(hit<=bias || hit>=limit)continue;
        vec2 hit_screen=lie_surface_project(origin+direction*hit);
        if(any(lessThan(hit_screen,vec2(q))) || any(greaterThanEqual(hit_screen,vec2(q)+1.)))continue;
        // Fade only near the metric traversal limit; direct-only attenuation.
        visibility=min(visibility,smoothstep(.75*limit,limit,hit));
        if(visibility<=0.)break;
    }
    return clamp(visibility,0.,1.);
}
// Same point-source units, distance floor, range window and normalized power
// as the finite-patch field. No second emitter budget and no invented relief.
vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {
    vec4 source=surface_lights.values[l*2u],power=surface_lights.values[l*2u+1u];
    vec3 delta=source.xyz-world;float d2=dot(delta,delta);
    if(d2<=1e-10 || source.w<=0.)return vec3(0);
    float cosine=max(dot(normal,delta*inversesqrt(d2)),0.);
    float fade=pow(max(0.,1.-pow(sqrt(d2)/source.w,4.)),2.);
    return power.rgb*(cosine*fade/(4.*PI*max(d2,power.w)));
}
// Finite-patch visibility/transmittance gates the local direct response.
// Contact-only mode cannot brighten. Detail mode redistributes direct light
// locally; its image-space integral is not a certified finite-area quadrature.
vec3 lie_surface_refined(vec3 old_direct,vec3 unoccluded,
                        vec3 coefficient,vec3 local_direct,float visibility,bool detail) {
    vec3 gate=vec3(0);
    for(int c=0;c<3;c++)if(unoccluded[c]>1e-20)gate[c]=clamp(old_direct[c]/unoccluded[c],0.,1.);
    vec3 direct=detail?coefficient*local_direct*gate:old_direct;
    return direct*visibility;
}

void main() {
    if(gl_GlobalInvocationID.x!=0u)return;
    result.visibility=vec4(lie_contact_visibility(query.world.xyz,query.normal.xyz,query.light.xyz,query.world.w,query.normal.w,int(query.light.w)));
    result.contact_only=vec4(lie_surface_refined(vec3(.2,.3,.4),vec3(.4,.6,.8),vec3(.5),vec3(2.),.25,false),1);
    result.detailed=vec4(lie_surface_refined(vec3(.2,.3,.4),vec3(.4,.6,.8),vec3(.5),vec3(2.),.25,true),1);
    result.source=vec4(lie_surface_unoccluded(0u,vec3(0),vec3(0,0,1)),1);
}
