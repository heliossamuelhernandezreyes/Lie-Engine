#[vertex]
#version 450

struct Proxy {mat4 world;mat4 local;vec4 lo;vec4 hi;vec4 material;uvec4 meta;};
struct View {vec4 eye;vec4 right;vec4 up;vec4 forward;vec4 lens;};
layout(set=0,binding=0,std430) readonly buffer Proxies {Proxy p[];} proxies;
layout(set=0,binding=1,std430) readonly buffer Views {View v[];} views;
layout(push_constant,std430) uniform Push {ivec4 value;} push;
vec4 clip_point(vec3 p,View v) {
    vec3 d=p-v.eye.xyz;float z=dot(d,v.forward.xyz),n=v.lens.x,f=v.lens.y;
    return vec4(dot(d,v.right.xyz)/v.lens.z,-dot(d,v.up.xyz)/v.lens.z,n*(f-z)/(f-n),z);
}

layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
struct Quad {vec4 rect;vec4 depth;uvec4 meta;};
layout(set=0,binding=8,std430) readonly buffer Mesh {Quad q[];} mesh;
layout(location=0) flat out uint proxy_id;
layout(location=1) flat out uvec2 face_layer;
layout(location=2) flat out vec4 patch_cells;
layout(location=3) flat out float plane_coord;
void main(){
    const int corners[6]=int[6](0,1,2,0,2,3);
    const vec2 uv[4]=vec2[4](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,1));
    Quad q=mesh.q[uint(push.value.y)+uint(gl_VertexIndex/6)];
    proxy_id=uint(gl_InstanceIndex+push.value.z);Proxy p=proxies.p[proxy_id];
    face_layer=q.meta.xy;patch_cells=q.rect;
    int axis=(int(q.meta.x)%6)/2;
    ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    ivec4 rect=faces.rect[q.meta.x];View v=views.v[push.value.x];
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    bool outside=any(lessThan(eye,p.lo.xyz))||any(greaterThan(eye,p.hi.xyz));
    if(outside&&((q.meta.x%2u==0u)?eye[axis]<=p.hi[axis]:eye[axis]>=p.lo[axis])){
        gl_Position=vec4(0,0,0,1);return;
    }
    plane_coord=(q.meta.x%2u==0u)?p.hi[axis]-q.depth.x:p.lo[axis]+q.depth.x;
    vec2 low=vec2(1e30),high=vec2(-1e30);int behind=0;
    for(int k=0;k<4;k++){
        vec2 cell=mix(q.rect.xy,q.rect.zw,uv[k]);vec3 point=p.lo.xyz;
        point[axes.x]=mix(p.lo[axes.x],p.hi[axes.x],cell.x/float(rect.z));
        point[axes.y]=mix(p.lo[axes.y],p.hi[axes.y],cell.y/float(rect.w));
        point[axis]=plane_coord;
        vec4 clip=clip_point((p.world*vec4(point,1)).xyz,v);
        if(clip.w<=v.lens.x)behind++;
        else{vec2 screen=clip.xy/clip.w;low=min(low,screen);high=max(high,screen);}
    }
    if(behind==4){gl_Position=vec4(0,0,0,1);return;}
    if(behind>0){low=vec2(-1);high=vec2(1);}
    // Conservative screen coverage only. The fragment tests the ORIGINAL
    // half-open cell rectangle and exact plane; no hole is filled.
    vec2 margin=vec2(2./float(push.value.w));
    low=max(low-margin,vec2(-1));high=min(high+margin,vec2(1));
    if(any(greaterThan(low,high))){gl_Position=vec4(0,0,0,1);return;}
    gl_Position=vec4(mix(low,high,uv[corners[gl_VertexIndex%6]]),.5,1);
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
    return vec4(dot(d,v.right.xyz)/v.lens.z,-dot(d,v.up.xyz)/v.lens.z,n*(f-z)/(f-n),z);
}

layout(set=0,binding=2) uniform sampler2D depth_field;
layout(set=0,binding=3) uniform sampler2DArray normal_field;
layout(set=0,binding=4) uniform sampler2DArray color_field;
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
layout(location=0) flat in uint proxy_id;
layout(location=1) flat in uvec2 face_layer;
layout(location=2) flat in vec4 patch_cells;
layout(location=3) flat in float plane_coord;
layout(location=0) out vec4 out_world;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_color;

void main(){
    Proxy p=proxies.p[proxy_id];View v=views.v[push.value.x];
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    vec2 screen=gl_FragCoord.xy*(2./float(push.value.w))-1.;
    vec3 world_ray=v.forward.xyz+(v.right.xyz*screen.x-v.up.xyz*screen.y)*v.lens.z;
    vec3 ray=mat3(p.local)*world_ray;
    vec3 safe=sign(ray)*max(abs(ray),vec3(1e-12));
    for(int k=0;k<3;k++)if(abs(safe[k])<1e-12)safe[k]=1e-12;
    vec3 nearv=min((p.lo.xyz-eye)/safe,(p.hi.xyz-eye)/safe);
    int axis=nearv.x>=nearv.y&&nearv.x>=nearv.z?0:nearv.y>=nearv.z?1:2;
    int face=axis*2+(ray[axis]>0.?1:0);
    if(face!=int(face_layer.x-p.meta.x))discard;
    ivec4 rect=faces.rect[face_layer.x];
    float t=(plane_coord-eye[axis])/ray[axis];if(t<=0.)discard;
    vec3 local_point=eye+ray*t;
    ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    vec2 capture_cell=(vec2(local_point[axes.x],local_point[axes.y])-vec2(p.lo[axes.x],p.lo[axes.y]))
        /vec2(p.hi[axes.x]-p.lo[axes.x],p.hi[axes.y]-p.lo[axes.y])*vec2(rect.zw);
    if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;
    ivec2 cell=clamp(ivec2(floor(capture_cell)),ivec2(0),rect.zw-1)+rect.xy;
    int layer=int(face_layer.y);
    if(texelFetch(depth_field,cell,0)[layer]<0.)discard;
    vec4 n=texelFetch(normal_field,ivec3(cell,layer),0);
    vec4 c=texelFetch(color_field,ivec3(cell,layer),0);
    vec3 world_point=v.eye.xyz+world_ray*t;
    float z=dot(world_point-v.eye.xyz,v.forward.xyz),near=v.lens.x,far=v.lens.y;
    if(z<=near||z>=far)discard;
    gl_FragDepth=near*(far-z)/((far-near)*z);
    out_world=vec4(world_point,n.w+p.material.z+1.);
    out_normal=vec4(normalize(transpose(mat3(p.local))*n.xyz),clamp(c.a+p.material.y,.2,.95));
    out_color=vec4(clamp(c.rgb*p.material.x,vec3(0),vec3(1)),1.);
}
