#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Bank {vec4 values[];} bank;
layout(set=0,binding=1,std430) readonly buffer BLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=2,std430) readonly buffer Leaves {uint values[];} lie_visibility_refs;
layout(set=0,binding=3,std430) readonly buffer Scene {uint values[];} lie_visibility_scene;
struct Query {vec4 point;vec4 normal;vec4 light;uvec4 identity;};
layout(set=0,binding=4,std430) readonly buffer Queries {Query values[];} queries;
layout(set=0,binding=5,std430) buffer Results {float values[];} results;
vec4 lie_visibility_position_radius(uint id){return bank.values[id*5u];}
vec3 lie_visibility_normal(uint id){return bank.values[id*5u+1u].xyz;}
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
    if(query_memory.words[4]!=0u) {
        bool accepted;float result=lie_page_trace(o,d,minimum,maximum,early,root,skip,blocker,accepted);
        if(accepted)return result;
        lie_page_stat(3u);blocker=0xffffffffu;
    }
    bool fast=true;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
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
    bool fast=true;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);
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
float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {
    uint found;return lie_source_world_visibility_hint(point,normal,light,reach,bias,owner,source_id,0u,found);
}

void main(){
    uint i=gl_GlobalInvocationID.x;if(i>=query_memory.words[3])return;
    Query q=queries.values[i];uint found,hint=query_memory.words[1]!=0u?query_memory.words[64u+i]:0u;
    results.values[i]=lie_source_world_visibility_hint(q.point.xyz,q.normal.xyz,q.light.xyz,q.point.w,q.normal.w,q.identity.x,q.identity.y,hint,found);
    if(query_memory.words[1]!=0u)query_memory.words[64u+i]=found;
}
