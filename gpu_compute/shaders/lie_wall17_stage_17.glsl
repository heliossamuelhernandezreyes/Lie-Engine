#[compute]
#version 450
// GENERATED dedicated stage 17; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };






layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;






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



layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;





// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.




















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
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;









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










// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.
layout(set=0,binding=36,std430) buffer QueryArena {uint words[];} query_arena;
vec4 lie_query_bound(uint i){uint at=query_memory.words[6]+i*4u;return uintBitsToFloat(uvec4(query_arena.words[at],query_arena.words[at+1u],query_arena.words[at+2u],query_arena.words[at+3u]));}

bool lie_query_visible(uint node) {
    vec3 lo=lie_query_bound(node*4u).xyz,hi=lie_query_bound(node*4u+1u).xyz;
    if(any(isnan(lo)) || any(isnan(hi)) || any(isinf(lo)) || any(isinf(hi)))return true;
    vec3 center=(lo+hi)*.5,extent=(hi-lo)*.5,delta=center-parameters.eye.xyz;
    float tolerance=2e-5*(1.+length(center)+length(parameters.eye.xyz));
    float z=dot(delta,parameters.forward.xyz),rz=dot(extent,abs(parameters.forward.xyz));
    if(z+rz<parameters.lens.z-tolerance || z-rz>parameters.lens.w+tolerance)return false;
    // Raster footprints are clamped to 8 pixels; floor/ceil add one pixel.
    float tx=parameters.lens.x*(1.+20./float(parameters.counts.z));
    float ty=parameters.lens.x*(1.+20./float(parameters.counts.w));
    for(int axis=0;axis<4;axis++) {
        vec3 side=axis<2?parameters.right.xyz:parameters.up.xyz;
        vec3 plane=parameters.forward.xyz*(axis<2?tx:ty)+(axis%2==0?side:-side);
        if(dot(delta,plane)+dot(extent,abs(plane)) < -tolerance)return false;
    }
    vec3 nl=lie_query_bound(node*4u+2u).xyz,nh=lie_query_bound(node*4u+3u).xyz;
    vec3 dl=parameters.eye.xyz-hi,dh=parameters.eye.xyz-lo;
    vec3 upper=max(max(nl*dl,nl*dh),max(nh*dl,nh*dh));
    return upper.x+upper.y+upper.z>=-tolerance;
}


void lie_query_select(uint page) {
    uint groups=query_memory.words[3];if(page>=query_memory.words[4] || !lie_query_visible(groups+page))return;
    for(uint block=page*16u;block<min((page+1u)*16u,groups);block++)if(lie_query_visible(block)) {
        uint at=atomicAdd(query_arena.words[0],1u);query_arena.words[4u+at]=query_memory.words[5]+block;
    }
}


void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=17;
lie_query_select(i);return;
}
