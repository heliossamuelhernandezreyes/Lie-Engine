#[compute]
#version 450
// GENERATED screen-owned resolve; tools/lie_wall22_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };



layout(set=0,binding=3,std430) buffer Projected { Projection v[]; } projected;
layout(set=0,binding=4,std430) buffer Depth { uint v[]; } depths;
layout(set=0,binding=5,std430) buffer Winner { uint v[]; } winners;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=7,std430) buffer Accumulated { Accumulator v[]; } accumulated;





/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */


/* 48 immutable bytes derived from real brick layout. Geometry remains source
   LIE samples, NOT faces of the coarse invisible spatial envelope. */
layout(set=0,binding=16,std430) readonly buffer WallJointLayout {
    vec4 dimensions; // real brick X length, Y height, x pitch, y pitch
    vec4 origin;     // first brick X/Y, recessed mortar plane Z, row stagger
    vec4 config;     // column count, row count, nominal mortar gap, enabled
} joint;

// WALL04 only: close the nominal 8.5mm spacing toward the 3mm visual boundary over the 6mm photographed core
// by expanding EACH original scanned brick about its original XY center.
// The GPU source sample buffer remains byte-identical to WALL03; there is
// no mesh creation and the one invisible box/collider is unchanged.
const float WALL04_VISIBLE_JOINT_M = 0.003;
vec2 wall04_brick_center(uint node) {
    uint brick=node/9u;
    uint row=brick/12u, col=brick%12u;
    float stagger=(row%2u==1u)?joint.origin.w*joint.dimensions.z:0.0;
    return joint.origin.xy+vec2(float(col)*joint.dimensions.z+stagger,
                                float(row)*joint.dimensions.w);
}
vec2 wall04_brick_xy_scale() {
    return vec2((joint.dimensions.z-WALL04_VISIBLE_JOINT_M)/joint.dimensions.x,
                (joint.dimensions.w-WALL04_VISIBLE_JOINT_M)/joint.dimensions.y);
}

vec2 wall04_unexpanded_xy(vec2 xy, uint node) {
    vec2 center=wall04_brick_center(node);
    return center+(xy-center)/wall04_brick_xy_scale();
}




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






bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}
float footprint_distance(Projection p,vec2 xy) {
    vec2 q=xy-p.screen.xy;
    return q.x*q.x*p.ellipse.x+2*q.x*q.y*p.ellipse.y+q.y*q.y*p.ellipse.z;
}
bool covered(Projection p,vec2 xy) {
    if(footprint_distance(p,xy)>1) return false;
    vec2 uv=xy/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
    vec3 local=parameters.eye.xyz+ray*pixel_depth(p,xy);
    if(p.gradient.z<96.) local.xy=wall04_unexpanded_xy(local.xy,uint(p.gradient.z)*9u);
    int axis=int(p.ellipse.w);vec2 q=axis==0?local.zy:axis==1?local.xz:local.xy;
    return all(greaterThanEqual(q,p.geometry.xy-vec2(.000002))) && all(lessThanEqual(q,p.geometry.zw+vec2(.000002)));
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










// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.












layout(set=0,binding=32,std430) buffer AppearanceControl {uint words[];} appearance_control;
// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.




// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.
ivec2 lie_splat_row(Projection p,ivec2 center,int y,int bound) {
    float dy=float(y)+.5-p.screen.y;
    float A=p.ellipse.x,B=p.ellipse.y,C=p.ellipse.z;
    float cross_section=1.-(C-B*B/A)*dy*dy;
    if(A<=0. || isnan(cross_section) || isinf(cross_section))return ivec2(center.x-bound,center.x+bound);
    // A one-pixel guard on both ends preserves floating-point boundary cases.
    // Even a slightly negative section receives a conservative candidate.
    float span=sqrt(max(cross_section,0.)/A);
    float middle=p.screen.x-B*dy/A-.5;
    return ivec2(max(center.x-bound,int(floor(middle-span))-1),
                 min(center.x+bound,int(ceil(middle+span))+1));
}


// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};










// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.










// Per-tile count, fill cursor, block-local exclusive offset, reserved.
layout(set=0,binding=41,std430) buffer TileTable { uvec4 values[]; } tile_table;
layout(set=0,binding=42,std430) buffer TileReferences { uint values[]; } tile_refs;
// One exclusive prefix per 64-tile block, then total reference count.
layout(set=0,binding=43,std430) buffer TileGroups { uint values[]; } tile_groups;
layout(set=0,binding=44,std430) buffer TileMaterials { vec4 values[]; } tile_materials;
const uint LIE_TILE_SIZE=8u;
uvec2 lie_tile_dimensions(){return (uvec2(parameters.counts.zw)+7u)/8u;}

uint lie_tile_start(uint tile){return tile_table.values[tile].z+tile_groups.values[tile/64u];}

bool lie_tile_hit(Projection p,ivec2 q,out uint bits){
    int bound=int(ceil(p.screen.w));ivec2 center=ivec2(floor(p.screen.xy));
    if(any(lessThan(q,center-ivec2(bound))) || any(greaterThan(q,center+ivec2(bound))))return false;
    if(appearance_control.words[1]!=0u){ivec2 row=lie_splat_row(p,center,q.y,bound);if(q.x<row.x || q.x>row.y)return false;}
    if(!covered(p,vec2(q)+.5))return false;
    float z=pixel_depth(p,vec2(q)+.5);if(z<=parameters.lens.z || isnan(z) || isinf(z))return false;
    bits=floatBitsToUint(z);return true;
}
void main(){
    uint tile=gl_WorkGroupID.x;uvec2 dims=lie_tile_dimensions();
    ivec2 q=ivec2(tile%dims.x,tile/dims.x)*8+ivec2(gl_LocalInvocationID.x%8u,gl_LocalInvocationID.x/8u);
    if(!inside(q))return;
    uint pixel=uint(q.y*parameters.counts.z+q.x),count=tile_table.values[tile].x,start=lie_tile_start(tile);
    uint nearest=0x7f7fffffu,owner=EMPTY;
    for(uint k=0u;k<count;k++){
        uint id=tile_refs.values[start+k],bits;Projection p=projected.v[id];
        if(lie_tile_hit(p,q,bits))nearest=min(nearest,bits);
    }
    Accumulator a=Accumulator(uvec4(0),uvec4(0));
    if(nearest!=0x7f7fffffu)for(uint k=0u;k<count;k++){
        uint id=tile_refs.values[start+k],bits;Projection p=projected.v[id];
        if(!lie_tile_hit(p,q,bits))continue;
        if(bits==nearest){owner=min(owner,id);atomicOr(source_visibility.values[id].y,0x80000000u);}
        if(abs(uintBitsToFloat(bits)-uintBitsToFloat(nearest))>parameters.options.w)continue;
        vec4 material=tile_materials.values[id];
        uint w=max(uint(round(256*exp(-2*footprint_distance(p,vec2(q)+.5)))),1u);
        uvec3 c=uvec3(round(material.rgb*float(w))),n=uvec3(round((p.normal.xyz*.5+.5)*float(w)));
        a.color_weight+=uvec4(c,w);
        a.normal_roughness+=uvec4(n,uint(round(material.w*float(w))));
    }
    depths.v[pixel]=nearest;winners.v[pixel]=owner;accumulated.v[pixel]=a;
}
