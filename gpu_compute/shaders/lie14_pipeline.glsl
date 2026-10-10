#[compute]
#version 450
// Shared object-local samples -> current camera plane, with real sample depth.
// Captured source geometry is never drawn. Direct light uses per-pixel normals.
layout(local_size_x=64,local_size_y=1) in;
struct Sample { vec4 point_gray; vec4 normal_node; };
struct Patch { vec4 center_area; vec4 normal_gray; vec4 filter_absorption; };
struct Light { vec4 position_radius; vec4 power; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample values[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Tasks { vec4 values[]; } tasks;
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
layout(push_constant,std430) uniform Phase { ivec4 data; } phase;
const float PI=3.141592653589793;
const float FIXED_SCALE=8192.0;


struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 shape; vec4 material; };
layout(set=0,binding=14,std430) readonly buffer Instances { Instance values[]; } instances;
vec3 local_point(vec3 p, Instance s) {
    vec3 q=p-s.origin.xyz;
    return vec3(dot(q,s.x.xyz),dot(q,s.y.xyz),dot(q,s.z.xyz));
}
vec3 world_point(vec3 p, Instance s) { return s.origin.xyz+s.x.xyz*p.x+s.y.xyz*p.y+s.z.xyz*p.z; }
vec3 world_normal(vec3 n, Instance s) { return normalize(s.x.xyz*n.x+s.y.xyz*n.y+s.z.xyz*n.z); }
bool cylinder_hit(vec3 a,vec3 b,Instance s) {
    if(s.shape.z<0.5) return false;
    vec3 p=local_point(a,s), d=local_point(b,s)-p;
    float r=s.shape.x,h=s.shape.y;
    float aa=dot(d.xz,d.xz),bb=2.0*dot(p.xz,d.xz),cc=dot(p.xz,p.xz)-r*r;
    if(aa>1e-12) {
        float disc=bb*bb-4.0*aa*cc;
        if(disc>=0.0) {
            float root=sqrt(disc);
            for(int k=0;k<2;k++) {
                float t=(-bb+(k==0?-root:root))/(2.0*aa);
                if(t>.001 && t<.999 && abs(p.y+t*d.y)<=h) return true;
            }
        }
    }
    if(abs(d.y)>1e-10) {
        for(int k=0;k<2;k++) {
            float t=((k==0?-h:h)-p.y)/d.y;
            vec2 radial=p.xz+t*d.xz;
            if(t>.001 && t<.999 && dot(radial,radial)<=r*r) return true;
        }
    }
    return false;
}
bool rigid_blocked(vec3 a,vec3 b) {
    for(int k=0;k<3;k++) if(cylinder_hit(a,b,instances.values[k])) return true;
    return false;
}


vec3 direct_at(vec3 p,vec3 n) {
    vec3 result=vec3(0.0);
    for(int l=0;l<camera.dims.z;l++) {
        Light source=lights.values[l];
        vec3 delta=source.position_radius.xyz-p;
        float d2=dot(delta,delta),radius=source.position_radius.w;
        if(d2<1e-10 || radius<=0.0) continue;
        float cosine=max(dot(n,delta*inversesqrt(d2)),0.0);
        if(cosine<=0.0 || rigid_blocked(p+n*.003,source.position_radius.xyz)) continue;
        float window=pow(max(0.0,1.0-pow(sqrt(d2)/radius,4.0)),2.0);
        result+=source.power.rgb*cosine*window/(4.0*PI*max(d2,.0025)*max(caps.values[l],1.0));
    }
    return result;
}
vec3 sample_light(Sample s,Instance instance,out vec3 direct_value) {
    int node=int(round(s.normal_node.w+instance.shape.w));
    vec3 p=world_point(s.point_gray.xyz,instance);
    vec3 n=world_normal(s.normal_node.xyz,instance);
    if(camera.dims.w==0) n=patches.values[node].normal_gray.xyz;
    direct_value=direct_at(p,n);
    vec3 indirect=max(imageLoad(irradiance,ivec2(node,0)).rgb-imageLoad(direct_irradiance,ivec2(node,0)).rgb,vec3(0));
    vec3 radiance=s.point_gray.w*instance.material.rgb*(1.0-instance.material.w)*(direct_value+indirect)/PI;
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
    for(int k=3;k<5;k++) {
        int axis=k==3?1:2;
        float coordinate=k==3?-1.05:-2.0;
        if(camera.eye[axis]<=coordinate || abs(ray[axis])<1e-10) continue;
        float t=(coordinate-camera.eye[axis])/ray[axis];
        vec3 p=camera.eye.xyz+t*ray;
        bool inside=abs(p.x)<=2.0 && (k==3?abs(p.z)<=2.0:(p.y>=-1.0 && p.y<=3.0));
        if(!inside || t<camera.lens.z || t>camera.lens.w || t>=depth) continue;
        depth=t;
        owner=k;
        int col=int(clamp(p.x+2.0,0.0,3.99999));
        int row=int(clamp(k==3?p.z+2.0:p.y+1.0,0.0,3.99999));
        s.point_gray=vec4(p,.7);
        s.normal_node=vec4(k==3?vec3(0,1,0):vec3(0,0,1),float(row*4+col));
    }
    return owner>=0;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint pixels=uint(camera.dims.x*camera.dims.y);
    if(phase.data.x==0) {
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
    uint stride=uint(phase.data.z);
    uint task=i/stride,offset=i%stride;
    if(task>=uint(phase.data.y)) return;
    vec4 job=tasks.values[task];
    if(offset>=uint(job.y)) return;
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
        vec3 e;
        color=sample_light(s,instance,e);
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
