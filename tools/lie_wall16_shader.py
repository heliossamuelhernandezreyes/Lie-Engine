"""Resident surface hierarchy and retested opaque occlusion witnesses."""
from pathlib import Path
from lie_wall15_shader import generate as baseline,precomputed_boxes
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def witnesses(s):
    s=replace(s,'float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {',
        (ROOT/'gpu_compute/shaders/lib/lie_occlusion_witness.glslinc').read_text()+'''\nfloat lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip,out uint blocker) {
    blocker=0xffffffffu;''')
    s=replace(s,'nearest=t;if(nearest<=early)return nearest;','nearest=t;blocker=sid;if(nearest<=early)return nearest;')
    s=replace(s,'float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {',
        '''float lie_source_world_visibility_hint(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id,uint hint,out uint found) {
    found=0u;''')
    s=replace(s,'if(limit<=bias)return 1.;','''if(limit<=bias)return 1.;
    if(query_memory.words[1]!=0u && hint!=0u) {
        lie_query_stat(0u);
        if(lie_witness_blocks(hint,o,d,bias,.75*limit,owner,source_id)){found=hint;lie_query_stat(1u);return 0.;}
    }
    lie_query_stat(2u);''')
    s=replace(s,'nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu);\n            if(nearest<=.75*limit)return 0.;',
        '''uint blocker;
            nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu,blocker);
            if(nearest<=.75*limit){found=lie_witness_code(instance,blocker);lie_query_stat(3u);return 0.;}''')
    end='return smoothstep(.75*limit,limit,nearest);\n}'
    s=replace(s,end,end+'''
float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {
    uint found;return lie_source_world_visibility_hint(point,normal,light,reach,bias,owner,source_id,0u,found);
}''')
    return s
def generate():
    s=witnesses(baseline())
    old='''float visibility=lie_source_world_visibility(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
                        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)));'''
    s=replace(s,old,'''uint found,hint=slot<visibility_control.words[2] && query_memory.words[1]!=0u?query_memory.words[64u+slot*8u+light]:0u;
                    float visibility=lie_source_world_visibility_hint(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[light*2u].xyz,
                        surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)),hint,found);
                    if(slot<visibility_control.words[2] && query_memory.words[1]!=0u)query_memory.words[64u+slot*8u+light]=found;''')
    start=s.index('            mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);',s.index('if(stage==2 || stage==3)'))
    end=s.index('            vec3 delta=world-parameters.eye.xyz;',start)
    geometry=s[start:end]
    # Keep exactly the same operations/order as the accepted projection path.
    geometry=geometry.replace('vec3 world=basis*local+inst.origin.xyz;','world=basis*local+inst.origin.xyz;').replace('vec3 n=normalize(', 'n=normalize(').replace('float radius=s.position_radius.w;','radius=s.position_radius.w;')
    s=s[:start]+'''            vec3 world,n;float radius;lie_query_geometry(s,inst,world,n,radius);
            uint source_node=uint(max(round(s.attributes.y),0.0));
'''+s[end:]
    function='void lie_query_geometry(Sample s,Instance inst,out vec3 world,out vec3 n,out float radius) {\n'+geometry+'}\n'
    include=(ROOT/'gpu_compute/shaders/lib/lie_surface_query.glslinc').read_text()
    s=replace(s,'void main() {',function+include+'''\nvoid main() {''')
    s=replace(s,'if(stage==16) {','''if(stage==18){lie_query_build(gl_WorkGroupID.x,gl_LocalInvocationID.x);return;}
    if(stage==19){lie_query_parent(i);return;}
    if(stage==17){lie_query_select(i);return;}
    if(stage==16) {''')
    s=replace(s,'if(i==0u){active_visibility.values[0]=0u;', 'if(i==0u){query_arena.words[0]=0u;query_arena.words[1]=1u;query_arena.words[2]=1u;query_arena.words[3]=0u;active_visibility.values[0]=0u;')
    s=replace(s,'if(phase.value.w>0) {','''if(phase.value.w<0) {
            uint group=gl_WorkGroupID.x;
            uvec2 block=source_blocks.values[query_arena.words[4u+group]];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else if(phase.value.w>0) {''')
    s=replace(s,'if(i<24u)visibility_control.words[4u+i]=0u;', 'if(i<4u)query_memory.words[16u+i]=0u;\n    if(i<24u)visibility_control.words[4u+i]=0u;')
    return s
def generate_test():
    common=(ROOT/'gpu_compute/shaders/lib/lie_source_visibility.glslinc').read_text()
    common=precomputed_boxes(common,'true');common=witnesses(common)
    return '''#[compute]
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
'''+common+'''
void main(){
    uint i=gl_GlobalInvocationID.x;if(i>=query_memory.words[3])return;
    Query q=queries.values[i];uint found,hint=query_memory.words[1]!=0u?query_memory.words[64u+i]:0u;
    results.values[i]=lie_source_world_visibility_hint(q.point.xyz,q.normal.xyz,q.light.xyz,q.point.w,q.normal.w,q.identity.x,q.identity.y,hint,found);
    if(query_memory.words[1]!=0u)query_memory.words[64u+i]=found;
}
'''
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall16_query.glsl').write_text(generate())
    (ROOT/'gpu_compute/shaders/lie_witness_test.glsl').write_text(generate_test())
