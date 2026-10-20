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

layout(location=3) flat out ivec3 capture_ids;
layout(location=4) flat out vec3 capture_weights;
void select_captures(Proxy p,vec3 eye){
    vec3 v=eye-(p.lo.xyz+p.hi.xyz)*.5;v/=dot(abs(v),vec3(1));
    vec2 uv=v.xy;
    if(v.z<0.)uv=(vec2(1)-abs(uv.yx))*mix(vec2(-1),vec2(1),greaterThanEqual(uv,vec2(0)));
    vec2 q=clamp((uv*.5+.5)*7.,vec2(0),vec2(7));
    ivec2 b=min(ivec2(floor(q)),ivec2(6));vec2 f=q-vec2(b);
    int at=int(p.meta.x/6u)*64+b.y*8+b.x;
    if(f.x+f.y<=1.){capture_ids=ivec3(at,at+1,at+8);capture_weights=vec3(1.-f.x-f.y,f.x,f.y);}
    else {capture_ids=ivec3(at+9,at+8,at+1);capture_weights=vec3(f.x+f.y-1.,1.-f.x,1.-f.y);}
}

void main(){
    const ivec2 corners[6]=ivec2[6](ivec2(0,0),ivec2(1,0),ivec2(1,1),ivec2(0,0),ivec2(1,1),ivec2(0,1));
    Proxy p=proxies.p[gl_InstanceIndex];int face=gl_VertexIndex/6,axis=face/2;
    ivec2 uvaxis=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    vec3 q=p.lo.xyz;ivec2 c=corners[gl_VertexIndex%6];
    q[axis]=(face%2==0)?p.hi[axis]:p.lo[axis];
    q[uvaxis.x]=mix(p.lo[uvaxis.x],p.hi[uvaxis.x],float(c.x));
    q[uvaxis.y]=mix(p.lo[uvaxis.y],p.hi[uvaxis.y],float(c.y));
    proxy_point=q;proxy_id=uint(gl_InstanceIndex);proxy_face=face;
    select_captures(p,(p.local*vec4(views.v[push.value.x].eye.xyz,1)).xyz);
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

struct Capture {vec4 right;vec4 up;vec4 direction;vec4 center;ivec4 tile;};
layout(set=0,binding=9,std430) readonly buffer Captures {Capture c[];} captures;

layout(set=0,binding=2) uniform sampler2D depth_field;
layout(set=0,binding=3) uniform sampler2DArray normal_field;
layout(set=0,binding=4) uniform sampler2DArray color_field;
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
layout(set=0,binding=10) uniform usampler2D brick_views;
layout(set=0,binding=11) uniform usampler2D mortar_views;
layout(location=0) in vec3 proxy_point;
layout(location=1) flat in uint proxy_id;
layout(location=2) flat in int proxy_face;
layout(location=3) flat in ivec3 capture_ids;
layout(location=4) flat in vec3 capture_weights;
float channel(vec4 value,int layer){return layer==0?value.x:layer==1?value.y:layer==2?value.z:value.w;}
bool capture_hit(Proxy p,vec3 eye,vec3 ray,int id,float entry,float exit,
                 out vec3 hit,out vec4 n,out vec4 color){
    Capture c=captures.c[id];float denom=dot(ray,c.direction.xyz);
    if(denom>=-.02)return false;
    float origin=dot(eye-c.center.xyz,c.direction.xyz);
    float t=-origin/denom;uvec2 record=uvec2(0);
    // Exactly three depth projections, independent of source density and
    // empty distance. A failed projection does not invoke the old renderer.
    for(int correction=0;correction<3;correction++){
        vec3 point=eye+ray*t-c.center.xyz;
        vec2 uv=vec2(dot(point,c.right.xyz)/c.right.w,dot(point,c.up.xyz)/c.up.w)*.5+.5;
        if(any(lessThan(uv,vec2(0)))||any(greaterThanEqual(uv,vec2(1))))return false;
        ivec2 cell=c.tile.xy+ivec2(floor(uv*vec2(c.tile.zw)));
        record=p.meta.x==0u?texelFetch(brick_views,cell,0).rg:texelFetch(mortar_views,cell,0).rg;
        if(record.y==0u)return false;
        t=(uintBitsToFloat(record.x)-origin)/denom;
    }
    uint code=record.y-1u;int face=int((code>>21u)&15u),layer=int((code>>25u)&3u),axis=(face%6)/2;
    ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
    ivec4 rect=faces.rect[face];ivec2 cell=ivec2(int(code&1023u),int((code>>10u)&2047u));
    if(abs(ray[axis])<.02)return false;
    // Follow the baked provenance into the ORIGINAL full-resolution field.
    // Two refinements are a fixed budget, not a cell traversal or binary search.
    for(int refinement=0;refinement<2;refinement++){
        if(refinement!=0){
            vec3 point=eye+ray*t;
            vec2 uv=(vec2(point[axes.x],point[axes.y])-vec2(p.lo[axes.x],p.lo[axes.y]))/vec2(p.hi[axes.x]-p.lo[axes.x],p.hi[axes.y]-p.lo[axes.y]);
            if(any(lessThan(uv,vec2(0)))||any(greaterThanEqual(uv,vec2(1))))return false;
            cell=rect.xy+ivec2(floor(uv*vec2(rect.zw)));
        }
        float d=channel(texelFetch(depth_field,cell,0),layer);
        if(d<0.)return false;
        float coord=face%2==0?p.hi[axis]-d:p.lo[axis]+d;
        t=(coord-eye[axis])/ray[axis];
    }
    if(t<entry-1e-5||t>exit+1e-5)return false;
    n=texelFetch(normal_field,ivec3(cell,layer),0);
    if(dot(n.xyz,-ray)<.02)return false;
    color=texelFetch(color_field,ivec3(cell,layer),0);hit=eye+ray*t;
    return true;
}
bool surface_hit(Proxy p,vec3 eye,vec3 ray,out vec3 hit,out vec4 n,out vec4 color){
    vec3 safe=ray;
    for(int k=0;k<3;k++)if(abs(safe[k])<1e-12)safe[k]=1e-12;
    vec3 ta=(p.lo.xyz-eye)/safe,tb=(p.hi.xyz-eye)/safe;
    vec3 nearv=min(ta,tb),farv=max(ta,tb);
    float entry=max(max(nearv.x,nearv.y),nearv.z),exit=min(min(farv.x,farv.y),farv.z);
    if(exit<max(entry,0.))return false;
    int axis=nearv.x>=nearv.y&&nearv.x>=nearv.z?0:nearv.y>=nearv.z?1:2;
    if(proxy_face!=axis*2+(ray[axis]>0.?1:0))return false;
    // Rebase before depth refinement to avoid far-eye float32 cancellation.
    eye+=ray*max(entry,0.);exit-=max(entry,0.);
    bool found=false;float best=1e30;
    for(int candidate=0;candidate<3;candidate++){
        int id=candidate==0?capture_ids.x:candidate==1?capture_ids.y:capture_ids.z;
        vec3 point;vec4 nn,cc;
        if(!capture_hit(p,eye,ray,id,0.,exit,point,nn,cc))continue;
        float t=dot(point-eye,ray);
        if(t<best){best=t;hit=point;n=nn;color=cc;found=true;}
    }
    return found;
}
layout(location=0) out vec4 out_world;
layout(location=1) out vec4 out_normal;
layout(location=2) out vec4 out_color;

void main(){
    Proxy p=proxies.p[proxy_id];View v=views.v[push.value.x];
    vec3 eye=(p.local*vec4(v.eye.xyz,1)).xyz;
    vec3 hit;vec4 n,c;if(!surface_hit(p,eye,normalize(proxy_point-eye),hit,n,c))discard;
    vec3 world=(p.world*vec4(hit,1)).xyz;
    vec4 clip=clip_point(world,v);float depth=clip.z/clip.w;
    if(depth<0.||depth>1.)discard;gl_FragDepth=depth;
    out_world=vec4(world,n.w+p.material.z+1.);
    out_normal=vec4(normalize(transpose(mat3(p.local))*n.xyz),clamp(c.a+p.material.y,.2,.95));
    out_color=vec4(clamp(c.rgb*p.material.x,vec3(0),vec3(1)),1.);
}
