"""Compile independent entry points from the accepted LIE 1.3 equations.

The generator removes unrelated main branches, unreachable helper functions,
unused descriptor declarations and workgroup storage before Godot import.
No primitive, material, recovery or lighting equation is rewritten.
"""
import json,re
from pathlib import Path
from lie_wall16_shader import generate as baseline
ROOT=Path(__file__).resolve().parents[1]
STAGES=(1,2,3,4,6,7,8,9,10,11,12,13,14,15,16,17,18,19)
def mask(source):
    return re.sub(r'/\*.*?\*/|//[^\n]*',lambda m:re.sub(r'[^\n]',' ',m[0]),source,flags=re.S)
def end_brace(source,start):
    depth=0
    for i in range(start,len(source)):
        if source[i]=='{':depth+=1
        elif source[i]=='}':
            depth-=1
            if depth==0:return i+1
    raise ValueError('Unbalanced source')
def functions(source):
    clean=mask(source);found=[]
    for match in re.finditer(r'^\w+\s+(\w+)\s*\([^;{}]*\)\s*\{',clean,re.M):
        end=end_brace(clean,match.end()-1)
        found.append((match[1],match.start(),end,source[match.start():end]))
    assert len({f[0] for f in found})==len(found),'Overloaded helpers need explicit closure support'
    return found
def stage_body(source,stage):
    main=next(f for f in functions(source) if f[0]=='main')[3]
    common=main[:main.index('    if(stage==14)')].replace('int stage=phase.value.x;',f'const int stage={stage};')
    key=2 if stage==3 else 8 if stage==9 else stage
    if stage in (4,6):
        start=main.index('    if(i>=pixels) return;');branch=main[start:main.rfind('}')]
    else:
        match=re.search(r'    if\(stage=='+str(key)+r'(?:\)| \|\| stage==\d+\))\s*\{',mask(main))
        assert match,stage
        start=match.end()-1;end=end_brace(mask(main),start)
        branch=main[start+1:end-1]
    return common+branch+'\n}\n'
def generate(stage):
    source=baseline();all_functions=functions(source);main=stage_body(source,stage)
    by_name={f[0]:f for f in all_functions if f[0]!='main'};needed=set();pending=[main]
    while pending:
        calls=set(re.findall(r'\b(\w+)\s*\(',mask(pending.pop())))
        for name in sorted(calls & by_name.keys()-needed):needed.add(name);pending.append(by_name[name][3])
    source=source[:all_functions[-1][1]] # main is the final definition
    for name,start,end,_ in reversed(all_functions[:-1]):
        if name not in needed:source=source[:start]+source[end:]
    source+='\n'+main
    # Descriptor declarations have one interface block or one opaque image.
    declarations=list(re.finditer(r'layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;',source,re.S))
    assert len(declarations)==37,len(declarations)
    used=source
    for match in reversed(declarations):used=used[:match.start()]+used[match.end():]
    bindings=[]
    for match in reversed(declarations):
        name=match[2] or match[3]
        if not re.search(r'\b'+name+r'\b',mask(used)):source=source[:match.start()]+source[match.end():]
        else:bindings.append(int(match[1]))
    if stage!=18:
        source=re.sub(r'^shared vec3 query_(?:positions|normals)\[64\];\n','',source,flags=re.M)
    source=source.replace('#version 450','#version 450\n// GENERATED dedicated stage '+str(stage)+'; tools/lie_wall17_shader.py')
    return source,sorted(bindings)
def outputs():
    result={};bindings={}
    for stage in STAGES:
        source,bindings[stage]=generate(stage);result[f'gpu_compute/shaders/lie_wall17_stage_{stage:02d}.glsl']=source
    gd='extends RefCounted\n## Generated immutable shader/binding manifest.\nconst SHADERS={\n'
    for stage in STAGES:gd+=f'    {stage}:preload("res://shaders/lie_wall17_stage_{stage:02d}.glsl"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':')).replace('"','')+'\n'
    # Real old binary, not a branch in the 1.3 shader.
    gd+='const LEGACY=preload("res://shaders/lie_wall15_active.glsl")\nconst LEGACY_BINDINGS='+json.dumps([i for i in range(36) if i!=10],separators=(',',':'))+'\n'
    result['gpu_compute/lie_stage_kernels.gd']=gd
    return result
if __name__=='__main__':
    for name,source in outputs().items():(ROOT/name).write_text(source)
