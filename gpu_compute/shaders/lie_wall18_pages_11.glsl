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

// Immutable source-coordinate -> CSR pages. Pages never replace exact disks.
layout(set=0,binding=37,std430) readonly buffer SpatialPages {uint words[];} spatial_pages;
void lie_page_stat(uint slot) {if(query_memory.words[2]!=0u)atomicAdd(query_memory.words[20u+slot],1u);}
vec3 lie_page_vec(uint at) {return uintBitsToFloat(uvec3(spatial_pages.words[at],spatial_pages.words[at+1u],spatial_pages.words[at+2u]));}
float lie_page_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip,out uint blocker,out bool accepted) {
    blocker=0xffffffffu;accepted=false;
    if(root>=spatial_pages.words[3])return maximum;
    uint index=spatial_pages.words[spatial_pages.words[4]+root];if(index==0u)return maximum;
    uint at=spatial_pages.words[5]+(index-1u)*16u;
    vec3 low=lie_page_vec(at),high=lie_page_vec(at+4u);
    ivec3 dims=ivec3(spatial_pages.words[at+3u],spatial_pages.words[at+7u],spatial_pages.words[at+8u]);
    if(any(lessThan(dims,ivec3(1))) || any(greaterThan(dims,ivec3(64))))return maximum;
    vec3 width=(high-low)/vec3(dims);float enter=minimum,leave=maximum;
    for(int axis=0;axis<3;axis++) {
        if(abs(d[axis])<1e-20){if(o[axis]<low[axis] || o[axis]>high[axis]){accepted=true;return maximum;}}
        else {float a=(low[axis]-o[axis])/d[axis],b=(high[axis]-o[axis])/d[axis];enter=max(enter,min(a,b));leave=min(leave,max(a,b));}
    }
    if(isnan(enter) || isnan(leave) || isinf(enter) || isinf(leave))return maximum;
    if(enter>leave){accepted=true;return maximum;}
    ivec3 cell=clamp(ivec3(floor((o+d*enter-low)/width)),ivec3(0),dims-1),step=ivec3(sign(d));
    vec3 next=vec3(3.402823e38),increment=vec3(3.402823e38);
    for(int axis=0;axis<3;axis++)if(abs(d[axis])>=1e-20) {
        float edge=low[axis]+float(cell[axis]+(step[axis]>0?1:0))*width[axis];
        next[axis]=max(enter,(edge-o[axis])/d[axis]);increment[axis]=abs(width[axis]/d[axis]);
    }
    lie_page_stat(0u);float nearest=maximum;
    for(int iteration=0;iteration<196;iteration++) {
        if(any(lessThan(cell,ivec3(0))) || any(greaterThanEqual(cell,dims))){accepted=true;return nearest;}
        uint address=uint((cell.z*dims.y+cell.y)*dims.x+cell.x),base=spatial_pages.words[at+9u];
        uint begin=spatial_pages.words[base+address],end=spatial_pages.words[base+address+1u];
        // Bound pathological dense pages; fallback always traces the full ray.
        if(end<begin || end-begin>256u || end>spatial_pages.words[at+11u])return maximum;
        lie_page_stat(1u);
        for(uint k=begin;k<end;k++) {
            uint sid=spatial_pages.words[spatial_pages.words[at+10u]+k];if(sid==skip)continue;
            lie_page_stat(2u);
            vec4 source=lie_visibility_position_radius(sid);vec3 normal=lie_visibility_normal(sid);
            float denominator=dot(normal,d);if(abs(denominator)<1e-8)continue;
            float t=dot(normal,source.xyz-o)/denominator;if(t<=minimum || t>=nearest)continue;
            vec3 delta=o+t*d-source.xyz;
            if(dot(delta,delta)>source.w*source.w)continue;
            nearest=t;blocker=sid;if(nearest<=early){accepted=true;return nearest;}
        }
        int axis=next.x<=next.y && next.x<=next.z?0:next.y<=next.z?1:2;
        float boundary=next[axis];
        if(isnan(boundary) || isinf(boundary))return maximum;
        // The membership guard is wider than float32 cell-plane rounding.
        float tolerance=2e-6*(1.+abs(boundary));
        if(boundary>min(leave,nearest)+tolerance){accepted=true;return nearest;}
        cell[axis]+=step[axis];next[axis]+=increment[axis];
    }
    return maximum; // Unresolved traversal: original BLAS is authoritative.
}

float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip,out uint blocker) {
    blocker=0xffffffffu;
    if((phase.value.w&4)!=0) {
        bool accepted;float result=lie_page_trace(o,d,minimum,maximum,early,root,skip,blocker,accepted);
        if(accepted)return result;
        lie_page_stat(3u);blocker=0xffffffffu;
    }
    bool fast=(phase.value.w&2)!=0;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
    uint end=floatBitsToUint(lie_blas_node(root).lo.w),i=root;
    float nearest=maximum;
    while(i<end) {
        LieSourceNode n=lie_blas_node(i);uint escape=floatBitsToUint(n.lo.w),leaf=floatBitsToUint(n.hi.w);
        if(!(fast?lie_source_box_precomputed(o,d,inverse,n.lo.xyz,n.hi.xyz,minimum,nearest):lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest))){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint count=lie_visibility_refs.values[leaf];
        for(uint k=0u;k<count;k++) {
            uint sid=lie_visibility_refs.values[leaf+1u+k];if(sid==skip)continue;
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
    if(query_memory.words[1]!=0u && hint!=0u) {
        lie_query_stat(0u);
        if(lie_witness_blocks(hint,o,d,bias,.75*limit,owner,source_id)){found=hint;lie_query_stat(1u);return 0.;}
    }
    lie_query_stat(2u);
    bool fast=(phase.value.w&2)!=0;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
    uint i=0u,end=lie_visibility_scene.values[0];
    while(i<end) {
        LieSourceNode node=lie_scene_node(i);uint escape=floatBitsToUint(node.lo.w),leaf=floatBitsToUint(node.hi.w);
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


void lie_build_persistent_visibility(uint i) {
    if(i>=uint(parameters.counts.x))return;
    uvec2 winner_flags=source_visibility.values[i];if((winner_flags.y&0x80000000u)==0u)return;
    uvec2 result=uvec2(0xffffffffu),resident=uvec2(0);
    uint slot=lie_visibility_slot(i),at=64u+slot*3u,valid=0u;
    bool use_cache=lie_visibility_persistent() && slot<visibility_control.words[2];
    if(use_cache){resident=uvec2(persistent_visibility.words[at],persistent_visibility.words[at+1u]);valid=persistent_visibility.words[at+2u];}
    Projection p=projected.v[i];
    if(surface_options.flags.x!=0u && surface_options.flags.w!=0u) {
        for(uint light=0u;light<surface_lights.header.y;light++) {
            uint mask=light==7u?127u:255u,value=mask;
            vec3 power=surface_lights.values[light*2u+1u].rgb;
            if(max(power.r,max(power.g,power.b))>0.) {
                if(use_cache && (valid&(1u<<light))!=0u) {
                    value=lie_pack_visibility(resident,light);
                    if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[4u+light],1u);
                } else {
                    uint found,hint=slot<visibility_control.words[2] && query_memory.words[1]!=0u?query_memory.words[64u+slot*8u+light]:0u;
                    float visibility=lie_source_world_visibility_hint(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
                        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)),hint,found);
                    if(slot<visibility_control.words[2] && query_memory.words[1]!=0u)query_memory.words[64u+slot*8u+light]=found;
                    value=uint(round(clamp(visibility,0.,1.)*float(mask)));
                    if(use_cache){resident=lie_write_visibility(resident,light,value);valid|=1u<<light;}
                    if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[12u+light],1u);
                }
            } else if(visibility_control.words[1]!=0u)atomicAdd(visibility_control.words[20u+light],1u);
            result=lie_write_visibility(result,light,value);
        }
    }
    if(use_cache){persistent_visibility.words[at]=resident.x;persistent_visibility.words[at+1u]=resident.y;persistent_visibility.words[at+2u]=valid;}
    source_visibility.values[i]=result;
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









void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=11;

        if((phase.value.w&1)!=0){if(i>=active_visibility.values[3])return;i=active_visibility.values[4u+i];}
        lie_build_persistent_visibility(i);return;
    
}
