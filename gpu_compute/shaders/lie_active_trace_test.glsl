#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Bank {vec4 values[];} bank;
layout(set=0,binding=1,std430) readonly buffer BLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=2,std430) readonly buffer Refs {uint values[];} lie_visibility_refs;
layout(set=0,binding=3,std430) readonly buffer Scene {uint values[];} lie_visibility_scene;
struct Projection {vec4 world;vec4 normal;vec4 gradient;};
layout(set=0,binding=4,std430) readonly buffer Projected {Projection v[];} projected;
layout(set=0,binding=5,std430) readonly buffer Options {uvec4 flags;vec4 metric;} surface_options;
layout(set=0,binding=6,std430) readonly buffer Params {ivec4 counts;} parameters;
layout(set=0,binding=7,std430) readonly buffer Lights {uvec4 header;vec4 values[];} surface_lights;
layout(set=0,binding=8,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;
layout(push_constant,std430) uniform Phase {uint value;} phase;
vec4 lie_visibility_position_radius(uint sid) {return bank.values[sid*5u];}
vec3 lie_visibility_normal(uint sid) {return bank.values[sid*5u+1u].xyz;}
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

float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {
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
            nearest=t;if(nearest<=early)return nearest;
        }
        i=escape;
    }
    return nearest;
}
float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {
    vec3 delta=light-point;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 o=point+normal*bias,d=delta/distance_to_light;
    float limit=min(reach,distance_to_light-bias),nearest=limit;
    if(limit<=bias)return 1.;
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
            nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu);
            if(nearest<=.75*limit)return 0.;
        }
        i=escape;
    }
    return smoothstep(.75*limit,limit,nearest);
}
// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.
layout(set=0,binding=29,std430) readonly buffer SourceBlocks {uvec2 values[];} source_blocks;
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
void lie_prepare_persistent(uint i) {
    if(i<24u)visibility_control.words[4u+i]=0u;
    if(i!=0u || !lie_visibility_persistent())return;
    uint count=surface_lights.header.y,old_count=persistent_visibility.words[2],dirty=0u;
    bool reset=persistent_visibility.words[1]==0u ||
        persistent_visibility.words[36]!=floatBitsToUint(surface_options.metric.x) ||
        persistent_visibility.words[37]!=floatBitsToUint(surface_options.metric.y);
    for(uint light=0u;light<8u;light++) {
        uint at=4u+light*4u;
        uvec3 position=light<count?floatBitsToUint(surface_lights.values[light*2u].xyz):uvec3(0);
        if(reset || (light<count)!=(light<old_count) ||
           (light<count && any(notEqual(position,uvec3(persistent_visibility.words[at],persistent_visibility.words[at+1u],persistent_visibility.words[at+2u]))))) {
            dirty|=1u<<light;
            persistent_visibility.words[41u+light]++;
        }
        persistent_visibility.words[at]=position.x;persistent_visibility.words[at+1u]=position.y;persistent_visibility.words[at+2u]=position.z;
    }
    persistent_visibility.words[0]=dirty;persistent_visibility.words[1]=1u;
    persistent_visibility.words[2]=count;persistent_visibility.words[3]++;
    persistent_visibility.words[36]=floatBitsToUint(surface_options.metric.x);
    persistent_visibility.words[37]=floatBitsToUint(surface_options.metric.y);
    if(dirty!=0u)persistent_visibility.words[40]++;
}
void lie_invalidate_persistent(uint i) {
    if(!lie_visibility_persistent() || i>=visibility_control.words[2])return;
    uint dirty=persistent_visibility.words[0];
    if(dirty!=0u)persistent_visibility.words[64u+i*3u+2u]&=~dirty;
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
                    float visibility=lie_source_world_visibility(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
                        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)));
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

void main() {
    uint i=gl_GlobalInvocationID.x;
    if(phase.value==13u)lie_prepare_persistent(i);
    if(phase.value==12u)lie_invalidate_persistent(i);
    if(phase.value==11u)lie_build_persistent_visibility(i);
    if(phase.value==99u && i==0u)source_visibility.values[0]=source_blocks.values[0];
}
