#[compute]
#version 450
// GENERATED dedicated stage 14; tools/lie_wall17_shader.py
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




/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */


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



// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.






bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
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



// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};
LiePixelMaterial lie_raw_material(uint i) {
    Accumulator a=accumulated.v[i];float w=max(float(a.color_weight.w),1.);
    vec3 n=vec3(a.normal_roughness.xyz)/w*2.-1.;
    return LiePixelMaterial(vec3(a.color_weight.xyz)/w,n,float(a.normal_roughness.w)/w,min(length(n),1.));
}
uvec4 lie_pack_material(LiePixelMaterial m) {
    return uvec4(packHalf2x16(m.albedo.rg),packHalf2x16(vec2(m.albedo.b,m.roughness)),packHalf2x16(m.mean_normal.xy),packHalf2x16(vec2(m.mean_normal.z,m.mean_length)));
}

LiePixelMaterial lie_filter_material(uint i) {
    LiePixelMaterial center=lie_raw_material(i);uint owner=winners.v[i];
    if(owner==EMPTY)return center;
    Projection p=projected.v[owner];uvec2 group=lie_group(projection_node(p));
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    float sigma=clamp(.35+.12*p.screen.w,.45,1.);
    float world_pixel=2.*p.screen.z*parameters.lens.x/float(parameters.counts.z);
    float tolerance=clamp(world_pixel*1.25,.0004,.002);
    vec3 color=vec3(0),normal=vec3(0);float rough=0.,sum=0.;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {
        ivec2 q=xy+ivec2(x,y);if(!inside(q))continue;
        uint j=uint(q.y*parameters.counts.z+q.x),other=winners.v[j];if(other==EMPTY)continue;
        Projection neighbor=projected.v[other];
        if(neighbor.gradient.z!=p.gradient.z || any(notEqual(group,lie_group(projection_node(neighbor)))))continue;
        if(dot(normalize(p.normal.xyz),normalize(neighbor.normal.xyz))<.95)continue;
        // Compare both planes at the same pixel center; never blur a depth edge.
        float observed=pixel_depth(neighbor,vec2(q)+.5);
        float expected=pixel_depth(p,vec2(q)+.5);
        if(abs(expected-observed)>tolerance)continue;
        LiePixelMaterial m=lie_raw_material(j);vec3 delta=m.albedo-center.albedo;
        float weight=exp(-float(x*x+y*y)/(2.*sigma*sigma)-dot(delta,delta)/.0128);
        color+=m.albedo*weight;normal+=m.mean_normal*weight;rough+=m.roughness*weight;sum+=weight;
    }
    if(sum<=0.)return center;
    normal/=sum;return LiePixelMaterial(color/sum,normal,rough/sum,min(length(normal),1.));
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
    const int stage=14;

        if(i>=uint(parameters.counts.z*parameters.counts.w) || winners.v[i]==EMPTY)return;
        ivec2 pixel=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
        imageStore(diffuse_image,pixel,lie_pack_material(lie_filter_material(i)));return;
    
}
