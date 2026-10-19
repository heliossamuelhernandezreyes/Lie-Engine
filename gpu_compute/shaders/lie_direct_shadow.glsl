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

layout(location=0) out vec3 proxy_point;
layout(location=1) flat out uint proxy_id;
layout(location=2) flat out int proxy_face;
void main(){
    const ivec2 corners[6]=ivec2[6](ivec2(0,0),ivec2(1,0),ivec2(1,1),ivec2(0,0),ivec2(1,1),ivec2(0,1));
    Proxy p=proxies.p[gl_InstanceIndex];int face=gl_VertexIndex/6,axis=face/2;
    ivec2 uvaxis=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    vec3 q=p.lo.xyz;ivec2 c=corners[gl_VertexIndex%6];
    q[axis]=(face%2==0)?p.hi[axis]:p.lo[axis];
    q[uvaxis.x]=mix(p.lo[uvaxis.x],p.hi[uvaxis.x],float(c.x));
    q[uvaxis.y]=mix(p.lo[uvaxis.y],p.hi[uvaxis.y],float(c.y));
    proxy_point=q;proxy_id=uint(gl_InstanceIndex);proxy_face=face;
    gl_Position=clip_point((p.world*vec4(q,1)).xyz,views.v[push.value.x]);
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
layout(location=0) in vec3 proxy_point;
layout(location=1) flat in uint proxy_id;
layout(location=2) flat in int proxy_face;
// Conservative local cell traversal. Empty capture cells are never box faces.
// Four layers and a finite cell limit are explicit representation limits.
bool surface_hit(Proxy p,vec3 eye,vec3 ray,out vec3 hit,out vec4 normal,out vec4 color){
    vec3 safe=sign(ray)*max(abs(ray),vec3(1e-12));
    for(int k=0;k<3;k++)if(abs(safe[k])<1e-12)safe[k]=1e-12;
    vec3 ta=(p.lo.xyz-eye)/safe,tb=(p.hi.xyz-eye)/safe;
    vec3 nearv=min(ta,tb),farv=max(ta,tb);
    float start=max(max(nearv.x,nearv.y),nearv.z),end=min(min(farv.x,farv.y),farv.z);
    if(end<max(start,0.))return false;
    int axis=nearv.x>=nearv.y&&nearv.x>=nearv.z?0:nearv.y>=nearv.z?1:2;
    int face=axis*2+(ray[axis]>0.?1:0);
    if(face!=proxy_face)return false;
    ivec2 uvaxis=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    ivec4 rect=faces.rect[int(p.meta.x)+face];
    vec2 cellsize=vec2(p.hi[uvaxis.x]-p.lo[uvaxis.x],p.hi[uvaxis.y]-p.lo[uvaxis.y])/vec2(rect.zw);
    vec2 origin=vec2(p.lo[uvaxis.x],p.lo[uvaxis.y]);
    vec2 r=vec2(ray[uvaxis.x],ray[uvaxis.y]);
    // Rebase at the box entry: tiny cell steps must not be added to a
    // multi-metre eye distance, where float32 rounding can stop traversal.
    float entry=max(start,0.);eye+=ray*entry;end-=entry;
    float t=1e-6;
    for(int iteration=0;iteration<256;iteration++){
        if(t>end+1e-6)break;
        vec3 pos=eye+ray*t;vec2 uv=vec2(pos[uvaxis.x],pos[uvaxis.y]);
        ivec2 cell=clamp(ivec2(floor((uv-origin)/cellsize)),ivec2(0),rect.zw-1);
        vec2 edge=origin+(vec2(cell)+step(vec2(0.),r))*cellsize;
        vec2 next=vec2(1e30);
        for(int k=0;k<2;k++)if(abs(r[k])>1e-12)next[k]=(edge[k]-uv[k])/r[k]+t;
        float stop=min(end,min(next.x,next.y));
        vec4 depths=texelFetch(depth_field,cell+rect.xy,0);
        float best=1e30;int layer=-1;
        for(int k=0;k<4;k++){
            if(depths[k]<0.)continue;
            float coord=(face%2==0)?p.hi[axis]-depths[k]:p.lo[axis]+depths[k];
            float candidate=(coord-eye[axis])/ray[axis];
            if(candidate>=t-1e-6&&candidate<=stop+1e-6&&candidate<best){best=candidate;layer=k;}
        }
        if(layer>=0){
            hit=eye+ray*best;
            normal=texelFetch(normal_field,ivec3(cell+rect.xy,layer),0);
            color=texelFetch(color_field,ivec3(cell+rect.xy,layer),0);
            return true;
        }
        t=max(stop+1e-6,t+1e-6);
    }
    return false;
}

void main(){
    Proxy p=proxies.p[proxy_id];View v=views.v[push.value.x];
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    vec3 hit;vec4 n,c;if(!surface_hit(p,eye,normalize(proxy_point-eye),hit,n,c))discard;
    vec3 world=(p.world*vec4(hit,1)).xyz;
    vec4 clip=clip_point(world,v);float depth=clip.z/clip.w;
    if(depth<0.||depth>1.)discard;gl_FragDepth=depth;

}
