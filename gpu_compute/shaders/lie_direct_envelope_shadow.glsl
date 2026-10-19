#[vertex]
#version 450

struct Proxy {mat4 world;mat4 local;vec4 lo;vec4 hi;vec4 material;uvec4 meta;};
struct View {vec4 eye;vec4 right;vec4 up;vec4 forward;vec4 lens;};
layout(set=0,binding=0,std430) readonly buffer Proxies {Proxy p[];} proxies;
layout(set=0,binding=1,std430) readonly buffer Views {View v[];} views;
layout(push_constant,std430) uniform Push {ivec4 value;} push;
vec4 clip_point(vec3 p,View v) {
    vec3 d=p-v.eye.xyz;float z=dot(d,v.forward.xyz),n=v.lens.x,f=v.lens.y;
    return vec4(dot(d,v.right.xyz)/v.lens.z,-dot(d,v.up.xyz)/v.lens.z,f/(f-n)*z-f*n/(f-n),z);
}

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
    point[axis]=(face%2==0)?p.hi[axis]-q.depth[corner]:p.lo[axis]+q.depth[corner];
    world_point=(p.world*vec4(point,1)).xyz;face_layer=q.meta.xy;
    View v=views.v[push.value.x];gl_Position=clip_point(world_point,v);
    // Cull the opposite directional sheet before rasterization. All six
    // vertices of a quad use the same decision; no per-pixel depth search.
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    float middle=(face%2==0)?p.hi[axis]-dot(q.depth,vec4(.25)):p.lo[axis]+dot(q.depth,vec4(.25));
    if((eye[axis]-middle)*(face%2==0?1.:-1.)<=0.)gl_Position=vec4(0,0,0,1);
}

#[fragment]
#version 450

struct Proxy {mat4 world;mat4 local;vec4 lo;vec4 hi;vec4 material;uvec4 meta;};
struct View {vec4 eye;vec4 right;vec4 up;vec4 forward;vec4 lens;};
layout(set=0,binding=0,std430) readonly buffer Proxies {Proxy p[];} proxies;
layout(set=0,binding=1,std430) readonly buffer Views {View v[];} views;
layout(push_constant,std430) uniform Push {ivec4 value;} push;
vec4 clip_point(vec3 p,View v) {
    vec3 d=p-v.eye.xyz;float z=dot(d,v.forward.xyz),n=v.lens.x,f=v.lens.y;
    return vec4(dot(d,v.right.xyz)/v.lens.z,-dot(d,v.up.xyz)/v.lens.z,f/(f-n)*z-f*n/(f-n),z);
}

layout(set=0,binding=2) uniform sampler2D depth_field;
layout(set=0,binding=3) uniform sampler2DArray normal_field;
layout(set=0,binding=4) uniform sampler2DArray color_field;
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
layout(location=0) in vec3 world_point;
layout(location=1) in vec2 capture_cell;
layout(location=2) flat in uint proxy_id;
layout(location=3) flat in uvec2 face_layer;

void main(){
    ivec4 rect=faces.rect[face_layer.x];ivec2 cell=clamp(ivec2(floor(capture_cell)),ivec2(0),rect.zw-1)+rect.xy;
    if(texelFetch(depth_field,cell,0)[face_layer.y]<0.)discard;
    Proxy p=proxies.p[proxy_id];
    vec4 n=texelFetch(normal_field,ivec3(cell,int(face_layer.y)),0);
    vec4 c=texelFetch(color_field,ivec3(cell,int(face_layer.y)),0);
    
}
