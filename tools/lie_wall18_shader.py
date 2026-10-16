"""A page-addressed visibility kernel alongside the untouched 1.4 kernel."""
from pathlib import Path
from lie_wall17_shader import generate as dedicated
from lie_wall16_shader import generate_test
ROOT=Path(__file__).resolve().parents[1]
def inject(source,test=False):
    anchor='float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip,out uint blocker) {'
    include=(ROOT/'gpu_compute/shaders/lib/lie_spatial_pages.glslinc').read_text()
    source=source.replace(anchor,include+'\n'+anchor,1)
    trigger='    blocker=0xffffffffu;\n    bool fast='
    if source.count(trigger)!=1:raise ValueError('Exact world source-trace anchor')
    gate='query_memory.words[4]!=0u' if test else '(phase.value.w&4)!=0'
    source=source.replace(trigger,'''    blocker=0xffffffffu;
    if('''+gate+''') {
        bool accepted;float result=lie_page_trace(o,d,minimum,maximum,early,root,skip,blocker,accepted);
        if(accepted)return result;
        lie_page_stat(3u);blocker=0xffffffffu;
    }
    bool fast=''',1)
    return source
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall18_pages_11.glsl').write_text(inject(dedicated(11)[0]))
    (ROOT/'gpu_compute/shaders/lie_pages_test.glsl').write_text(inject(generate_test(),True))
