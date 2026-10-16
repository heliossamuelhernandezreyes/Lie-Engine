#[compute]
#version 450
// GENERATED screen-owned fill; tools/lie_wall22_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };


layout(set=0,binding=2,std430) readonly buffer Jobs { uvec4 v[]; } jobs;
layout(set=0,binding=3,std430) buffer Projected { Projection v[]; } projected;


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















uint job_index(uint invocation) {
    uint lo=0u,hi=uint(parameters.counts.y);
    while(lo+1u<hi) {uint mid=(lo+hi)/2u;if(jobs.v[mid].w<=invocation)lo=mid;else hi=mid;}
    return lo;
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
layout(set=0,binding=29,std430) readonly buffer SourceBlocks {uvec2 values[];} source_blocks;












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









// Per-tile count, fill cursor, block-local exclusive offset, reserved.
layout(set=0,binding=41,std430) buffer TileTable { uvec4 values[]; } tile_table;
layout(set=0,binding=42,std430) buffer TileReferences { uint values[]; } tile_refs;
// One exclusive prefix per 64-tile block, then total reference count.
layout(set=0,binding=43,std430) buffer TileGroups { uint values[]; } tile_groups;

const uint LIE_TILE_SIZE=8u;
uvec2 lie_tile_dimensions(){return (uvec2(parameters.counts.zw)+7u)/8u;}

uint lie_tile_start(uint tile){return tile_table.values[tile].z+tile_groups.values[tile/64u];}
bool lie_tile_range(Projection p,out ivec4 range){
    if(p.screen.z<=0.)return false;
    int bound=int(ceil(p.screen.w));ivec2 center=ivec2(floor(p.screen.xy));
    ivec2 lo=max(center-ivec2(bound),ivec2(0));
    ivec2 hi=min(center+ivec2(bound),parameters.counts.zw-ivec2(1));
    if(any(greaterThan(lo,hi)))return false;
    range=ivec4(lo/8,hi/8);return true;
}

void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=3;

        uint j;
        if(phase.value.w<0) {
            uint group=gl_WorkGroupID.x;
            uvec2 block=source_blocks.values[query_arena.words[4u+group]];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else if(phase.value.w>0) {
            uint group=gl_WorkGroupID.x+gl_WorkGroupID.y*gl_NumWorkGroups.x;
            uvec2 block=source_blocks.values[uint(phase.value.w)-1u+group];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else {if(i>=uint(parameters.counts.x))return;j=job_index(i);}

        Projection p=projected.v[i];ivec4 range;if(!lie_tile_range(p,range))return;
        uint columns=lie_tile_dimensions().x;
        for(int y=range.y;y<=range.w;y++)for(int x=range.x;x<=range.z;x++){
            uint tile=uint(y)*columns+uint(x);
            uint at=atomicAdd(tile_table.values[tile].y,1u);
            tile_refs.values[lie_tile_start(tile)+at]=i;
        }
}
