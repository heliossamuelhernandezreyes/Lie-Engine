#[compute]
#version 450
layout(local_size_x=64) in;
layout(push_constant,std430) uniform Phase {ivec4 value;} phase;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=28,std430) readonly buffer SourceVisibility {uvec2 values[];} source_visibility;
layout(set=0,binding=35,std430) buffer ActiveVisibility {uint values[];} active_visibility;
layout(set=0,binding=37,std430) readonly buffer SpatialOrder {uint values[];} spatial_order;
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
        if(count>0u){stream_base=atomicAdd(active_visibility.values[3],count);atomicMax(active_visibility.values[0],(stream_base+count+63u)/64u);}
    }
    barrier();
    if(selected)active_visibility.values[4u+stream_base+rank]=id;
}

void main() {
    uint at=gl_GlobalInvocationID.x,i=0u;bool selected=false;
    if(at<uint(parameters.counts.x)){i=spatial_order.values[uint(phase.value.w)+at];selected=(source_visibility.values[i].x&1u)!=0u;}
    lie_stream_append(selected,i,gl_LocalInvocationID.x);
}
