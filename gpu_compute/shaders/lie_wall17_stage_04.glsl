#[compute]
#version 450
// GENERATED dedicated stage 4; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };



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
layout(rgba32f,set=0,binding=11) uniform image2D output_image;


/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */
layout(rgba32f,set=0,binding=14) uniform readonly image2D injected_node_irradiance;
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








struct Recovery { uvec4 info; vec4 coefficients[9]; };


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

vec3 lie_irradiance_code(Projection point) {
    uint node=projection_node(point);uvec2 group=lie_group(node);
    vec3 total=vec3(0);float sum=group.y==1u?1.:lie_stencil_sum(point.world.xyz,node);
    for(uint k=0u;k<group.y;k++) {
        uint candidate=group.x+k;
        float w=group.y==1u?1.:lie_stencil_weight(point.world.xyz,node,candidate)/max(sum,1e-30);
        vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(candidate),0)).rgb,vec3(0));
        float absorption=clamp(injected_material_codes.values[candidate*3u+2u].w,0.,1.);
        total+=w*E*(1.-absorption)/PI;
    }
    return total;
}
















// WALL04 has no analytic flat-plane mortar. Every mortar pixel must be
// depth-tested from a PHOTO-CAPTURED source sample in the original stage 2/3.
// The single 6-face invisible spatial envelope is NEVER a visible surface.




// 32 bytes per accepted recovery record instead of a full-frame world atlas.
struct RecoverySurface {vec4 world;vec4 normal;};





// Bounded screen-space contact test. The host supplies projection and a REAL
// observed tangent plane per pixel; recovered holes never become occluders.
// The plane is bounded by its observed pixel cell, not an infinite surface or
// a guessed solid thickness. Missing/off-screen geometry contributes no shadow.

// Same point-source units, distance floor, range window and normalized power
// as the finite-patch field. No second emitter budget and no invented relief.
// Relative total RGB power: an isotropic point has gain 1. A one-sided
// Lambert emitter has intensity Phi*cos(theta)/PI, hence gain 4*cos.



// Finite-patch visibility/transmittance gates the local direct response.
// Contact-only mode cannot brighten. Detail mode redistributes direct light
// locally; its image-space integral is not a certified finite-area quadrature.









// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};




// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.



// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.










// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.













// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.




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




// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.









void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=4;
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        bool fused=pipeline_control.flags.x!=0u,filtered=pipeline_control.flags.y!=0u;
        if(owner==EMPTY) {if(fused)imageStore(output_image,xy,vec4(0));return;}
        LiePixelMaterial material=lie_material(i);
        vec3 E=lie_irradiance_code(projected.v[owner]);
        if(fused)imageStore(output_image,xy,vec4(max(material.albedo*E,vec3(0)),1));
        else if(filtered)imageStore(specular_image,xy,vec4(E,1));
        else imageStore(diffuse_image,xy,floatBitsToUint(vec4(E,1)));
        return;
    }
    if(stage==6) {
        if(owner==EMPTY){imageStore(output_image,xy,vec4(0));return;}
        vec3 E=pipeline_control.flags.y!=0u?imageLoad(specular_image,xy).rgb:uintBitsToFloat(imageLoad(diffuse_image,xy)).rgb;
        imageStore(output_image,xy,vec4(max(lie_material(i).albedo*E,vec3(0)),1));
    }

}
