#[compute]
#version 450
// Lie's own temporal resolve: current captured depth, stable rigid owner,
// current/previous invisible transforms and previous camera. No mesh motion
// vectors, no frame generation, and no readback in the interactive path.
layout(local_size_x=8,local_size_y=8) in;
layout(rgba32f,set=0,binding=0) uniform readonly image2D current_image;
layout(rgba32f,set=0,binding=1) uniform readonly image2D previous_image;
layout(rgba32f,set=0,binding=2) uniform writeonly image2D resolved_image;
layout(set=0,binding=3,std430) readonly buffer Depths { uint values[]; } depths;
layout(set=0,binding=4,std430) readonly buffer Owners { uint values[]; } owners;
layout(set=0,binding=5,std430) readonly buffer PreviousMeta { uvec2 values[]; } previous_meta;
layout(set=0,binding=6,std430) writeonly buffer NextMeta { uvec2 values[]; } next_meta;
struct Camera { vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 dims; vec4 jitter; };
layout(set=0,binding=7,std430) readonly buffer CurrentCamera { Camera value; } camera;
layout(set=0,binding=8,std430) readonly buffer PreviousCamera { Camera value; } previous_camera;
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 shape; vec4 material; vec4 pbr; };
layout(set=0,binding=9,std430) readonly buffer Instances { Instance values[]; } instances;
struct Pose { vec4 x; vec4 y; vec4 z; vec4 origin; };
layout(set=0,binding=10,std430) readonly buffer PreviousPoses { Pose values[]; } previous_poses;
layout(set=0,binding=11,std430) buffer Counters { uint values[]; } counters;
layout(push_constant,std430) uniform Config { ivec4 flags; vec4 policy; } config;

void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy),size=camera.value.dims.xy;
    if(any(greaterThanEqual(xy,size))) return;
    uint pixel=uint(xy.y*size.x+xy.x),owner=owners.values[pixel];
    vec4 current=imageLoad(current_image,xy);
    next_meta.values[pixel]=uvec2(depths.values[pixel],owner);
    // Newly uncovered space is always represented by THIS frame. History
    // cannot draw a robot into a current background/receiver pixel.
    if(current.a<.5 || owner==0xffffffffu || config.flags.y==0 || config.flags.x==0) {
        if(current.a>.5 && config.flags.y!=0 && config.flags.x==0) atomicAdd(counters.values[13],1u);
        imageStore(resolved_image,xy,current); return;
    }
    Camera c=camera.value,prev=previous_camera.value;
    vec2 uv=(vec2(xy)+vec2(.5)-c.jitter.xy)/vec2(size);
    vec3 ray=c.forward.xyz+(uv.x*2.0-1.0)*c.lens.x*c.lens.y*c.right.xyz
        +(1.0-uv.y*2.0)*c.lens.x*c.up.xyz;
    vec3 world=c.eye.xyz+ray*uintBitsToFloat(depths.values[pixel]);
    vec3 before=world;
    if(owner<15u) {
        Instance s=instances.values[owner];
        vec3 q=world-s.origin.xyz;
        vec3 local=vec3(dot(q,s.x.xyz)/dot(s.x.xyz,s.x.xyz),dot(q,s.y.xyz)/dot(s.y.xyz,s.y.xyz),dot(q,s.z.xyz)/dot(s.z.xyz,s.z.xyz));
        Pose p=previous_poses.values[owner];
        before=p.origin.xyz+p.x.xyz*local.x+p.y.xyz*local.y+p.z.xyz*local.z;
    }
    vec3 delta=before-prev.eye.xyz;
    float expected_depth=dot(delta,prev.forward.xyz);
    vec2 position=vec2((dot(delta,prev.right.xyz)/(expected_depth*prev.lens.x*prev.lens.y)+1.0)*.5*float(size.x),
        (1.0-dot(delta,prev.up.xyz)/(expected_depth*prev.lens.x))*.5*float(size.y))+prev.jitter.xy-vec2(.5);
    if(expected_depth<prev.lens.z || expected_depth>prev.lens.w || any(lessThan(position,vec2(-.5))) || any(greaterThan(position,vec2(size)-vec2(.5)))) {
        atomicAdd(counters.values[9],1u); atomicAdd(counters.values[14],1u);
        imageStore(resolved_image,xy,current); return;
    }
    ivec2 base=ivec2(floor(position)); vec2 t=fract(position);
    vec3 history=vec3(0); float total=0.0;
    bool wrong_owner=false,wrong_depth=false;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 at=base+ivec2(x,y);
        if(any(lessThan(at,ivec2(0))) || any(greaterThanEqual(at,size))) continue;
        float weight=(x==0?1.0-t.x:t.x)*(y==0?1.0-t.y:t.y);
        if(weight<.00001) continue;
        uvec2 meta=previous_meta.values[uint(at.y*size.x+at.x)];
        if(meta.y!=owner) { wrong_owner=true; continue; }
        float depth=uintBitsToFloat(meta.x);
        if(abs(depth-expected_depth)>.008+expected_depth*.002) { wrong_depth=true; continue; }
        vec4 color=imageLoad(previous_image,at);
        if(color.a<.5) continue;
        history+=color.rgb*weight; total+=weight;
    }
    if(total<.2) {
        atomicAdd(counters.values[9],1u);
        if(wrong_owner) atomicAdd(counters.values[11],1u);
        if(wrong_depth) atomicAdd(counters.values[10],1u);
        imageStore(resolved_image,xy,current); return;
    }
    history/=total;
    vec3 low=current.rgb,high=current.rgb;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        ivec2 at=clamp(xy+ivec2(x,y),ivec2(0),size-ivec2(1));
        uint index=uint(at.y*size.x+at.x);
        if(owners.values[index]!=owner) continue;
        vec3 color=imageLoad(current_image,at).rgb;
        low=min(low,color); high=max(high,color);
    }
    vec3 safe=clamp(history,low,high);
    if(any(greaterThan(abs(history-safe),vec3(.00001)))) atomicAdd(counters.values[12],1u);
    // Reactive color and velocity reduce history weight on changing specular
    // highlights, shadows and fast articulation rather than leaving trails.
    float change=max(max(abs(history.r-current.r),abs(history.g-current.g)),abs(history.b-current.b));
    float velocity=length(position-vec2(xy));
    float blend=config.policy.x*exp(-velocity*.06)*clamp(1.0-change/.12,0.0,1.0)*min(total,1.0);
    atomicAdd(counters.values[8],1u);
    imageStore(resolved_image,xy,vec4(mix(current.rgb,safe,blend),current.a));
}
