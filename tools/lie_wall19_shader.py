"""Coherent winner queues; cache/witness preparation separated from exact BLAS."""
import json,re
from pathlib import Path
from lie_wall17_shader import generate,functions,mask
ROOT=Path(__file__).resolve().parents[1]
LIB=ROOT/'gpu_compute/shaders/lib'
def prune(source):
    fs=functions(source);by={f[0]:f for f in fs if f[0]!='main'};needed=set();pending=[next(f[3] for f in fs if f[0]=='main')]
    while pending:
        calls=set(re.findall(r'\b(\w+)\s*\(',mask(pending.pop())))
        for name in sorted(calls&by.keys()-needed):needed.add(name);pending.append(by[name][3])
    for name,start,end,_ in reversed(fs):
        if name!='main' and name not in needed:source=source[:start]+source[end:]
    pattern=r'layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;'
    ds=list(re.finditer(pattern,source,re.S));used=source
    for m in reversed(ds):used=used[:m.start()]+used[m.end():]
    bindings=[]
    for m in reversed(ds):
        if re.search(r'\b'+(m[2] or m[3])+r'\b',mask(used)):bindings.append(int(m[1]))
        else:source=source[:m.start()]+source[m.end():]
    return source,sorted(bindings)
def main_replace(source,body):
    main=next(f for f in functions(source) if f[0]=='main');return source[:main[1]]+body+'\n'
COMMON='''#[compute]
#version 450
layout(local_size_x=64) in;
layout(push_constant,std430) uniform Phase {ivec4 value;} phase;
'''
PREPARE='''
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
'''
TRACE='''
void lie_stream_trace(uint i,uint light) {
    Projection p=projected.v[i];uint slot=lie_visibility_slot(i),mask=light==7u?127u:255u,found;
    float visibility=lie_source_world_visibility_hint(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)),0u,found);
    if(slot<visibility_control.words[2] && query_memory.words[1]!=0u)query_memory.words[64u+slot*8u+light]=found;
    uint value=uint(round(clamp(visibility,0.,1.)*float(mask)));lie_stream_store(i,slot,light,value,true);
}
'''
def outputs():
    result={};bindings={}
    s=generate(16)[0]
    start=s.index('        if((atomicOr(');end=s.index('}return;',start)+len('}return;')
    s=s[:start]+'        atomicOr(source_visibility.values[owner].x,1u);return;'+s[end:]
    result['mark'],bindings['mark']=prune(s)
    params=next(m[0] for m in re.finditer(r'layout\(set=0,binding=6,std430\).*?parameters;',generate(16)[0],re.S))
    s=COMMON+params+'''
layout(set=0,binding=28,std430) readonly buffer SourceVisibility {uvec2 values[];} source_visibility;
layout(set=0,binding=35,std430) buffer ActiveVisibility {uint values[];} active_visibility;
layout(set=0,binding=37,std430) readonly buffer SpatialOrder {uint values[];} spatial_order;
'''+(LIB/'lie_stream_compact.glslinc').read_text().replace('STREAM_QUEUE','active_visibility')+'''
void main() {
    uint at=gl_GlobalInvocationID.x,i=0u;bool selected=false;
    if(at<uint(parameters.counts.x)){i=spatial_order.values[uint(phase.value.w)+at];selected=(source_visibility.values[i].x&1u)!=0u;}
    lie_stream_append(selected,i,gl_LocalInvocationID.x);
}
'''
    result['compact'],bindings['compact']=prune(s)
    source=generate(11)[0];store=(LIB/'lie_visibility_stream.glslinc').read_text()
    s=main_replace(source,store+PREPARE+(LIB/'lie_stream_compact.glslinc').read_text().replace('STREAM_QUEUE','trace_queue')+'''
void main() {
    uint at=gl_GlobalInvocationID.x,i=0u;bool selected=false;
    if(at<active_visibility.values[3]){i=active_visibility.values[4u+at];selected=lie_stream_prepare(i,uint(phase.value.z));}
    lie_stream_append(selected,i,gl_LocalInvocationID.x);
}
''')
    result['prepare'],bindings['prepare']=prune(s)
    # The traversal binary has no cache/witness fast-path; all its lanes need a ray.
    a=source.index('    if(query_memory.words[1]!=0u && hint!=0u) {');b=source.index('    lie_query_stat(2u);',a);source=source[:a]+source[b:]
    source=source.replace('LieSourceNode n=lie_blas_node(i);','lie_stream_stat(5u);LieSourceNode n=lie_blas_node(i);')
    source=source.replace('uint sid=lie_visibility_refs.values[leaf+1u+k];','lie_stream_stat(6u);uint sid=lie_visibility_refs.values[leaf+1u+k];')
    source=source.replace('LieSourceNode node=lie_scene_node(i);','lie_stream_stat(7u);LieSourceNode node=lie_scene_node(i);')
    # Declaration precedes helpers that instrument traversal.
    source=source.replace('float lie_source_trace(',store+'\nfloat lie_source_trace(',1)
    # Store calls helpers defined later, so use a prototype before the traversal.
    source=source.replace('void lie_stream_store(uint i,uint slot,uint light,uint value,bool cache_value) {', 'void lie_stream_store(uint i,uint slot,uint light,uint value,bool cache_value);\nvoid lie_stream_store_impl(uint i,uint slot,uint light,uint value,bool cache_value) {',1)
    # Move its implementation after the existing visibility helpers.
    fs=functions(source);impl=next(f for f in fs if f[0]=='lie_stream_store_impl');body=impl[3].replace('lie_stream_store_impl','lie_stream_store')
    source=source[:impl[1]]+source[impl[2]:]
    s=main_replace(source,body+TRACE+'''
void main() {
    uint at=gl_GlobalInvocationID.x;if(at>=trace_queue.values[3])return;
    lie_stream_trace(trace_queue.values[4u+at],uint(phase.value.z));
}
''')
    result['trace'],bindings['trace']=prune(s)
    result['reset']=COMMON+'''layout(set=0,binding=38,std430) buffer TraceQueue {uint values[];} trace_queue;
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;
void main(){uint i=gl_GlobalInvocationID.x;if(i==0u){trace_queue.values[0]=0u;trace_queue.values[1]=1u;trace_queue.values[2]=1u;trace_queue.values[3]=0u;}if(i<8u && phase.value.z==0)query_memory.words[24u+i]=0u;}
''';bindings['reset']=[38,39]
    files={f'gpu_compute/shaders/lie_wall19_{k}.glsl':v for k,v in result.items()}
    gd='extends RefCounted\nconst SHADERS={\n'+''.join(f'    "{k}":preload("res://shaders/lie_wall19_{k}.glsl"),\n' for k in result)+'}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':'))+'\n'
    files['gpu_compute/lie_visibility_stream_kernels.gd']=gd;return files
if __name__=='__main__':
    for name,text in outputs().items():(ROOT/name).write_text(text)
