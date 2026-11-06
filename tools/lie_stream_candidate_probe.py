"""Staged-only LIE Vulkan candidate-risk probe using streaming-style residual signals.

Writes three GPU atomic bitset planes BEFORE patch-support discard:
0=near finite-patch edge, 1=near captured texel grid, 2=near entry-face tie.
Original shader and renderer are modified ONLY in a temporary staged QA project.
Does not solve first-hit correctness; never-covered triangles cannot signal.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

GLSL_HELPER = r"""
// LIE streaming candidate risk, not corrected surface geometry.
layout(set=0,binding=9,std430) buffer LieCandidateRisk {uint bits[];} lie_risk;
void lie_risk_mark(uint plane) {
    ivec2 xy=ivec2(gl_FragCoord.xy);
    int s=push.value.w;
    if(s<=0 || xy.x<0 || xy.y<0 || xy.x>=s || xy.y>=s)return;
    uint pixel=uint(xy.y*s+xy.x);
    uint words=(uint(s*s)+31u)/32u;
    atomicOr(lie_risk.bits[plane*words+(pixel>>5u)],1u<<(pixel&31u));
}
"""

RENDERER_MARKERS={
 'var _view_packet := PackedByteArray()': 'var _view_packet := PackedByteArray()\nvar _lie_risk := RID()\nvar _lie_risk_zero := PackedByteArray()',
 'var options := PackedByteArray(); options.resize(32); _options = _buffer(options)': '''var options := PackedByteArray(); options.resize(32); _options = _buffer(options)
    # Three packed atomic flags; no GPU-side scene geometry is altered.
    _lie_risk_zero.resize(3*ceili(float(size*size)/32.)*4)
    _lie_risk = _buffer(_lie_risk_zero)''',
 'if key=="native": native_uniforms.append(_uniform(8,native_mesh))': '''if key=="native":
            native_uniforms.append(_uniform(8,native_mesh))
            native_uniforms.append(_uniform(9,_lie_risk))''',
 '        _draw(backend,_primary_frame,0); primary_builds += 1; _camera_key = camera_key': '''        if backend == "native":
            _rd.buffer_update(_lie_risk,0,_lie_risk_zero.size(),_lie_risk_zero)
        _draw(backend,_primary_frame,0); primary_builds += 1; _camera_key = camera_key''',
 '"proxy_packet":_proxy_packet}': '''"proxy_packet":_proxy_packet,
        "lie_candidate_risk":_rd.buffer_get_data(_lie_risk) if _backend == "native" else PackedByteArray()}''',
}

def replace_once(content,old,new,scope):
    if content.count(old)!=1:raise ValueError(f'{scope}: expected exactly one occurrence of: {old[:100]}')
    return content.replace(old,new)

def instrument(shader:Path,renderer:Path,test:Path):
    original=shader.read_text()
    header='layout(location=2) out vec4 out_color;'
    modified=replace_once(original,header,header+'\n'+GLSL_HELPER,'native GLSL')
    face='if(face!=int(face_layer.x-p.meta.x))discard;'
    modified=replace_once(modified,face,'''float lie_second_near=-1e30;
    for(int lie_a=0;lie_a<3;lie_a++)if(lie_a!=axis)lie_second_near=max(lie_second_near,nearv[lie_a]);
    if(abs(nearv[axis]-lie_second_near)<0.00002)lie_risk_mark(2u);
    if(face!=int(face_layer.x-p.meta.x))discard;''','native GLSL face')
    bounds='if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;'
    modified=replace_once(modified,bounds,'''// Candidate instrumentation precedes ORIGINAL half-open support rejection.
    // Do not signal unrelated conservative quad coverage far outside the patch.
    const vec2 lie_slack=vec2(0.005);
    bool lie_near_support=all(greaterThanEqual(capture_cell,patch_cells.xy-lie_slack)) &&
                          all(lessThan(capture_cell,patch_cells.zw+lie_slack));
    if(lie_near_support) {
        vec2 edge_dist=min(abs(capture_cell-patch_cells.xy),abs(capture_cell-patch_cells.zw));
        if(any(lessThan(edge_dist,lie_slack)))lie_risk_mark(0u);
        vec2 cell_dist=abs(capture_cell-round(capture_cell));
        if(any(lessThan(cell_dist,lie_slack)))lie_risk_mark(1u);
    }
    if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;''','native GLSL half-open')
    gd=renderer.read_text()
    for old,new in RENDERER_MARKERS.items():
        gd=replace_once(gd,old,new,'native Godot renderer')
    script=test.read_text()
    marker='    var image := Image.create_from_data(data["output_size"]'
    script=replace_once(script,marker,'''    if label.ends_with("-native") and native.has("lie_candidate_risk"):
        var risk: PackedByteArray = native["lie_candidate_risk"]
        if risk.size() != 3*ceili(float(data["output_size"]*data["output_size"])/32.)*4:
            printerr("LIE candidate risk packet length mismatch"); quit(1); return
        var risk_file := FileAccess.open(prefix+"-candidate-risk.bin",FileAccess.WRITE)
        risk_file.store_buffer(risk); risk_file.close()
''' + marker,'native Godot capture script')
    shader.write_text(modified)
    renderer.write_text(gd)
    test.write_text(script)
    return {'schema':'lie-stream-candidate-probe-staging/1',
            'signals':['near-patch-before-discard','near-source-grid','near-proxy-entry-face-tie'],
            'packed_bytes':'3 * ceil(width*height/32) * 4',
            'staged_shader':str(shader),'staged_renderer':str(renderer),'staged_test':str(test),
            'limits':['Triangles with no conservative raster coverage cannot signal',
                      'Atomics may be expensive on mobile hardware',
                      'No depth/owner/normal/material correction is performed']}
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage',type=Path,required=True)
    args=p.parse_args()
    root=args.stage
    report=instrument(root/'shaders'/'lie_direct_native.glsl',root/'lie_direct_renderer.gd',root/'test_lie_native_depth.gd')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
