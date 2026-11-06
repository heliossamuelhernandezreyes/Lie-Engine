"""Stage an actual Vulkan runtime canary for error-free float32 products.

Inputs come from an SSBO to prevent compile-time constant folding. Reports
both FMA residual and the Dekker product used by the analytic resolver.
"""
from pathlib import Path
import argparse
import numpy as np


def stage(root):
    root = Path(root)
    source = (Path(__file__).parent/'shaders/lie_stream_first_hit_analytic.comp.glsl').read_text()
    prefix = source[:source.index('struct Ray')]
    shader = prefix + '''
void main() {
    float a=proxies.p[0].lo.x;
    float b=proxies.p[0].lo.y;
    precise float hi=a*b;
    precise float residual=fma(a,b,-hi);
    precise vec2 split=ds_product(a,b);
    output_hit.h[0]=HitRecord(vec4(hi,residual,split),vec4(0.),vec4(0.),vec4(0.));
}
'''
    (root/'shaders/lie_gpu_math_probe.glsl').write_text(shader)
    values = np.zeros(48, dtype='<f4')
    values[32:34] = np.array([0x3f800001, 0x3f800001], dtype='<u4').view('<f4')
    (root/'lie_gpu_math_input.bin').write_bytes(values.tobytes())
    (root/'lie_gpu_math_probe.gd').write_text('''extends SceneTree
func _initialize() -> void:
    var rd := RenderingServer.create_local_rendering_device()
    if rd == null: printerr("No Vulkan math device"); quit(1); return
    var file: RDShaderFile = load("res://shaders/lie_gpu_math_probe.glsl")
    var shader := rd.shader_create_from_spirv(file.get_spirv())
    var pipeline := rd.compute_pipeline_create(shader)
    var input := rd.storage_buffer_create(192,FileAccess.get_file_as_bytes("res://lie_gpu_math_input.bin"))
    var zero := PackedByteArray(); zero.resize(64)
    var output := rd.storage_buffer_create(64,zero)
    var a := RDUniform.new(); a.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; a.binding=0; a.add_id(input)
    var b := RDUniform.new(); b.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; b.binding=7; b.add_id(output)
    var uniforms := rd.uniform_set_create([a,b],shader,0)
    var list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list,pipeline)
    rd.compute_list_bind_uniform_set(list,uniforms,0)
    rd.compute_list_dispatch(list,1,1,1)
    rd.compute_list_end(); rd.submit(); rd.sync()
    var values := rd.buffer_get_data(output).to_float32_array()
    var expected: float = 1.4210854715202004e-14
    var passed: bool = values.size()==16 and values[0]==1.000000238418579 and values[2]==values[0] and values[3]==expected
    print("LIE_GPU_MATH ",JSON.stringify({"fma_high":values[0],"fma_residual":values[1],"dekker_high":values[2],"dekker_residual":values[3],"expected_residual":expected,"fma_residual_correct":values[1]==expected,"dekker_passed":passed}))
    for rid in [uniforms,pipeline,shader,input,output]: rd.free_rid(rid)
    rd.free(); quit(0 if passed else 1)
''')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage', type=Path, required=True)
    stage(p.parse_args().stage)
