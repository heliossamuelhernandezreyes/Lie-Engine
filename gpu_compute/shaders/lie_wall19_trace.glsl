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



layout(set=0,binding=25,std430) readonly buffer SourceBLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=26,std430) readonly buffer SourceLeaves {uint values[];} lie_visibility_refs;
layout(set=0,binding=27,std430) readonly buffer SourceScene {uint values[];} lie_visibility_scene;
layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;
vec4 lie_visibility_position_radius(uint sid) {return samples.v[sid].position_radius;}
vec3 lie_visibility_normal(uint sid) {return samples.v[sid].normal_gray.xyz;}
// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};
LieSourceNode lie_blas_node(uint i) {
    LieSourceNode n;n.lo=lie_visibility_blas.values[i*2u];n.hi=lie_visibility_blas.values[i*2u+1u];return n;
}
vec4 lie_scene_vec(uint at) {
    return uintBitsToFloat(uvec4(lie_visibility_scene.values[at],lie_visibility_scene.values[at+1u],lie_visibility_scene.values[at+2u],lie_visibility_scene.values[at+3u]));
}
LieSourceNode lie_scene_node(uint i) {
    LieSourceNode n;n.lo=lie_scene_vec(4u+i*8u);n.hi=lie_scene_vec(8u+i*8u);return n;
}
bool lie_source_box(vec3 o,vec3 d,vec3 low,vec3 high,float minimum,float maximum) {
    float enter=minimum,leave=maximum;
    for(int k=0;k<3;k++) {
        if(abs(d[k])<1e-12) {if(o[k]<low[k] || o[k]>high[k])return false;}
        else {float a=(low[k]-o[k])/d[k],b=(high[k]-o[k])/d[k];enter=max(enter,min(a,b));leave=min(leave,max(a,b));}
    }
    return enter<=leave;
}
// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.
vec3 lie_ray_reciprocal(vec3 d) {
    return vec3(abs(d.x)<1e-12?0.:1./d.x,abs(d.y)<1e-12?0.:1./d.y,abs(d.z)<1e-12?0.:1./d.z);
}
bool lie_source_box_precomputed(vec3 o,vec3 d,vec3 inverse,vec3 low,vec3 high,float minimum,float maximum) {
    float enter=minimum,leave=maximum;
    for(int k=0;k<3;k++) {
        if(abs(d[k])<1e-12){if(o[k]<low[k] || o[k]>high[k])return false;}
        else {
            float a=(low[k]-o[k])*inverse[k],b=(high[k]-o[k])*inverse[k];
            if(isinf(a) || isinf(b) || isnan(a) || isnan(b))return lie_source_box(o,d,low,high,minimum,maximum);
            float tolerance=8.*1.1920928955078125e-7*max(abs(a),abs(b))+1e-9;
            enter=max(enter,min(a,b)-tolerance);leave=min(leave,max(a,b)+tolerance);
        }
    }
    return enter<=leave;
}

// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;
void lie_query_stat(uint at) {if(query_memory.words[2]!=0u)atomicAdd(query_memory.words[16u+at],1u);}
uint lie_witness_code(uint instance,uint sid) {
    return instance<1024u && sid<0x3fffffu?(instance<<22u)|(sid+1u):0u;
}


layout(set=0,binding=38,std430) buffer TraceQueue {uint values[];} trace_queue;
void lie_stream_stat(uint slot) {if(query_memory.words[2]!=0u)atomicAdd(query_memory.words[24u+slot],1u);}
// Each light dispatch completes before the next one. No cross-light word races.
void lie_stream_store(uint i,uint slot,uint light,uint value,bool cache_value);


float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip,out uint blocker) {
    blocker=0xffffffffu;
    bool fast=(phase.value.w&2)!=0;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
    uint end=floatBitsToUint(lie_blas_node(root).lo.w),i=root;
    float nearest=maximum;
    while(i<end) {
        lie_stream_stat(5u);LieSourceNode n=lie_blas_node(i);uint escape=floatBitsToUint(n.lo.w),leaf=floatBitsToUint(n.hi.w);
        if(!(fast?lie_source_box_precomputed(o,d,inverse,n.lo.xyz,n.hi.xyz,minimum,nearest):lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest))){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint count=lie_visibility_refs.values[leaf];
        for(uint k=0u;k<count;k++) {
            lie_stream_stat(6u);uint sid=lie_visibility_refs.values[leaf+1u+k];if(sid==skip)continue;
            vec4 source=lie_visibility_position_radius(sid);vec3 normal=lie_visibility_normal(sid);
            float denominator=dot(normal,d);if(abs(denominator)<1e-8)continue;
            float t=dot(normal,source.xyz-o)/denominator;if(t<=minimum || t>=nearest)continue;
            vec3 delta=o+t*d-source.xyz;
            if(dot(delta,delta)>source.w*source.w)continue;
            nearest=t;blocker=sid;if(nearest<=early)return nearest;
        }
        i=escape;
    }
    return nearest;
}
float lie_source_world_visibility_hint(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id,uint hint,out uint found) {
    found=0u;
    vec3 delta=light-point;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 o=point+normal*bias,d=delta/distance_to_light;
    float limit=min(reach,distance_to_light-bias),nearest=limit;
    if(limit<=bias)return 1.;
    lie_query_stat(2u);
    bool fast=(phase.value.w&2)!=0;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
    uint i=0u,end=lie_visibility_scene.values[0];
    while(i<end) {
        lie_stream_stat(7u);LieSourceNode node=lie_scene_node(i);uint escape=floatBitsToUint(node.lo.w),leaf=floatBitsToUint(node.hi.w);
        if(!(fast?lie_source_box_precomputed(o,d,inverse,node.lo.xyz,node.hi.xyz,bias,nearest):lie_source_box(o,d,node.lo.xyz,node.hi.xyz,bias,nearest))){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint list=lie_visibility_scene.values[1]+leaf,count=lie_visibility_scene.values[list];
        for(uint k=0u;k<count;k++) {
            uint instance=lie_visibility_scene.values[list+1u+k];uint at=lie_visibility_scene.values[2]+instance*16u;
            vec4 x=lie_scene_vec(at),y=lie_scene_vec(at+4u),z=lie_scene_vec(at+8u);
            vec3 local_o=vec3(dot(x,vec4(o,1)),dot(y,vec4(o,1)),dot(z,vec4(o,1)));
            vec3 local_d=vec3(dot(x.xyz,d),dot(y.xyz,d),dot(z.xyz,d));
            uint root=lie_visibility_scene.values[at+12u];
            uint blocker;
            nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu,blocker);
            if(nearest<=.75*limit){found=lie_witness_code(instance,blocker);lie_query_stat(3u);return 0.;}
        }
        i=escape;
    }
    return smoothstep(.75*limit,limit,nearest);
}



// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.

layout(set=0,binding=30,std430) buffer PersistentVisibility {uint words[];} persistent_visibility;
layout(set=0,binding=31,std430) buffer VisibilityControl {uint words[];} visibility_control;
uint lie_visibility_slot(uint projection) {return uint(projected.v[projection].normal.w);}
bool lie_visibility_persistent() {return visibility_control.words[0]!=0u && surface_options.flags.x!=0u && surface_options.flags.w!=0u;}

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










// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.









void lie_stream_store(uint i,uint slot,uint light,uint value,bool cache_value) {
    uvec2 result=source_visibility.values[i];result=lie_write_visibility(result,light,value);source_visibility.values[i]=result;
    if(cache_value && lie_visibility_persistent() && slot<visibility_control.words[2]) {
        uint at=64u+slot*3u;uvec2 resident=uvec2(persistent_visibility.words[at],persistent_visibility.words[at+1u]);
        resident=lie_write_visibility(resident,light,value);persistent_visibility.words[at]=resident.x;persistent_visibility.words[at+1u]=resident.y;persistent_visibility.words[at+2u]|=1u<<light;
    }
}
void lie_stream_trace(uint i,uint light) {
    Projection p=projected.v[i];uint slot=lie_visibility_slot(i),mask=light==7u?127u:255u,found;
    float visibility=lie_source_world_visibility_hint(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)),0u,found);
    if(slot<visibility_control.words[2] && query_memory.words[1]!=0u)query_memory.words[64u+slot*8u+light]=found;
    uint value=uint(round(clamp(visibility,0.,1.)*float(mask)));lie_stream_store(i,slot,light,value,true);
}

void main() {
    uint at=gl_GlobalInvocationID.x;if(at>=trace_queue.values[3])return;
    lie_stream_trace(trace_queue.values[4u+at],uint(phase.value.z));
}

