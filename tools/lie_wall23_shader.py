"""Generate scalar-power response kernels from the accepted surface equations.

Capture the coarse direct term and its detailed replacement. Reuse only
rescales these terms; the existing indirect field is recomputed unchanged.
"""
import json,re
from pathlib import Path
from lie_wall17_shader import generate as baseline,functions,mask
ROOT=Path(__file__).resolve().parents[1]
DECL='''layout(set=0,binding=42,std430) buffer PowerResponses {
    vec4 anchors[8]; vec4 values[];
} power_responses;
'''
REUSE='''void lie_resolve_surface(uint i) {
    uint pixels=uint(parameters.counts.z*parameters.counts.w);
    if(i>=pixels)return;
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    vec4 base=imageLoad(specular_image,q);if(base.a<.5)return;
    vec3 old_total=vec3(0),new_total=vec3(0);
    for(uint l=0u;l<surface_lights.header.y;l++) {
        vec3 current=surface_lights.values[l*2u+1u].rgb;
        if(max(current.r,max(current.g,current.b))<=0.)continue;
        vec3 anchor=power_responses.anchors[l].rgb,scale=vec3(0);
        for(int c=0;c<3;c++)if(anchor[c]>0.)scale[c]=current[c]/anchor[c];
        uint at=2u*(l*pixels+i);
        old_total+=power_responses.values[at].rgb*scale;
        new_total+=power_responses.values[at+1u].rgb*scale;
    }
    imageStore(specular_image,q,vec4(max(base.rgb-old_total,vec3(0))+new_total,base.a));
}'''
def prune(source):
    found=functions(source);by_name={f[0]:f for f in found};needed={'main'};pending=[by_name['main'][3]]
    while pending:
        calls=set(re.findall(r'\b(\w+)\s*\(',mask(pending.pop())))
        for name in sorted(calls & by_name.keys()-needed):needed.add(name);pending.append(by_name[name][3])
    for name,start,end,_ in reversed(found):
        if name not in needed:source=source[:start]+source[end:]
    declarations=list(re.finditer(r'layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;',source,re.S))
    used=source
    for m in reversed(declarations):used=used[:m.start()]+used[m.end():]
    bindings=[]
    for m in reversed(declarations):
        if re.search(r'\b'+(m[2] or m[3])+r'\b',mask(used)):bindings.append(int(m[1]))
        else:source=source[:m.start()]+source[m.end():]
    return source,sorted(bindings)
def generate(kind):
    source,_=baseline(10)
    source=source.replace('void lie_resolve_surface(uint i) {',DECL+'\nvoid lie_resolve_surface(uint i) {',1)
    if kind=='reuse':
        f=next(f for f in functions(source) if f[0]=='lie_resolve_surface');source=source[:f[1]]+REUSE+source[f[2]:]
    elif kind=='capture':
        source=source.replace('    if(i>=uint(parameters.counts.z*parameters.counts.w))return;','''    uint pixels=uint(parameters.counts.z*parameters.counts.w);
    if(i>=pixels)return;
    if(i==0u)for(uint l=0u;l<surface_lights.header.y;l++)power_responses.anchors[l]=surface_lights.values[l*2u+1u];
    for(uint l=0u;l<surface_lights.header.y;l++) {
        uint at=2u*(l*pixels+i);
        power_responses.values[at]=vec4(0);
        power_responses.values[at+1u]=vec4(0);
    }''',1)
        source=source.replace('old_total+=old_direct;','old_total+=old_direct;\n        vec3 contribution=vec3(0);',1)
        source=source.replace('new_total+=max(response,vec3(0))*local_direct*gate*visibility;','contribution=max(response,vec3(0))*local_direct*gate*visibility;',1)
        old='} else new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);'
        assert source.count(old)==1
        source=source.replace(old,'''} else contribution=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);
        power_responses.values[2u*(l*pixels+i)]=vec4(old_direct,1);
        power_responses.values[2u*(l*pixels+i)+1u]=vec4(contribution,1);
        new_total+=contribution;''',1)
    else:raise ValueError(kind)
    source,bindings=prune(source)
    source=source.replace('// GENERATED dedicated stage 10; tools/lie_wall17_shader.py','// GENERATED direct response '+kind+'; tools/lie_wall23_shader.py')
    return source,bindings
def outputs():
    result={};bindings={}
    for kind in ('capture','reuse'):
        source,bindings[kind]=generate(kind);result[f'gpu_compute/shaders/lie_wall23_{kind}.glsl']=source
    gd='extends RefCounted\n## Generated direct response shader/binding manifest.\nconst SHADERS={\n'
    for kind in bindings:gd+=f'    "{kind}":preload("res://shaders/lie_wall23_{kind}.glsl"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':'))+'\n'
    result['gpu_compute/lie_power_response_kernels.gd']=gd
    return result
if __name__=='__main__':
    for path,source in outputs().items():(ROOT/path).write_text(source)
