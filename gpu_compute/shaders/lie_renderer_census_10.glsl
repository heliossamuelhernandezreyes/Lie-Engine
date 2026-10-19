#[compute]
#version 450
// GENERATED diagnostic census; excludes performance results.
// GENERATED dedicated stage 10; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
layout(set=0,binding=49,std430) buffer LieCensus {uint values[];} lie_census;
void lie_count(uint at,uint n) {atomicAdd(lie_census.values[at],n);}

struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample v[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Instances { Instance v[]; } instances;

layout(set=0,binding=3,std430) buffer Projected { Projection v[]; } projected;

layout(set=0,binding=5,std430) buffer Winner { uint v[]; } winners;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=7,std430) buffer Accumulated { Accumulator v[]; } accumulated;
layout(rgba32ui,set=0,binding=8) uniform uimage2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;



/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */

layout(set=0,binding=15,std430) readonly buffer InjectedMaterialCodes {
    vec4 values[];
} injected_material_codes;
/* 48 immutable bytes derived from real brick layout. Geometry remains source
   LIE samples, NOT faces of the coarse invisible spatial envelope. */


// WALL04 only: close the nominal 8.5mm spacing toward the 3mm visual boundary over the 6mm photographed core
// by expanding EACH original scanned brick about its original XY center.
// The GPU source sample buffer remains byte-identical to WALL03; there is
// no mesh creation and the one invisible box/collider is unchanged.
const float WALL04_VISIBLE_JOINT_M = 0.003;







layout(set=0,binding=18,std430) buffer RecoveryMap { uint values[]; } recovery_map;
struct Recovery { uvec4 info; vec4 coefficients[9]; };
layout(set=0,binding=19,std430) buffer RecoveryRecords { Recovery values[]; } recovery;

const uint MAX_RECOVERY=65536u;
// A virtual sample is reconstructed from ONE original immutable brick master.
// Per-instance transforms, source subset IDs and tint recreate the old WALL04
// records; photo mortar records are copied unchanged. No original mesh draws.


uint projection_node(Projection p) {
    return uint(round(p.world.w));
}
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;
layout(set=0,binding=21,std430) readonly buffer LightGroups { uvec4 header; uvec4 entries[]; } light_groups;
uvec2 lie_group(uint node) {return light_groups.header.x==0u?uvec2(node,1):light_groups.entries[node].xy;}
vec3 lie_position(uint node) {return injected_material_codes.values[node*3u].xyz;}
vec3 lie_normal(uint node) {return injected_material_codes.values[node*3u+1u].xyz;}
float lie_area(uint node) {return injected_material_codes.values[node*3u].w;}
// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.
float lie_stencil_weight(vec3 world,uint reference,uint candidate) {
    vec3 normal=normalize(lie_normal(reference));
    float agreement=dot(normal,normalize(lie_normal(candidate)));
    if(agreement<.9)return 0.;
    vec3 delta=world-lie_position(candidate);delta-=normal*dot(delta,normal);
    float alignment=max((agreement-.9)/.1,0.);
    return alignment*alignment/(dot(delta,delta)+max(lie_area(reference)*1e-4,1e-12));
}
float lie_stencil_sum(vec3 world,uint node) {
    uvec2 group=lie_group(node);float total=0.;
    for(uint k=0u;k<group.y;k++)total+=lie_stencil_weight(world,node,group.x+k);
    return total;
}




bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}












// WALL04 has no analytic flat-plane mortar. Every mortar pixel must be
// depth-tested from a PHOTO-CAPTURED source sample in the original stage 2/3.
// The single 6-face invisible spatial envelope is NEVER a visible surface.


layout(set=0,binding=22,std430) readonly buffer SurfaceOptions { uvec4 flags; vec4 metric; } surface_options;
layout(set=0,binding=23,std430) readonly buffer SurfaceLights { uvec4 header; vec4 values[]; } surface_lights;
// 32 bytes per accepted recovery record instead of a full-frame world atlas.
struct RecoverySurface {vec4 world;vec4 normal;};
layout(set=0,binding=24,std430) buffer RecoverySurfaces { RecoverySurface values[]; } recovery_surfaces;
vec3 lie_surface_ray(vec2 screen) {
    vec2 uv=screen/vec2(parameters.counts.zw);
    return parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+
        parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
}
vec3 lie_surface_world(Projection p,vec2 screen) {
    return parameters.eye.xyz+lie_surface_ray(screen)*pixel_depth(p,screen);
}
vec2 lie_surface_project(vec3 world) {
    vec3 d=world-parameters.eye.xyz;float z=dot(d,parameters.forward.xyz);
    if(z<=parameters.lens.z)return vec2(-1e9);
    vec2 uv=vec2(dot(d,parameters.right.xyz),-dot(d,parameters.up.xyz))/(z*parameters.lens.x);
    return (uv*.5+.5)*vec2(parameters.counts.zw);
}
bool lie_surface_observed(ivec2 q,out vec3 point,out vec3 normal) {
    if(!inside(q))return false;
    uint owner=winners.v[uint(q.y*parameters.counts.z+q.x)];
    if(owner==EMPTY)return false;
    Projection p=projected.v[owner];point=lie_surface_world(p,vec2(q)+.5);
    normal=normalize(p.normal.xyz);return true;
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
// Relative total RGB power: an isotropic point has gain 1. A one-sided
// Lambert emitter has intensity Phi*cos(theta)/PI, hence gain 4*cos.
float lie_emitter_gain(vec4 shape,vec3 from_source) {
    if(shape.w<.5)return 1.;
    float d2=dot(from_source,from_source);
    return d2>1e-20?4.*max(dot(shape.xyz,from_source*inversesqrt(d2)),0.):0.;
}
layout(set=0,binding=34,std430) readonly buffer EmitterShapesEarly {vec4 values[];} emitter_shapes_early;
vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {
    vec4 source=surface_lights.values[l*2u],power=surface_lights.values[l*2u+1u];
    vec3 delta=source.xyz-world;float d2=dot(delta,delta);
    if(d2<=1e-10 || source.w<=0.)return vec3(0);
    float cosine=max(dot(normal,delta*inversesqrt(d2)),0.);
    float fade=pow(max(0.,1.-pow(sqrt(d2)/source.w,4.)),2.);
    return power.rgb*(cosine*fade*lie_emitter_gain(emitter_shapes_early.values[l],-delta)/(4.*PI*max(d2,power.w)));
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





layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;


// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};




// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.



// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.









float lie_cached_source_visibility(uint projection,uint light) {
    uvec2 bits=source_visibility.values[projection];
    if(light<4u)return float((bits.x>>(light*8u))&255u)/255.;
    uint shift=(light-4u)*8u,mask=light==7u?127u:255u;
    return float((bits.y>>shift)&mask)/float(mask);
}
// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.












layout(set=0,binding=32,std430) buffer AppearanceControl {uint words[];} appearance_control;
// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.
vec3 lie_opaque_direction(vec3 delta) {
    // A source exactly on a receiver has zero incident irradiance. Keep its
    // direction finite as well: normalize(0) is undefined on GPU hardware.
    return delta*inversesqrt(max(dot(delta,delta),1e-20));
}
float lie_fresnel(float cosine,float f0) {
    float m=clamp(1.-cosine,0.,1.);float m2=m*m;
    return f0+(1.-f0)*m2*m2*m;
}
float lie_filtered_roughness(float roughness,float mean_length,bool filtered) {
    float r=clamp(roughness,.2,.98);
    float variance=filtered?clamp(1.-mean_length,0.,1.):0.;
    // Normal variance broadens the squared microfacet width. It never
    // changes the captured geometric normal, source color or visibility.
    return sqrt(sqrt(min(r*r*r*r+variance,1.)));
}
vec3 lie_opaque_brdf(vec3 albedo,float roughness,float f0,float survival,vec3 normal,vec3 view,vec3 light) {
    float nl=dot(normal,light),nv=dot(normal,view);
    if(nl<=1e-6 || nv<=1e-6)return vec3(0);
    vec3 half_sum=view+light;float h2=dot(half_sum,half_sum);
    if(h2<=1e-12)return vec3(0);
    vec3 h=half_sum*inversesqrt(h2);
    float nh=max(dot(normal,h),0.),vh=max(dot(view,h),0.);
    float alpha=roughness*roughness,a2=alpha*alpha;
    float denominator=nh*nh*(a2-1.)+1.;
    float D=a2/(3.141592653589793*denominator*denominator);
    // Algebraically equivalent to G2/(4*nl*nv); stable near grazing.
    float smith=2.*(nv*sqrt(a2+(1.-a2)*nl*nl)+nl*sqrt(a2+(1.-a2)*nv*nv));
    float specular=D*lie_fresnel(vh,f0)/max(smith,1e-12);
    float diffuse=(1.-lie_fresnel(nl,f0))*(1.-lie_fresnel(nv,f0))/3.141592653589793;
    return albedo*diffuse+vec3(specular*survival);
}
// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.


layout(set=0,binding=33,std430) readonly buffer PipelineControl {uvec4 flags;} pipeline_control;
// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};
LiePixelMaterial lie_raw_material(uint i) {
    Accumulator a=accumulated.v[i];float w=max(float(a.color_weight.w),1.);
    vec3 n=vec3(a.normal_roughness.xyz)/w*2.-1.;
    return LiePixelMaterial(vec3(a.color_weight.xyz)/w,n,float(a.normal_roughness.w)/w,min(length(n),1.));
}

LiePixelMaterial lie_unpack_material(uvec4 b) {
    vec2 a=unpackHalf2x16(b.x),c=unpackHalf2x16(b.y),n=unpackHalf2x16(b.z),z=unpackHalf2x16(b.w);
    return LiePixelMaterial(vec3(a,c.x),vec3(n,z.x),c.y,z.y);
}


LiePixelMaterial lie_material(uint i) {
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    return pipeline_control.flags.y!=0u?lie_unpack_material(imageLoad(diffuse_image,q)):lie_raw_material(i);
}
void lie_resolve_surface(uint i) {
    if(i>=uint(parameters.counts.z*parameters.counts.w))return;
    if(surface_options.flags.x==0u && surface_options.flags.y==0u && appearance_control.words[0]==0u)return;
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    vec4 base=imageLoad(specular_image,q);if(base.a<.5)return;lie_count(6u,1u);
    uint owner=winners.v[i],slot=recovery_map.values[i];
    uint source_projection=owner;
    float roughness=.8,mean_length=1.;
    vec3 world,normal;vec3 coefficients[9];float optical_weights[9];for(int k=0;k<9;k++){coefficients[k]=vec3(0);optical_weights[k]=0.;}
    uvec2 group;
    if(owner!=EMPTY) {
        Projection p=projected.v[owner];uint node=projection_node(p);group=lie_group(node);
        world=lie_surface_world(p,vec2(q)+.5);normal=normalize(p.normal.xyz);
        LiePixelMaterial material=lie_material(i);vec3 albedo=material.albedo,mean_normal=material.mean_normal;
        roughness=material.roughness;mean_length=material.mean_length;
        if(dot(mean_normal,mean_normal)>1e-8 && dot(normalize(mean_normal),normal)>.9)normal=normalize(mean_normal);
        float sum=group.y==1u?1.:lie_stencil_sum(p.world.xyz,node);
        for(uint k=0u;k<group.y;k++) {
            float w=group.y==1u?1.:lie_stencil_weight(p.world.xyz,node,group.x+k)/max(sum,1e-30);
            coefficients[k]=albedo*(w/PI);optical_weights[k]=w;
        }
    } else {
        // An overflow/unwitnessed hole stays on the accepted baseline path.
        if(slot==EMPTY || slot==0u || slot>MAX_RECOVERY)return;
        Recovery record=recovery.values[slot-1u];group=record.info.xy;
        RecoverySurface surface=recovery_surfaces.values[slot-1u];
        world=surface.world.xyz;normal=surface.normal.xyz;source_projection=uint(surface.normal.w)-1u;
        for(uint k=0u;k<group.y;k++){coefficients[k]=record.coefficients[k].rgb;optical_weights[k]=record.coefficients[k].w;}
        Projection witness=projected.v[source_projection];
        uint sid=uint(round(witness.gradient.w));
        roughness=clamp(samples.v[sid].attributes.z+instances.v[uint(witness.gradient.z)].tint.w,.2,.95);
    }
    vec3 coefficient=vec3(0);
    for(uint k=0u;k<group.y;k++) {
        float absorption=clamp(injected_material_codes.values[(group.x+k)*3u+2u].w,0.,1.);
        coefficients[k]*=1.-absorption;coefficient+=coefficients[k];
    }
    vec3 old_total=vec3(0),new_total=vec3(0);lie_count(7u,group.y);
    roughness=lie_filtered_roughness(roughness,mean_length,appearance_control.words[2]!=0u);
    vec3 view=lie_opaque_direction(parameters.eye.xyz-world);
    float survival=0.;
    for(uint k=0u;k<group.y;k++)survival+=optical_weights[k]*(1.-clamp(injected_material_codes.values[(group.x+k)*3u+2u].w,0.,1.));
    float f0=uintBitsToFloat(appearance_control.words[3]);
    for(uint l=0u;l<surface_lights.header.y;l++) {
        if(max(surface_lights.values[l*2u+1u].r,max(surface_lights.values[l*2u+1u].g,surface_lights.values[l*2u+1u].b))<=0.)continue;
        vec3 old_direct=vec3(0),unoccluded=vec3(0),optical_direct=vec3(0),optical_unoccluded=vec3(0);
        for(uint k=0u;k<group.y;k++) {
            bool optical=appearance_control.words[0]!=0u && surface_options.flags.y!=0u;
            if(max(coefficients[k].r,max(coefficients[k].g,coefficients[k].b))<=0. && (!optical || optical_weights[k]<=0.))continue;
            uint node=group.x+k;lie_count(8u,1u);
            vec3 incident=lie_surface_unoccluded(l,lie_position(node),lie_normal(node));
            vec3 coarse=surface_lights.values[16u+l*surface_lights.header.x+node].rgb;
            old_direct+=coefficients[k]*coarse;
            if(optical) {
                optical_direct+=optical_weights[k]*coarse;
                optical_unoccluded+=optical_weights[k]*incident;
            } else unoccluded+=coefficients[k]*incident;
        }
        float visibility=1.;
        if(surface_options.flags.x!=0u && (max(old_direct.r,max(old_direct.g,old_direct.b))>0. || (appearance_control.words[0]!=0u && max(optical_direct.r,max(optical_direct.g,optical_direct.b))>0.))) {
            if(surface_options.flags.w!=0u)visibility=lie_cached_source_visibility(source_projection,l);
            else visibility=lie_contact_visibility(world,normal,surface_lights.values[l*2u].xyz,
                surface_options.metric.x,surface_options.metric.y,int(surface_options.flags.z));
        }
        vec3 local_direct=lie_surface_unoccluded(l,world,normal);lie_count(9u,1u);
        old_total+=old_direct;
        if(appearance_control.words[0]!=0u && surface_options.flags.y!=0u) {
            // Replace the existing direct term. The indirect field is retained
            // once, outside this loop. No second point emitter or cached RGB.
            vec3 gate=vec3(0);
            for(int c=0;c<3;c++)if(optical_unoccluded[c]>1e-20)gate[c]=clamp(optical_direct[c]/optical_unoccluded[c],0.,1.);
            vec3 direction=lie_opaque_direction(surface_lights.values[l*2u].xyz-world);
            vec3 response=lie_opaque_brdf(coefficient*PI,roughness,f0,survival,normal,view,direction);
            new_total+=max(response,vec3(0))*local_direct*gate*visibility;
        } else new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);
    }
    imageStore(specular_image,q,vec4(max(base.rgb-old_total,vec3(0))+new_total,base.a));
}



// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.









void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=10;
lie_resolve_surface(i);return;
}
