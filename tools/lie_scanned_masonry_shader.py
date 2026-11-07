"""Isolated entries for the existing captured GGX consumer, no source mesh draw."""
import json
from pathlib import Path
from lie_brick_reference_shader import dedicated
ROOT=Path(__file__).resolve().parents[1]
def outputs():
    source=(ROOT/'gpu_compute/shaders/lie30_masonry.glsl').read_text()
    # Large authored roof/floor surfaces need their full projected support.
    # No image dilation: every pixel still passes source-face clipping/depth.
    source=source.replace('clamp(sqrt(max(xx,yy)),.5,8)','clamp(sqrt(max(xx,yy)),.5,64)')
    # Exact half-source clipping is independent of per-sample support radius.
    anchor='    vec3 n=abs(s.normal_gray.xyz);'
    assert source.count(anchor)==1
    source=source.replace(anchor,'''    if(inst.meta.z>0. && local.x>inst.meta.w+1e-7)return false;
    if(inst.meta.z<0. && local.x<inst.meta.w-1e-7)return false;
'''+anchor)
    # Same full projected disk and authored face clipping as the accepted
    # independent-brick shadow correction; no fixed 3x3 sparse shadow holes.
    old='for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {'
    new='''float offset_ratio=max(abs(dot(ld,parameters.shadow_right.xyz)),abs(dot(ld,parameters.shadow_up.xyz)))/lz;
                int shadow_bound=min(SHADOW_SIZE,int(ceil(radius*(1.+offset_ratio)*float(SHADOW_SIZE)/(2.*1.25*max(lz-radius,1e-6)))+1.));
                for(int y=-shadow_bound;y<=shadow_bound;y++)for(int x=-shadow_bound;x<=shadow_bound;x++) {'''
    assert source.count(old)==1;source=source.replace(old,new)
    old='if(z>.00001 && length('
    new='''vec3 local_hit=inverse(basis)*(parameters.light.xyz+ray*z-inst.origin.xyz);
                    vec3 axis=abs(s.normal_gray.xyz);vec2 support_point=axis.x>=axis.y && axis.x>=axis.z?local_hit.zy:axis.y>=axis.z?local_hit.xz:local_hit.xy;
                    bool face_support=all(greaterThanEqual(support_point,s.support.xy-vec2(.000002))) && all(lessThanEqual(support_point,s.support.zw+vec2(.000002)));
                    bool cut_support=(inst.meta.z==0.) || (inst.meta.z>0.?local_hit.x<=inst.meta.w+1e-7:local_hit.x>=inst.meta.w-1e-7);
                    if(face_support && cut_support && z>.00001 && length('''
    assert source.count(old)==1;source=source.replace(old,new)
    result={};bindings={};gd='extends RefCounted\n## Generated from the existing opaque GGX captured consumer.\nconst SHADERS={\n'
    for stage in (1,2,3,4,6,7):
        shader,bindings[stage]=dedicated(stage,source)
        name=f'shaders/lie_scanned_masonry_stage_{stage}.glsl';result['gpu_compute/'+name]=shader;gd+=f'    {stage}:preload("res://{name}"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':')).replace('"','')+'\n'
    result['gpu_compute/lie_scanned_masonry_kernels.gd']=gd;return result
if __name__=='__main__':
    for path,value in outputs().items():(ROOT/path).write_text(value)
