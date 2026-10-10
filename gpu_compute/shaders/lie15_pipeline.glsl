#[compute]
#version 450
// Shared object-local samples -> current camera plane, with real sample depth.
// Captured source geometry is never drawn. Direct light uses per-pixel normals.
layout(local_size_x=64,local_size_y=1) in;
struct Task { vec4 job; vec4 span; };
struct Sample { vec4 point_gray; vec4 normal_node; };
struct Patch { vec4 center_area; vec4 normal_gray; vec4 filter_absorption; };
struct Light { vec4 position_radius; vec4 power; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample values[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Tasks { Task values[]; } tasks;
layout(set=0,binding=2,std430) readonly buffer Camera {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 dims;
} camera;
layout(set=0,binding=3,std430) buffer Projected { vec4 values[]; } projected;
layout(set=0,binding=4,std430) buffer Depths { uint values[]; } depths;
layout(set=0,binding=5,std430) buffer Sums { uvec4 values[]; } sums;
layout(set=0,binding=6,std430) buffer Owners { uint values[]; } owners;
layout(rgba32f,set=0,binding=7) uniform writeonly image2D target_image;
layout(rgba32f,set=0,binding=11) uniform readonly image2D irradiance;
layout(set=0,binding=12,std430) readonly buffer Patches { Patch values[]; } patches;
layout(rgba32f,set=0,binding=15) uniform readonly image2D direct_irradiance;
layout(set=0,binding=16,std430) readonly buffer Probes { uvec4 values[]; } probes;
layout(set=0,binding=17,std430) buffer ProbeOutput { vec4 values[]; } probe_output;
layout(set=0,binding=18,std430) readonly buffer Lights { Light values[]; } lights;
layout(set=0,binding=19,std430) readonly buffer Caps { float values[]; } caps;
layout(set=0,binding=20,std430) buffer Counters { uint values[]; } counters;
layout(push_constant,std430) uniform Phase { ivec4 data; } phase;
const float PI=3.141592653589793;
const float FIXED_SCALE=8192.0;


struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 shape; vec4 material; vec4 pbr; };
layout(set=0,binding=14,std430) readonly buffer Instances { Instance values[]; } instances;
vec3 local_point(vec3 p, Instance s) {
    vec3 q=p-s.origin.xyz;
    return vec3(dot(q,s.x.xyz)/dot(s.x.xyz,s.x.xyz),dot(q,s.y.xyz)/dot(s.y.xyz,s.y.xyz),dot(q,s.z.xyz)/dot(s.z.xyz,s.z.xyz));
}
vec3 world_point(vec3 p, Instance s) { return s.origin.xyz+s.x.xyz*p.x+s.y.xyz*p.y+s.z.xyz*p.z; }
vec3 world_normal(vec3 n, Instance s) {
    return normalize(s.x.xyz*n.x/dot(s.x.xyz,s.x.xyz)+s.y.xyz*n.y/dot(s.y.xyz,s.y.xyz)+s.z.xyz*n.z/dot(s.z.xyz,s.z.xyz));
}
bool box_hit(vec3 a,vec3 b,Instance s) {
    if(s.pbr.w<.5) return false;
    vec3 p=local_point(a,s),d=local_point(b,s)-p;
    float lo=.001,hi=.999;
    for(int axis=0;axis<3;axis++) {
        if(abs(d[axis])<1e-10) { if(abs(p[axis])>s.shape[axis]-1e-5) return false; }
        else {
            float u=(-s.shape[axis]+1e-5-p[axis])/d[axis],v=(s.shape[axis]-1e-5-p[axis])/d[axis];
            lo=max(lo,min(u,v)); hi=min(hi,max(u,v));
        }
    }
    return lo<=hi;
}
bool rigid_blocked(vec3 a,vec3 b,int skip) {
    for(int k=0;k<15;k++) if(k!=skip && box_hit(a,b,instances.values[k])) return true;
    return false;
}

// Isotropic Trowbridge-Reitz (GGX), Smith masking and RGB Schlick Fresnel.
// Bounded artist RGB parameters; no spectral conductor or specular GI claim.
float smith_lambda(float cosine,float a2) {
    return .5*(sqrt(1.0+a2*max(1.0-cosine*cosine,0.0)/max(cosine*cosine,1e-8))-1.0);
}
vec3 direct_at(vec3 p,vec3 n,vec3 base,Instance instance,out vec3 specular) {
    vec3 result=vec3(0),v=normalize(camera.eye.xyz-p);
    float nv=max(dot(n,v),1e-5),alpha=max(instance.pbr.x*instance.pbr.x,.02),a2=alpha*alpha;
    vec3 f0=mix(vec3(.04),base,instance.pbr.y);
    specular=vec3(0);
    for(int l=0;l<camera.dims.z;l++) {
        Light source=lights.values[l]; vec3 delta=source.position_radius.xyz-p;
        float d2=dot(delta,delta),radius=source.position_radius.w;
        if(d2<1e-10 || radius<=0.0) continue;
        vec3 wi=delta*inversesqrt(d2);
        float nl=max(dot(n,wi),0.0);
        if(nl<=0.0 || rigid_blocked(p+n*.003,source.position_radius.xyz,instance.pbr.w>.5?int(instance.shape.w)/6:-1)) continue;
        float window=pow(max(0.0,1.0-pow(sqrt(d2)/radius,4.0)),2.0);
        vec3 li=source.power.rgb*window/(4.0*PI*max(d2,.0025)*max(caps.values[l],1.0));
        result+=li*nl;
        vec3 h=normalize(v+wi); float nh=max(dot(n,h),0.0),vh=max(dot(v,h),0.0);
        float denom=nh*nh*(a2-1.0)+1.0;
        float D=a2/(PI*denom*denom);
        float G=1.0/(1.0+smith_lambda(nv,a2)+smith_lambda(nl,a2));
        vec3 F=f0+(vec3(1)-f0)*pow(1.0-vh,5.0);
        if(dot(n,v)>0.0) specular+=li*F*D*G/(4.0*nv);
    }
    return result;
}
vec3 node_indirect(int node) {
    return max(imageLoad(irradiance,ivec2(node,0)).rgb-imageLoad(direct_irradiance,ivec2(node,0)).rgb,vec3(0));
}
vec3 surface_indirect(int node,vec3 p,Instance instance) {
    if(instance.pbr.w>.5) return node_indirect(node);
    int offset=int(instance.shape.w);
    vec2 grid=clamp(vec2(p.x+1.5,offset==90?p.z+1.5:p.y+.5),vec2(0),vec2(3));
    ivec2 a=ivec2(floor(grid)),b=min(a+ivec2(1),ivec2(3)); vec2 t=fract(grid);
    vec3 low=mix(node_indirect(offset+a.y*4+a.x),node_indirect(offset+a.y*4+b.x),t.x);
    vec3 high=mix(node_indirect(offset+b.y*4+a.x),node_indirect(offset+b.y*4+b.x),t.x);
    return mix(low,high,t.y);
}
vec3 sample_light(Sample s,Instance instance,out vec3 direct_value) {
    int node=int(round(s.normal_node.w+instance.shape.w));
    vec3 p=world_point(s.point_gray.xyz,instance),n=world_normal(s.normal_node.xyz,instance);
    if(camera.dims.w==0) n=patches.values[node].normal_gray.xyz;
    vec3 base=s.point_gray.w*instance.material.rgb,specular;
    direct_value=direct_at(p,n,base,instance,specular);
    vec3 indirect=surface_indirect(node,p,instance);
    vec3 v=normalize(camera.eye.xyz-p),f0=mix(vec3(.04),base,instance.pbr.y);
    vec3 F=f0+(vec3(1)-f0)*pow(1.0-max(dot(n,v),0.0),5.0);
    vec3 diffuse=(vec3(1)-F)*(1.0-instance.pbr.y)*base*(direct_value+indirect)/PI;
    vec3 radiance=(diffuse+specular)*(1.0-instance.material.w)+base*instance.pbr.z;
    return radiance/(vec3(1)+radiance);
}
bool receiver_at(uint pixel,out Sample s,out int owner,out float depth) {
    // Flat sprite receivers are sampled by inverse projection, not sparse
    // point splats. This fills the floor/wall without inventing cylinder data.
    vec2 uv=(vec2(int(pixel)%camera.dims.x,int(pixel)/camera.dims.x)+vec2(.5))/vec2(camera.dims.xy);
    vec3 ray=camera.forward.xyz+(uv.x*2.0-1.0)*camera.lens.x*camera.lens.y*camera.right.xyz
        +(1.0-uv.y*2.0)*camera.lens.x*camera.up.xyz;
    depth=3.402823e38;
    owner=-1;
    for(int k=15;k<17;k++) {
        int axis=k==15?1:2;
        float coordinate=k==15?-1.05:-2.0;
        if(camera.eye[axis]<=coordinate || abs(ray[axis])<1e-10) continue;
        float t=(coordinate-camera.eye[axis])/ray[axis];
        vec3 p=camera.eye.xyz+t*ray;
        bool inside=abs(p.x)<=2.0 && (k==15?abs(p.z)<=2.0:(p.y>=-1.0 && p.y<=3.0));
        if(!inside || t<camera.lens.z || t>camera.lens.w || t>=depth) continue;
        depth=t;
        owner=k;
        int col=int(clamp(p.x+2.0,0.0,3.99999));
        int row=int(clamp(k==15?p.z+2.0:p.y+1.0,0.0,3.99999));
        s.point_gray=vec4(p,.7);
        s.normal_node=vec4(k==15?vec3(0,1,0):vec3(0,0,1),float(row*4+col));
    }
    return owner>=0;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint pixels=uint(camera.dims.x*camera.dims.y);
    if(phase.data.x==0) {
        if(i==0u) for(int k=0;k<4;k++) counters.values[k]=0u;
        if(i<pixels) { depths.values[i]=0x7f7fffffu; sums.values[i]=uvec4(0); owners.values[i]=0xffffffffu; }
        return;
    }
    if(phase.data.x==4) {
        if(i>=pixels) return;
        uvec4 sum=sums.values[i];
        ivec2 xy=ivec2(int(i)%camera.dims.x,int(i)/camera.dims.x);
        imageStore(target_image,xy,sum.w>0u?vec4(vec3(sum.xyz)/float(sum.w),1):vec4(0));
        return;
    }
    if(phase.data.x==6 || phase.data.x==7) {
        if(i>=pixels) return;
        Sample s;
        int owner;
        float depth;
        if(!receiver_at(i,s,owner,depth)) return;
        uint bits=floatBitsToUint(depth);
        if(phase.data.x==6) atomicMin(depths.values[i],bits);
        else if(depths.values[i]==bits) {
            vec3 e;
            vec3 color=sample_light(s,instances.values[owner],e);
            uint weight=uint(FIXED_SCALE);
            sums.values[i]=uvec4(uvec3(round(color*FIXED_SCALE)),weight);
            owners.values[i]=uint(owner);
        }
        return;
    }
    if(phase.data.x==5) {
        if(i>=uint(phase.data.w)) return;
        uvec4 probe=probes.values[i];
        Sample s=samples.values[probe.x];
        Instance instance=instances.values[probe.y];
        vec3 e;
        vec3 color=sample_light(s,instance,e);
        probe_output.values[i*2]=vec4(e,s.normal_node.w+instance.shape.w);
        probe_output.values[i*2+1]=vec4(color,1);
        return;
    }
    uint task,offset;
    if(phase.data.z==0) {
        uint stride=16384u; task=i/stride; offset=i%stride;
        if(task>=uint(phase.data.y)) return;
        if(offset>=uint(tasks.values[task].job.y)) return;
    } else {
        if(phase.data.y==0 || i>=uint(tasks.values[phase.data.y-1].span.y)) return;
        uint lo=0u,hi=uint(phase.data.y);
        while(lo+1u<hi) { uint mid=(lo+hi)/2u; if(i<uint(tasks.values[mid].span.x)) hi=mid; else lo=mid; }
        task=lo; offset=i-uint(tasks.values[task].span.x);
    }
    vec4 job=tasks.values[task].job;
    Sample s=samples.values[uint(job.x)+offset];
    Instance instance=instances.values[int(job.z)];
    if(phase.data.x==1) {
        projected.values[i]=vec4(0);
        vec3 world=world_point(s.point_gray.xyz,instance);
        vec3 normal=world_normal(s.normal_node.xyz,instance);
        vec3 delta=world-camera.eye.xyz;
        float depth=dot(delta,camera.forward.xyz);
        float front=dot(normal,normalize(camera.eye.xyz-world));
        if(depth<camera.lens.z || depth>camera.lens.w || front<=0.0) return;
        float x=dot(delta,camera.right.xyz)/(depth*camera.lens.x*camera.lens.y);
        float y=dot(delta,camera.up.xyz)/(depth*camera.lens.x);
        if(abs(x)>1.0 || abs(y)>1.0) return;
        float weight=job.w*clamp(front/.5,0.0,1.0);
        projected.values[i]=vec4((x+1.0)*.5*float(camera.dims.x),(1.0-y)*.5*float(camera.dims.y),depth,weight);
        return;
    }
    vec4 p=projected.values[i];
    if(p.w<.0001 || p.z<=0.0) return;
    uint weight=uint(round(clamp(p.w,0.0,1.0)*FIXED_SCALE));
    if(weight==0u) return;
    vec3 color=vec3(0);
    if(phase.data.x==3) {
        atomicAdd(counters.values[0],1u);
        bool survives=false;
        for(int dy=0;dy<2;dy++) for(int dx=0;dx<2;dx++) {
            ivec2 xy=ivec2(floor(p.xy))+ivec2(dx,dy);
            if(any(lessThan(xy,ivec2(0))) || any(greaterThanEqual(xy,camera.dims.xy))) continue;
            uint target=uint(xy.y*camera.dims.x+xy.x);
            if(abs(uintBitsToFloat(depths.values[target])-p.z)<.025) survives=true;
        }
        if(phase.data.z!=0 && !survives) { atomicAdd(counters.values[2],1u); return; }
        atomicAdd(counters.values[1],1u);
        vec3 e; color=sample_light(s,instance,e);
    }
    for(int dy=0;dy<2;dy++) for(int dx=0;dx<2;dx++) {
        ivec2 xy=ivec2(floor(p.xy))+ivec2(dx,dy);
        if(any(lessThan(xy,ivec2(0))) || any(greaterThanEqual(xy,camera.dims.xy))) continue;
        uint target=uint(xy.y*camera.dims.x+xy.x);
        if(phase.data.x==2) atomicMin(depths.values[target],floatBitsToUint(p.z));
        else if(phase.data.x==3 && abs(uintBitsToFloat(depths.values[target])-p.z)<.025) {
            if(floatBitsToUint(p.z)==depths.values[target]) atomicMin(owners.values[target],uint(job.z));
            uvec3 value=uvec3(round(color*float(weight)));
            atomicAdd(sums.values[target].x,value.x);
            atomicAdd(sums.values[target].y,value.y);
            atomicAdd(sums.values[target].z,value.z);
            atomicAdd(sums.values[target].w,weight);
        }
    }
}
