"""Winner-only GPU queue and conservative precomputed ray/box broad phase."""
from pathlib import Path
from lie_wall13_shader import generate as baseline
from lie_wall11_shader import generate_test as trace_baseline
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def precomputed_boxes(s, enabled):
    s=replace(s,'float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {',
        (ROOT/'gpu_compute/shaders/lib/lie_precomputed_ray_box.glslinc').read_text()+'''\nfloat lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {
    bool fast=FAST_ENABLED;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);''')
    s=replace(s,'if(!lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest))','if(!(fast?lie_source_box_precomputed(o,d,inverse,n.lo.xyz,n.hi.xyz,minimum,nearest):lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest)))')
    s=replace(s,'uint i=0u,end=lie_visibility_scene.values[0];','bool fast=FAST_ENABLED;vec3 inverse=fast?lie_ray_reciprocal(d):vec3(0);\n    uint i=0u,end=lie_visibility_scene.values[0];')
    s=replace(s,'if(!lie_source_box(o,d,node.lo.xyz,node.hi.xyz,bias,nearest))','if(!(fast?lie_source_box_precomputed(o,d,inverse,node.lo.xyz,node.hi.xyz,bias,nearest):lie_source_box(o,d,node.lo.xyz,node.hi.xyz,bias,nearest)))')
    return s.replace("FAST_ENABLED", enabled)
def generate():
    s=precomputed_boxes(baseline(),"(phase.value.w&2)!=0")
    s=replace(s,'void main() {','''layout(set=0,binding=35,std430) buffer ActiveVisibility {uint values[];} active_visibility;
void main() {''')
    s=replace(s,'if(stage==1) {','''if(stage==1) {
        if(i==0u){active_visibility.values[0]=0u;active_visibility.values[1]=1u;active_visibility.values[2]=1u;active_visibility.values[3]=0u;}''')
    s=replace(s,'if(stage==11) {lie_build_persistent_visibility(i);return;}','''if(stage==16) {
        if(i>=uint(parameters.counts.z*parameters.counts.w))return;
        uint owner=winners.v[i];if(owner==EMPTY || owner>=uint(parameters.counts.x))return;
        if((atomicOr(source_visibility.values[owner].x,1u)&1u)==0u){
            uint at=atomicAdd(active_visibility.values[3],1u);active_visibility.values[4u+at]=owner;
            atomicMax(active_visibility.values[0],at/64u+1u);
        }return;
    }
    if(stage==11) {
        if((phase.value.w&1)!=0){if(i>=active_visibility.values[3])return;i=active_visibility.values[4u+i];}
        lie_build_persistent_visibility(i);return;
    }''')
    return s
def generate_trace_test():return precomputed_boxes(trace_baseline(),"true")
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall15_active.glsl').write_text(generate())
    (ROOT/'gpu_compute/shaders/lie_active_trace_test.glsl').write_text(generate_trace_test())
