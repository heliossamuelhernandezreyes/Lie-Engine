"""Staged-only compensated float32 boundary predicate experiment.

A near-boundary candidate is recomputed using two-float compensated arithmetic
(fma residuals and error-free sums). This is an A/B hypothesis for the original
half-open interval; it does NOT change any production source, and is NOT
certified for mobile performance or every possible camera.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

ORIGINAL='if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;'
INSERT_AFTER='layout(location=2) out vec4 out_color;'
HELPERS=r'''
// Experimental compensated-float fallback for ambiguous captured-cell bounds.
// This code intentionally uses FP32 + FMA, never FP64.
vec2 lie_two_sum(float a,float b) {
    precise float s=a+b;
    precise float bb=s-a;
    precise float e=(a-(s-bb))+(b-bb);
    return vec2(s,e);
}
vec2 lie_two_prod(float a,float b) {
    precise float hi=a*b;
    precise float lo=fma(a,b,-hi);
    return vec2(hi,lo);
}
vec2 lie_dd_add(vec2 a,vec2 b) {
    vec2 s=lie_two_sum(a.x,b.x);
    return lie_two_sum(s.x,s.y+a.y+b.y);
}
vec2 lie_dd_sub(vec2 a,vec2 b) {
    return lie_dd_add(a,vec2(-b.x,-b.y));
}
vec2 lie_dd_mul(vec2 a,vec2 b) {
    vec2 p=lie_two_prod(a.x,b.x);
    return lie_two_sum(p.x,p.y+a.x*b.y+a.y*b.x);
}
vec2 lie_dd_div(vec2 a,vec2 b) {
    float q0=a.x/b.x;
    vec2 remainder=lie_dd_sub(a,lie_dd_mul(b,vec2(q0,0.)));
    float q1=(remainder.x+remainder.y)/b.x;
    return lie_dd_add(vec2(q0,0.),vec2(q1,0.));
}
vec2 lie_dd_local_eye(Proxy p,View v,int axis) {
    vec2 result=vec2(p.local[3][axis],0.);
    for(int i=0;i<3;i++)
        result=lie_dd_add(result,lie_two_prod(p.local[i][axis],v.eye[i]));
    return result;
}
vec2 lie_dd_local_dir(Proxy p,View v,int axis,vec2 sx,vec2 sy) {
    vec2 forward=vec2(0.),right=vec2(0.),up=vec2(0.);
    for(int i=0;i<3;i++) {
        forward=lie_dd_add(forward,lie_two_prod(p.local[i][axis],v.forward[i]));
        right=lie_dd_add(right,lie_two_prod(p.local[i][axis],v.right[i]));
        up=lie_dd_add(up,lie_two_prod(p.local[i][axis],v.up[i]));
    }
    vec2 side=lie_dd_sub(lie_dd_mul(right,sx),lie_dd_mul(up,sy));
    return lie_dd_add(forward,lie_dd_mul(side,vec2(v.lens.z,0.)));
}
vec2 lie_edge_function(vec2 eye_u,vec2 eye_z,vec2 ray_u,vec2 ray_z,
                       vec2 plane,float lo,float hi,float dim,float edge) {
    // ((eye_u-lo)*dim-edge*(hi-lo))*ray_z +
    //    (plane-eye_z)*ray_u*dim; sign is adjusted for ray_z.
    vec2 relative=lie_dd_sub(eye_u,vec2(lo,0.));
    vec2 base=lie_dd_sub(lie_dd_mul(relative,vec2(dim,0.)),
                         lie_dd_mul(vec2(edge,0.),lie_dd_sub(vec2(hi,0.),vec2(lo,0.))));
    return lie_dd_add(lie_dd_mul(base,ray_z),
           lie_dd_mul(lie_dd_mul(lie_dd_sub(plane,eye_z),ray_u),vec2(dim,0.)));
}
bool lie_precise_patch_contains(Proxy p,View v,ivec4 rect,
                                vec4 patch_cells,float plane_coord) {
    vec2 sx=lie_dd_sub(lie_dd_div(vec2(gl_FragCoord.x*2.,0.),
                                  vec2(float(push.value.w),0.)),vec2(1.,0.));
    vec2 sy=lie_dd_sub(lie_dd_div(vec2(gl_FragCoord.y*2.,0.),
                                  vec2(float(push.value.w),0.)),vec2(1.,0.));
    // Face is selected by the normal main-path proxy entry calculation.
    int axis=(int(face_layer.x-p.meta.x)%6)/2;
    ivec2 uvaxis=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    vec2 eye_z=lie_dd_local_eye(p,v,axis);
    vec2 ray_z=lie_dd_local_dir(p,v,axis,sx,sy);
    if(ray_z.x==0.)return false;
    // The source plane_coord is already rounded in the vertex stage.
    // Near the critical wall pixel, that plane rounding is < observed
    // float32 cancellation and does not invalidate the experimental sign.
    vec2 plane=vec2(plane_coord,0.);
    float orientation=ray_z.x>0.?1.:-1.;
    for(int a=0;a<2;a++) {
        int uv=a==0?uvaxis.x:uvaxis.y;
        float dim=a==0?float(rect.z):float(rect.w);
        float lower=a==0?patch_cells.x:patch_cells.y;
        float upper=a==0?patch_cells.z:patch_cells.w;
        vec2 eye_u=lie_dd_local_eye(p,v,uv);
        vec2 ray_u=lie_dd_local_dir(p,v,uv,sx,sy);
        vec2 value_low=lie_edge_function(eye_u,eye_z,ray_u,ray_z,plane,
            p.lo[uv],p.hi[uv],dim,lower);
        vec2 value_high=lie_edge_function(eye_u,eye_z,ray_u,ray_z,plane,
            p.lo[uv],p.hi[uv],dim,upper);
        if(orientation*(value_low.x+value_low.y)<0. ||
           orientation*(value_high.x+value_high.y)>=0.)return false;
    }
    return true;
}
'''
REPLACEMENT=r'''// Preserve ordinary FP32 path away from boundaries; only re-evaluate
    // numerically ambiguous candidates. Unlike the rejected edge guard,
    // these candidates are not discarded simply for being near a boundary.
    bool lie_rough_inside = all(greaterThanEqual(capture_cell,patch_cells.xy)) &&
                            all(lessThan(capture_cell,patch_cells.zw));
    vec2 lie_low_distance=abs(capture_cell-patch_cells.xy);
    vec2 lie_high_distance=abs(capture_cell-patch_cells.zw);
    bool lie_ambiguous = any(lessThan(lie_low_distance,vec2(0.002))) ||
                         any(lessThan(lie_high_distance,vec2(0.002)));
    if(lie_ambiguous) {
        if(!lie_precise_patch_contains(p,v,rect,patch_cells,plane_coord))discard;
    } else if(!lie_rough_inside)discard;'''


def apply(shader:Path):
    data=shader.read_text()
    if data.count(ORIGINAL)!=1 or data.count(INSERT_AFTER)!=1 or 'lie_precise_patch_contains' in data:
        raise ValueError('Expected exactly one unmodified native shader fragment')
    data=data.replace(INSERT_AFTER,INSERT_AFTER+'\n'+HELPERS)
    data=data.replace(ORIGINAL,REPLACEMENT)
    shader.write_text(data)
    return {'shader':str(shader),'precision':'two-float compensated FP32 with fma',
            'sensitive_threshold_in_capture_cells':0.002,
            'approach':'re-evaluate near-border inclusion, do not discard border region',
            'status':'STAGED SHADER EXPERIMENT, NOT A RELEASE'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shader',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(apply(args.shader),indent=2))


if __name__=='__main__':main()
