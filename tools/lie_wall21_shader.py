"""Visibility-only binaries with the same source equations and a 32-byte ABI."""
import json
from pathlib import Path
from lie_wall17_shader import generate
from lie_wall19_shader import outputs as stream_outputs,prune
ROOT=Path(__file__).resolve().parents[1]
OLD='struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };'
NEW='struct Sample { vec4 position_radius; vec4 normal_gray; };'
def outputs():
    source=stream_outputs();shaders={'visibility':generate(11)[0],'prepare':source['gpu_compute/shaders/lie_wall19_prepare.glsl'],'trace':source['gpu_compute/shaders/lie_wall19_trace.glsl']};files={};bindings={}
    for key,text in shaders.items():
        if text.count(OLD)!=1:raise ValueError('source sample declaration changed')
        text=text.replace(OLD,NEW);text,used=prune(text);bindings[key]=used
        files[f'gpu_compute/shaders/lie_wall21_{key}.glsl']=text
    files['gpu_compute/lie_shadow_view_kernels.gd']='extends RefCounted\nconst SHADERS={\n'+''.join(f'    "{k}":preload("res://shaders/lie_wall21_{k}.glsl"),\n' for k in shaders)+'}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':'))+'\n'
    oracle=(ROOT/'gpu_compute/shaders/lie_witness_test.glsl').read_text()
    if 'id*5u' not in oracle:raise ValueError('fixture source accessor changed')
    files['gpu_compute/shaders/lie_compact_shadow_test.glsl']=oracle.replace('id*5u','id*2u')
    return files
if __name__=='__main__':
    for name,text in outputs().items():(ROOT/name).write_text(text)
