"""Stable reference identities, direct workgroup ownership and persistent visibility."""
from pathlib import Path
from lie_wall10_shader import generate as baseline
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=baseline()
    start=s.index('void lie_build_source_visibility(uint i) {')
    end=s.index('\nvoid lie_resolve_surface(uint i)',start)
    s=s[:start]+(ROOT/'gpu_compute/shaders/lib/lie_persistent_visibility.glslinc').read_text()+'\n'+s[end:]
    s=replace(s,'if(stage==11) {lie_build_source_visibility(i);return;}','''if(stage==11) {lie_build_persistent_visibility(i);return;}
    if(stage==12) {lie_invalidate_persistent(i);return;}
    if(stage==13) {lie_prepare_persistent(i);return;}''')
    s=replace(s,'''if(i>=uint(parameters.counts.x))return;
        uint j=job_index(i);uvec4 job=jobs.v[j];uint sid=sample_refs.values[job.x+i-job.w];''','''uint j;
        if(phase.value.w>0) {
            uint group=gl_WorkGroupID.x+gl_WorkGroupID.y*gl_NumWorkGroups.x;
            uvec2 block=source_blocks.values[uint(phase.value.w)-1u+group];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else {if(i>=uint(parameters.counts.x))return;j=job_index(i);}
        uvec4 job=jobs.v[j];uint reference_index=job.x+i-job.w;
        uint sid=sample_refs.values[reference_index];''')
    s=replace(s,'p.normal=vec4(n,front);','p.normal=vec4(n,float(reference_index));')
    return s
def generate_test():
    common=(ROOT/'gpu_compute/shaders/lib/lie_source_visibility.glslinc').read_text()
    cache=(ROOT/'gpu_compute/shaders/lib/lie_persistent_visibility.glslinc').read_text()
    return '''#[compute]
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
'''+common+cache+'''
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(phase.value==13u)lie_prepare_persistent(i);
    if(phase.value==12u)lie_invalidate_persistent(i);
    if(phase.value==11u)lie_build_persistent_visibility(i);
    if(phase.value==99u && i==0u)source_visibility.values[0]=source_blocks.values[0];
}
'''
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall11_persistent.glsl').write_text(generate())
    (ROOT/'gpu_compute/shaders/lie_persistent_visibility_test.glsl').write_text(generate_test())
