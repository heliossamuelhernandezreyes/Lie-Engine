#[compute]
#version 450
layout(local_size_x=64) in;
layout(push_constant,std430) uniform Phase {ivec4 value;} phase;
layout(set=0,binding=38,std430) buffer TraceQueue {uint values[];} trace_queue;
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;
void main(){uint i=gl_GlobalInvocationID.x;if(i==0u){trace_queue.values[0]=0u;trace_queue.values[1]=1u;trace_queue.values[2]=1u;trace_queue.values[3]=0u;}if(i<8u && phase.value.z==0)query_memory.words[24u+i]=0u;}
