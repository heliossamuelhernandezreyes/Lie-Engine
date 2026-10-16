#[compute]
#version 450
// GENERATED dedicated stage 11; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample v[]; } samples;


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




















// WALL04 has no analytic flat-plane mortar. Every mortar pixel must be
// depth-tested from a PHOTO-CAPTURED source sample in the original stage 2/3.
// The single 6-face invisible spatial envelope is NEVER a visible surface.


layout(set=0,binding=22,std430) readonly buffer SurfaceOptions { uvec4 flags; vec4 metric; } surface_options;
layout(set=0,binding=23,std430) readonly buffer SurfaceLights { uvec4 header; vec4 values[]; } surface_lights;
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





layout(set=0,binding=27,std430) readonly buffer SourceScene {uint values[];} lie_visibility_scene;
layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;
vec4 lie_visibility_position_radius(uint sid) {return samples.v[sid].position_radius;}
vec3 lie_visibility_normal(uint sid) {return samples.v[sid].normal_gray.xyz;}
// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};

vec4 lie_scene_vec(uint at) {
    return uintBitsToFloat(uvec4(lie_visibility_scene.values[at],lie_visibility_scene.values[at+1u],lie_visibility_scene.values[at+2u],lie_visibility_scene.values[at+3u]));
}


// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.



// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;
void lie_query_stat(uint at) {if(query_memory.words[2]!=0u)atomicAdd(query_memory.words[16u+at],1u);}

bool lie_witness_blocks(uint code,vec3 o,vec3 d,float minimum,float early,uint owner,uint source_id) {
    if((code&0x3fffffu)==0u)return false;
    uint instance=code>>22u,sid=(code&0x3fffffu)-1u;
    if(instance>=lie_visibility_scene.values[3] || (instance==owner && sid==source_id))return false;
    uint at=lie_visibility_scene.values[2]+instance*16u;
    uint start=lie_visibility_scene.values[at+13u],count=lie_visibility_scene.values[at+14u];
    if(sid<start || sid-start>=count)return false;
    vec4 x=lie_scene_vec(at),y=lie_scene_vec(at+4u),z=lie_scene_vec(at+8u);
    vec3 local_o=vec3(dot(x,vec4(o,1)),dot(y,vec4(o,1)),dot(z,vec4(o,1)));
    vec3 local_d=vec3(dot(x.xyz,d),dot(y.xyz,d),dot(z.xyz,d));
    vec4 source=lie_visibility_position_radius(sid);vec3 normal=lie_visibility_normal(sid);
    float denominator=dot(normal,local_d);if(abs(denominator)<1e-8)return false;
    float t=dot(normal,source.xyz-local_o)/denominator;if(t<=minimum || t>early)return false;
    vec3 delta=local_o+t*local_d-source.xyz;
    return dot(delta,delta)<=source.w*source.w;
}






// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.

layout(set=0,binding=30,std430) buffer PersistentVisibility {uint words[];} persistent_visibility;
layout(set=0,binding=31,std430) buffer VisibilityControl {uint words[];} visibility_control;
uint lie_visibility_slot(uint projection) {return uint(projected.v[projection].normal.w);}
bool lie_visibility_persistent() {return visibility_control.words[0]!=0u && surface_options.flags.x!=0u && surface_options.flags.w!=0u;}
uint lie_pack_visibility(uvec2 bits,uint light) {
    uint shift=(light%4u)*8u,mask=light==7u?127u:255u;
    return ((light<4u?bits.x:bits.y)>>shift)&mask;
}
uvec2 lie_write_visibility(uvec2 bits,uint light,uint value) {
    uint shift=(light%4u)*8u,mask=light==7u?127u:255u;
    if(light<4u)bits.x=(bits.x&~(mask<<shift))|(value<<shift);
    else bits.y=(bits.y&~(mask<<shift))|(value<<shift);
    return bits;
}






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








layout(set=0,binding=35,std430) buffer ActiveVisibility {uint values[];} active_visibility;

// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.









layout(set=0,binding=38,std430) buffer TraceQueue {uint values[];} trace_queue;
layout(constant_id=0) const bool LIE_STREAM_INSTRUMENTED=false;
void lie_stream_stat(uint slot) {if(LIE_STREAM_INSTRUMENTED)atomicAdd(query_memory.words[24u+slot],1u);}
// Each light dispatch completes before the next one. No cross-light word races.
void lie_stream_store(uint i,uint slot,uint light,uint value,bool cache_value) {
    uvec2 result=source_visibility.values[i];result=lie_write_visibility(result,light,value);source_visibility.values[i]=result;
    if(cache_value && lie_visibility_persistent() && slot<visibility_control.words[2]) {
        uint at=64u+slot*3u;uvec2 resident=uvec2(persistent_visibility.words[at],persistent_visibility.words[at+1u]);
        resident=lie_write_visibility(resident,light,value);persistent_visibility.words[at]=resident.x;persistent_visibility.words[at+1u]=resident.y;persistent_visibility.words[at+2u]|=1u<<light;
    }
}

bool lie_stream_prepare(uint i,uint light) {
    if(i>=uint(parameters.counts.x) || light>=surface_lights.header.y)return false;
    if((source_visibility.values[i].y&0x80000000u)==0u)return false;
    if(light==0u)source_visibility.values[i]=uvec2(0xffffffffu);
    uint slot=lie_visibility_slot(i),at=64u+slot*3u,mask=light==7u?127u:255u;
    lie_stream_stat(0u);
    if(surface_options.flags.x==0u || surface_options.flags.w==0u)return false;
    vec3 power=surface_lights.values[light*2u+1u].rgb;
    if(max(power.r,max(power.g,power.b))<=0.) {
        lie_stream_store(i,slot,light,mask,false);lie_stream_stat(2u);
        if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[20u+light],1u);return false;
    }
    bool cache=lie_visibility_persistent() && slot<visibility_control.words[2];
    if(cache && (persistent_visibility.words[at+2u]&(1u<<light))!=0u) {
        uvec2 resident=uvec2(persistent_visibility.words[at],persistent_visibility.words[at+1u]);
        lie_stream_store(i,slot,light,lie_pack_visibility(resident,light),false);lie_stream_stat(1u);
        if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[4u+light],1u);return false;
    }
    if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[12u+light],1u);
    Projection p=projected.v[i];vec3 normal=normalize(p.normal.xyz),point=p.world.xyz;
    vec3 delta=surface_lights.values[light*2u].xyz-point;float distance_to_light=length(delta),bias=surface_options.metric.y;
    if(distance_to_light<=bias || dot(normal,delta)<=0.) {lie_stream_store(i,slot,light,mask,true);lie_stream_stat(2u);return false;}
    vec3 o=point+normal*bias,d=delta/distance_to_light;
    float limit=min(surface_options.metric.x,distance_to_light-bias);
    if(limit<=bias){lie_stream_store(i,slot,light,mask,true);lie_stream_stat(2u);return false;}
    uint hint=slot<visibility_control.words[2] && query_memory.words[1]!=0u?query_memory.words[64u+slot*8u+light]:0u;
    if(hint!=0u) {
        lie_query_stat(0u);
        if(lie_witness_blocks(hint,o,d,bias,.75*limit,uint(p.gradient.z),uint(round(p.gradient.w)))) {
            lie_query_stat(1u);lie_stream_stat(3u);lie_stream_store(i,slot,light,0u,true);return false;
        }
    }
    lie_stream_stat(4u);return true;
}
// Portable 64-lane ballot: no optional subgroup capability is assumed.
// Three barriers instead of the shared prefix scan's thirteen barriers.
shared uint stream_masks[2];
shared uint stream_base;
void lie_stream_append(bool selected,uint id,uint lane) {
    if(lane<2u)stream_masks[lane]=0u;barrier();
    if(selected)atomicOr(stream_masks[lane/32u],1u<<(lane%32u));barrier();
    uvec2 votes=uvec2(stream_masks[0],stream_masks[1]);
    uint lower=(1u<<(lane%32u))-1u;
    uint rank=uint(bitCount(votes[lane/32u]&lower))+(lane>=32u?uint(bitCount(votes.x)):0u);
    if(lane==0u) {
        uint count=uint(bitCount(votes.x)+bitCount(votes.y));stream_base=0u;
        if(count>0u){stream_base=atomicAdd(trace_queue.values[3],count);atomicMax(trace_queue.values[0],(stream_base+count+63u)/64u);}
    }
    barrier();
    if(selected)trace_queue.values[4u+stream_base+rank]=id;
}

void main() {
    uint at=gl_GlobalInvocationID.x,i=0u;bool selected=false;
    if(at<active_visibility.values[3]){i=active_visibility.values[4u+at];selected=lie_stream_prepare(i,uint(phase.value.z));}
    lie_stream_append(selected,i,gl_LocalInvocationID.x);
}

