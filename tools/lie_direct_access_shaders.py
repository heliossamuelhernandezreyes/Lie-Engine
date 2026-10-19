"""Build executable region-skip and native-depth capture-envelope consumers."""
from pathlib import Path
import lie_direct_shaders as base
ROOT=Path(__file__).resolve().parents[1]/'gpu_compute/shaders'

REGION_BINDINGS='''
layout(set=0,binding=6) uniform sampler2D region_field;
layout(set=0,binding=7,std430) readonly buffer Regions {ivec4 rect[];} regions;
'''
REGION_SKIP='''
        // Bounds include every occupied cell/layer, including partial tiles.
        // A disjoint ray interval can skip the entire 8-cell region exactly.
        ivec2 block=cell/8;ivec4 bounds_rect=regions.rect[int(p.meta.x)+face];
        vec4 bounds=texelFetch(region_field,block+bounds_rect.xy,0);
        vec2 block_edge=origin+vec2(min((block+ivec2(greaterThanEqual(r,vec2(0.))))*8,rect.zw))*cellsize;
        vec2 next_block=vec2(1e30);
        for(int k=0;k<2;k++)if(abs(r[k])>1e-12)next_block[k]=(block_edge[k]-uv[k])/r[k]+t;
        float block_stop=min(end,min(next_block.x,next_block.y));
        float depth_a=(face%2==0)?p.hi[axis]-pos[axis]:pos[axis]-p.lo[axis];
        float end_coord=eye[axis]+ray[axis]*block_stop;
        float depth_b=(face%2==0)?p.hi[axis]-end_coord:end_coord-p.lo[axis];
        if(bounds.z<.5||max(depth_a,depth_b)<bounds.x-2e-6||min(depth_a,depth_b)>bounds.y+2e-6){
            t=max(block_stop+1e-6,t+1e-6);continue;
        }
'''

ENVELOPE_VERTEX='''
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
struct Quad {vec4 rect;vec4 depth;uvec4 meta;};
layout(set=0,binding=8,std430) readonly buffer Mesh {Quad q[];} mesh;
layout(location=0) out vec3 world_point;
layout(location=1) out vec2 capture_cell;
layout(location=2) flat out uint proxy_id;
layout(location=3) flat out uvec2 face_layer;
void main(){
    const int corners[6]=int[6](0,1,2,0,2,3);
    const vec2 uv[4]=vec2[4](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,1));
    Quad q=mesh.q[uint(push.value.y)+uint(gl_VertexIndex/6)];
    int corner=corners[gl_VertexIndex%6];int face=int(q.meta.x)%6,axis=face/2;
    ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    proxy_id=uint(gl_InstanceIndex+push.value.z);Proxy p=proxies.p[proxy_id];
    ivec4 rect=faces.rect[q.meta.x];
    capture_cell=mix(q.rect.xy,q.rect.zw,uv[corner]);
    vec3 point=p.lo.xyz;
    point[axes.x]=mix(p.lo[axes.x],p.hi[axes.x],capture_cell.x/float(rect.z));
    point[axes.y]=mix(p.lo[axes.y],p.hi[axes.y],capture_cell.y/float(rect.w));
    point[axis]=(face%2==0)?p.hi[axis]-(corner==0?q.depth.x:corner==1?q.depth.y:corner==2?q.depth.z:q.depth.w):p.lo[axis]+(corner==0?q.depth.x:corner==1?q.depth.y:corner==2?q.depth.z:q.depth.w);
    world_point=(p.world*vec4(point,1)).xyz;face_layer=q.meta.xy;
    View v=views.v[push.value.x];gl_Position=clip_point(world_point,v);
    // Cull the opposite directional sheet before rasterization. All six
    // vertices of a quad use the same decision; no per-pixel depth search.
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    float middle=(face%2==0)?p.hi[axis]-dot(q.depth,vec4(.25)):p.lo[axis]+dot(q.depth,vec4(.25));
    if((eye[axis]-middle)*(face%2==0?1.:-1.)<=0.)gl_Position=vec4(0,0,0,1);
}
'''
ENVELOPE_FRAGMENT='''
layout(set=0,binding=2) uniform sampler2D depth_field;
layout(set=0,binding=3) uniform sampler2DArray normal_field;
layout(set=0,binding=4) uniform sampler2DArray color_field;
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
layout(location=0) in vec3 world_point;
layout(location=1) in vec2 capture_cell;
layout(location=2) flat in uint proxy_id;
layout(location=3) flat in uvec2 face_layer;
ENVELOPE_OUTPUTS
void main(){
    ivec4 rect=faces.rect[face_layer.x];ivec2 cell=clamp(ivec2(floor(capture_cell)),ivec2(0),rect.zw-1)+rect.xy;
    if(texelFetch(depth_field,cell,0).r<0.)discard;
    Proxy p=proxies.p[proxy_id];
    vec4 n=texelFetch(normal_field,ivec3(cell,int(face_layer.y)),0);
    vec4 c=texelFetch(color_field,ivec3(cell,int(face_layer.y)),0);
    ENVELOPE_OUTPUT
}
'''

OUTPUTS='''layout(location=0) out vec4 out_world;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_color;
'''

def build():
    base.build()
    vertex='#[vertex]\n#version 450\n'+base.COMMON+base.VERTEX
    fragment=base.FRAGMENT.replace('layout(location=0) in vec3 proxy_point;',REGION_BINDINGS+'\nlayout(location=0) in vec3 proxy_point;')
    fragment=fragment.replace('        vec2 edge=origin+',REGION_SKIP+'        vec2 edge=origin+')
    fragment='#[fragment]\n#version 450\n'+base.COMMON+fragment
    body='''out_world=vec4(world,n.w+p.material.z+1.);
    out_normal=vec4(normalize(transpose(mat3(p.local))*n.xyz),clamp(c.a+p.material.y,.2,.95));
    out_color=vec4(clamp(c.rgb*p.material.x,vec3(0),vec3(1)),1.);'''
    (ROOT/'lie_direct_regions.glsl').write_text(vertex+'\n'+fragment+OUTPUTS+base.MAIN.replace('SURFACE_OUTPUT',body))
    (ROOT/'lie_direct_regions_shadow.glsl').write_text(vertex+'\n'+fragment+base.MAIN.replace('    SURFACE_OUTPUT',''))
    vertex='#[vertex]\n#version 450\n'+base.COMMON+ENVELOPE_VERTEX
    fragment='#[fragment]\n#version 450\n'+base.COMMON+ENVELOPE_FRAGMENT
    (ROOT/'lie_direct_envelope.glsl').write_text(vertex+'\n'+fragment.replace('ENVELOPE_OUTPUTS',OUTPUTS).replace('ENVELOPE_OUTPUT',body.replace('vec4(world,','vec4(world_point,')))
    (ROOT/'lie_direct_envelope_shadow.glsl').write_text(vertex+'\n'+fragment.replace('ENVELOPE_OUTPUTS','').replace('ENVELOPE_OUTPUT',''))

if __name__=='__main__':build()
