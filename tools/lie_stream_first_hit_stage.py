"""Inject separate compute first-hit resolver into Godot Vulkan staging ONLY.

Run AFTER lie_stream_candidate_probe.py. Copies a compute shader and adds a
64-byte SSBO per framebuffer pixel, bound to original captured surface packets.
It never writes the primary renderer's G-buffer; all output is diagnostic.
"""
from __future__ import annotations
import argparse
import json
import shutil
from pathlib import Path

HERE=Path(__file__).resolve().parent
SHADER=HERE/'shaders'/'lie_stream_first_hit.comp.glsl'

def replace_once(s,old,new):
    if s.count(old)!=1:
        raise ValueError(f'Expected exactly one stable staged renderer marker: {old[:100]}')
    return s.replace(old,new)

def apply(stage:Path, analytic=False):
    shader=stage/'shaders'/'lie_stream_first_hit.glsl'
    renderer=stage/'lie_direct_renderer.gd'
    test=stage/'test_lie_native_depth.gd'
    if not SHADER.is_file() or not renderer.is_file() or not test.is_file():
        raise FileNotFoundError('Must stage authentic experimental native renderer first')
    if shader.exists():raise ValueError('Refusing to apply resolver twice')
    source=renderer.read_text()
    if 'lie_candidate_risk' not in source or 'var _lie_risk_zero' not in source:
        raise ValueError('Pre-discard candidate probe must be applied BEFORE resolver')
    script=test.read_text()
    source=replace_once(source,
        'const NativeShadowShader = preload("res://shaders/lie_direct_native_shadow.glsl")',
        'const NativeShadowShader = preload("res://shaders/lie_direct_native_shadow.glsl")\n'
        'const StreamResolveShader = preload("res://shaders/lie_stream_first_hit.glsl")')
    source=replace_once(source,
        'var _lie_risk_zero := PackedByteArray()',
        'var _lie_risk_zero := PackedByteArray()\n'
        'var _lie_result := RID()\n'
        'var _lie_resolve_set := RID()\n'
        'var _lie_result_zero := PackedByteArray()')
    source=replace_once(source,
        '    _lie_risk = _buffer(_lie_risk_zero)',
        '    _lie_risk = _buffer(_lie_risk_zero)\n'
        '    _lie_result_zero.resize(size * size * 64)\n'
        '    _lie_result = _buffer(_lie_result_zero)')
    source=replace_once(source,
        '"light":LightShader}',
        '"light":LightShader,"lie_stream_resolve":StreamResolveShader}')
    source=replace_once(source,
        'if key == "light": pipeline = _rd.compute_pipeline_create(shader)',
        'if key in ["light","lie_stream_resolve"]: pipeline = _rd.compute_pipeline_create(shader)')
    insertion='    var group_buffer: RID = light_groups'
    extra=r'''    # Diagnostic ONLY: the resolver is a separate compute pass using the
    # EXACT original finite captured cells. It does not overwrite _world.
    var resolve_uniforms: Array[RDUniform] = [
        _uniform(0,proxies),
        _uniform(1,_views),
        _uniform(2,atlas["depth"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),
        _uniform(3,atlas["normal"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),
        _uniform(4,atlas["color"],RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE),
        _uniform(5,rectangles),
        _uniform(6,_lie_risk),
        _uniform(7,_lie_result)
    ]
    _lie_resolve_set = _rd.uniform_set_create(resolve_uniforms,_programs["lie_stream_resolve"]["shader"],0)
    if not _lie_resolve_set.is_valid():
        failure = "Streaming first-hit compute bindings"; return false
    _sets.append(_lie_resolve_set)
'''
    source=replace_once(source,insertion,extra+insertion)
    # The original call does not change: a separate pass follows the completed
    # draw, and the real native G-buffer stays the baseline for comparison.
    after='        _draw(backend,_primary_frame,0); primary_builds += 1; _camera_key = camera_key'
    replacement=after+r'''
        if backend == "native":
            _rd.buffer_update(_lie_result,0,_lie_result_zero.size(),_lie_result_zero)
            var lie_list: int = _rd.compute_list_begin()
            _rd.compute_list_bind_compute_pipeline(lie_list,_programs["lie_stream_resolve"]["pipeline"])
            _rd.compute_list_bind_uniform_set(lie_list,_lie_resolve_set,0)
            _rd.compute_list_set_push_constant(lie_list,PackedInt32Array([_size,0,0,0]).to_byte_array(),16)
            _rd.compute_list_dispatch(lie_list,ceili(float(_size*_size)/64.),1,1)
            _rd.compute_list_end()
'''
    source=replace_once(source,after,replacement)
    source=replace_once(source,
        '"lie_candidate_risk":_rd.buffer_get_data(_lie_risk) if _backend == "native" else PackedByteArray()}',
        '"lie_candidate_risk":_rd.buffer_get_data(_lie_risk) if _backend == "native" else PackedByteArray(),\n'
        '        "lie_first_hit":_rd.buffer_get_data(_lie_result) if _backend == "native" else PackedByteArray()}')
    marker='    var image := Image.create_from_data(data["output_size"]'
    script=replace_once(script,marker,r'''    if label in ["0-native","1-native","2-native"]:
        var hit_record: PackedByteArray = native["lie_first_hit"]
        if hit_record.size() != data["output_size"]*data["output_size"]*64:
            printerr("LIE compute first-hit packet length mismatch"); quit(1); return
        var result_file := FileAccess.open(prefix+"-first-hit.bin",FileAccess.WRITE)
        result_file.store_buffer(hit_record); result_file.close()
'''+marker)
    selected=HERE/'shaders'/'lie_stream_first_hit_analytic.comp.glsl' if analytic else SHADER
    shutil.copyfile(selected,shader)
    renderer.write_text(source)
    test.write_text(script)
    return {'schema':'lie-native-stream-first-hit-staging/1',
            'scope':'separate compute; no writes to original native G-buffer',
            'output_record_bytes':64,'resolution':'full grid dispatch, expensive geometry traversal only on flagged pixels',
            'shader':str(shader),'staged_renderer':str(renderer),
            'limitations':['Not a mobile optimized GPU worklist dispatch',
                           'No original Blender source mesh',
                           'No accepted production G-buffer publication',
                           'GPU result must be validated against independent finite-cell oracle']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage',required=True,type=Path)
    p.add_argument('--analytic',action='store_true',help='Use V5 analytic enumeration; preserve V4 shader')
    args=p.parse_args()
    print(json.dumps(apply(args.stage,args.analytic),indent=2))

if __name__=='__main__':main()
