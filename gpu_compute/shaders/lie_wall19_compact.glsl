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
// Stable lane order within a 64-entry spatial block; one global append per block.
shared uint stream_prefix[64];
shared uint stream_base;
void lie_stream_append(bool selected,uint id,uint lane) {
    stream_prefix[lane]=selected?1u:0u;barrier();
    for(uint step=1u;step<64u;step*=2u) {
        uint addend=lane>=step?stream_prefix[lane-step]:0u;barrier();
        stream_prefix[lane]+=addend;barrier();
    }
    if(lane==63u) {
        uint count=stream_prefix[63];stream_base=0u;
        if(count>0u){stream_base=atomicAdd(active_visibility.values[3],count);atomicMax(active_visibility.values[0],(stream_base+count+63u)/64u);}
    }
    barrier();
    if(selected)active_visibility.values[4u+stream_base+stream_prefix[lane]-1u]=id;
}

void main() {
    uint at=gl_GlobalInvocationID.x,i=0u;bool selected=false;
    if(at<uint(parameters.counts.x)){i=spatial_order.values[uint(phase.value.w)+at];selected=(source_visibility.values[i].x&1u)!=0u;}
    lie_stream_append(selected,i,gl_LocalInvocationID.x);
}
