#[compute]
#version 450
// Shared object-local samples -> current camera plane, with real sample depth.
// Captured source geometry is never drawn. Direct light uses per-pixel normals.
layout(local_size_x=64,local_size_y=1) in;
struct Task { vec4 job; vec4 span; vec4 right; vec4 up; vec4 forward; };
struct Sample { vec4 point_gray; vec4 normal_node; };
struct Patch { vec4 center_area; vec4 normal_gray; vec4 filter_absorption; };
struct Light { vec4 position_radius; vec4 power; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample values[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Tasks { Task values[]; } tasks;
layout(set=0,binding=2,std430) readonly buffer Camera {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 dims; vec4 jitter;
} camera;
struct Projection { vec4 position; vec4 footprint; };
layout(set=0,binding=3,std430) buffer Projected { Projection values[]; } projected;
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
// Normalize by resolved coverage BEFORE quantizing color. A tiny contribution
// must not round an ordinary gray to pure black/white. The 24-bit color sum
// stays bounded by COLOR_SCALE plus rounding, independent of sample density.
const float COLOR_SCALE=16777216.0;


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
    vec2 uv=(vec2(int(pixel)%camera.dims.x,int(pixel)/camera.dims.x)+vec2(.5)-camera.jitter.xy)/vec2(camera.dims.xy);
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

layout(set=0,binding=21,std430) readonly buffer Footprints { float values[]; } footprints;
layout(set=0,binding=22,std430) buffer Winners { uint values[]; } winners;

vec2 project_world(vec3 world) {
    vec3 delta=world-camera.eye.xyz;
    float depth=dot(delta,camera.forward.xyz);
    return vec2((dot(delta,camera.right.xyz)/(depth*camera.lens.x*camera.lens.y)+1.0)*.5*float(camera.dims.x),
        (1.0-dot(delta,camera.up.xyz)/(depth*camera.lens.x))*.5*float(camera.dims.y))+camera.jitter.xy;
}
float pixel_depth(Projection p,vec2 pixel) {
    return 1.0/(1.0/p.position.z+dot(p.footprint.zw,pixel-p.position.xy));
}
float coverage(Projection p,vec2 pixel) {
    vec2 q=abs(pixel-p.position.xy)/p.footprint.xy;
    return max(0.0,1.0-q.x)*max(0.0,1.0-q.y);
}
float depth_tolerance(float depth) { return .003+depth*.0005; }

void main() {
    uint i=gl_GlobalInvocationID.x;
    uint pixels=uint(camera.dims.x*camera.dims.y);
    if(phase.data.x==0) {
        if(i==0u) for(int k=0;k<16;k++) counters.values[k]=0u;
        if(i<pixels) {
            depths.values[i]=0x7f7fffffu; sums.values[i]=uvec4(0);
            owners.values[i]=0xffffffffu; winners.values[i]=0xffffffffu;
        }
        return;
    }
    if(phase.data.x==4) {
        if(i>=pixels) return;
        uvec4 sum=sums.values[i];
        if(sum.w>0u && winners.values[i]!=0xffffffffu) owners.values[i]=winners.values[i]/uint(camera.jitter.z);
        ivec2 xy=ivec2(int(i)%camera.dims.x,int(i)/camera.dims.x);
        imageStore(target_image,xy,sum.w>0u?vec4(vec3(sum.xyz)/COLOR_SCALE,1):vec4(0));
        return;
    }
    if(phase.data.x==6 || phase.data.x==7) {
        if(i>=pixels) return;
        Sample s; int owner; float depth;
        if(!receiver_at(i,s,owner,depth)) return;
        uint bits=floatBitsToUint(depth);
        if(phase.data.x==6) atomicMin(depths.values[i],bits);
        else if(depths.values[i]==bits && winners.values[i]==0xffffffffu) {
            vec3 e; vec3 color=sample_light(s,instances.values[owner],e);
            sums.values[i]=uvec4(uvec3(round(color*COLOR_SCALE)),uint(FIXED_SCALE));
            owners.values[i]=uint(owner);
        }
        return;
    }
    if(phase.data.x==5) {
        if(i>=uint(phase.data.w)) return;
        uvec4 probe=probes.values[i]; Sample s=samples.values[probe.x];
        vec3 e; vec3 color=sample_light(s,instances.values[probe.y],e);
        probe_output.values[i*2]=vec4(e,s.normal_node.w+instances.values[probe.y].shape.w);
        probe_output.values[i*2+1]=vec4(color,1);
        return;
    }
    if(phase.data.y==0 || i>=uint(tasks.values[phase.data.y-1].span.y)) return;
    uint lo=0u,hi=uint(phase.data.y);
    while(lo+1u<hi) {
        uint mid=(lo+hi)/2u;
        if(i<uint(tasks.values[mid].span.x)) hi=mid; else lo=mid;
    }
    Task task=tasks.values[lo];
    uint sample_index=uint(task.job.x)+i-uint(task.span.x);
    Sample s=samples.values[sample_index];
    uint owner=uint(task.job.z);
    Instance instance=instances.values[owner];
    if(phase.data.x==1) {
        projected.values[i].position=vec4(0);
        vec3 world=world_point(s.point_gray.xyz,instance);
        vec3 normal=world_normal(s.normal_node.xyz,instance);
        vec3 delta=world-camera.eye.xyz;
        float depth=dot(delta,camera.forward.xyz);
        float front=dot(normal,normalize(camera.eye.xyz-world));
        if(depth<camera.lens.z || depth>camera.lens.w || front<=.01) return;
        vec2 pixel=project_world(world);
        if(any(lessThan(pixel,vec2(-4))) || any(greaterThan(pixel,vec2(camera.dims.xy)+vec2(4)))) return;
        float width=footprints.values[sample_index];
        float nd=dot(s.normal_node.xyz,task.forward.xyz);
        vec3 tr=task.right.xyz,tu=task.up.xyz;
        if(abs(nd)>.25) {
            tr-=task.forward.xyz*dot(s.normal_node.xyz,tr)/nd;
            tu-=task.forward.xyz*dot(s.normal_node.xyz,tu)/nd;
        }
        vec2 r=project_world(world_point(s.point_gray.xyz+tr*width,instance))-pixel;
        vec2 u=project_world(world_point(s.point_gray.xyz+tu*width,instance))-pixel;
        // Capture-cell coverage plus a bounded reconstruction tent. Fine
        // boundary cells stay fine; coarse cells carry their real footprint.
        vec2 radius=clamp((abs(r)+abs(u))*.5+vec2(.55),vec2(.75),vec2(3.5));
        float plane=dot(normal,delta);
        vec2 gradient=vec2(2.0*camera.lens.x*camera.lens.y*dot(normal,camera.right.xyz)/float(camera.dims.x),
            -2.0*camera.lens.x*dot(normal,camera.up.xyz)/float(camera.dims.y))/plane;
        projected.values[i].position=vec4(pixel,depth,task.job.w*clamp(front/.5,0.0,1.0));
        projected.values[i].footprint=vec4(radius,gradient);
        return;
    }
    Projection p=projected.values[i];
    if(p.position.w<.00001 || p.position.z<=0.0) return;
    ivec2 low=max(ivec2(ceil(p.position.xy-p.footprint.xy-vec2(.5))),ivec2(0));
    ivec2 high=min(ivec2(floor(p.position.xy+p.footprint.xy-vec2(.5))),camera.dims.xy-ivec2(1));
    if(any(greaterThan(low,high))) return;
    vec3 color=vec3(0);
    uint key=owner*uint(camera.jitter.z)+sample_index;
    if(phase.data.x==3) {
        atomicAdd(counters.values[0],1u);
        bool survives=false;
        for(int y=low.y;y<=high.y;y++) for(int x=low.x;x<=high.x;x++) {
            uint target=uint(y*camera.dims.x+x);
            uint winner=winners.values[target];
            if(winner==0xffffffffu || winner/uint(camera.jitter.z)!=owner) continue;
            float z=pixel_depth(p,vec2(x,y)+vec2(.5));
            if(abs(uintBitsToFloat(depths.values[target])-z)>depth_tolerance(z)) continue;
            Sample nearest=samples.values[winner%uint(camera.jitter.z)];
            if(dot(s.normal_node.xyz,nearest.normal_node.xyz)<.95) continue;
            if(coverage(p,vec2(x,y)+vec2(.5))>.0001) survives=true;
        }
        if(!survives) { atomicAdd(counters.values[2],1u); return; }
        atomicAdd(counters.values[1],1u);
        vec3 e; color=sample_light(s,instance,e);
    }
    for(int y=low.y;y<=high.y;y++) for(int x=low.x;x<=high.x;x++) {
        vec2 pixel=vec2(x,y)+vec2(.5);
        float cov=coverage(p,pixel);
        if(cov<.0001) continue;
        uint weight=uint(round(clamp(p.position.w*cov,0.0,1.0)*FIXED_SCALE));
        if(weight==0u) continue;
        uint target=uint(y*camera.dims.x+x);
        float z=pixel_depth(p,pixel);
        if(z<camera.lens.z || z>camera.lens.w) continue;
        uint bits=floatBitsToUint(z);
        if(phase.data.x==2) { atomicMin(depths.values[target],bits); atomicAdd(counters.values[3],1u); }
        else if(phase.data.x==8 && bits==depths.values[target]) atomicMin(winners.values[target],key);
        else if(phase.data.x==3 || phase.data.x==9) {
            uint winner=winners.values[target];
            if(winner==0xffffffffu || winner/uint(camera.jitter.z)!=owner) { atomicAdd(counters.values[4],1u); continue; }
            if(abs(uintBitsToFloat(depths.values[target])-z)>depth_tolerance(z)) continue;
            Sample nearest=samples.values[winner%uint(camera.jitter.z)];
            if(dot(s.normal_node.xyz,nearest.normal_node.xyz)<.95) { atomicAdd(counters.values[5],1u); continue; }
            if(phase.data.x==9) atomicAdd(sums.values[target].w,weight);
            else {
                float contribution=float(weight)/float(sums.values[target].w)*COLOR_SCALE;
                atomicAdd(sums.values[target].x,uint(round(color.x*contribution)));
                atomicAdd(sums.values[target].y,uint(round(color.y*contribution)));
                atomicAdd(sums.values[target].z,uint(round(color.z*contribution)));
            }
        }
    }
}
