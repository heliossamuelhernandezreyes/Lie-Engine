#[compute]
#version 450
#define LIE_SURFACE_PROBE 1
// LIE28: source RGB albedo and roughness captured without lighting.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
// 64-byte std430 record: offsets 0/12, 16/24, 32/44, 48/60.
struct Projection {
    vec3 normal; float depth;
    vec2 center; vec2 gradient;
    vec3 geometry; float owner;
    vec3 ellipse; float radius;
};
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=14,std430) readonly buffer OpticalNormals {vec4 v[];} optical_normals;
layout(set=0,binding=0,std430) readonly buffer Samples { Sample v[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Instances { Instance v[]; } instances;
layout(set=0,binding=2,std430) readonly buffer Jobs { uvec4 v[]; } jobs;
layout(set=0,binding=3,std430) readonly buffer Projected { Projection v[]; } projected;
layout(set=0,binding=4,std430) readonly buffer Depth { uint v[]; } depths;
layout(set=0,binding=5,std430) readonly buffer Winner { uint v[]; } winners;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=7,std430) readonly buffer Accumulated { Accumulator v[]; } accumulated;




layout(set=0,binding=13,std430) readonly buffer Shadow { uint v[]; } shadow;
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;
vec2 project(vec3 p,vec3 eye,vec3 right,vec3 up,vec3 forward,float tangent,vec2 size) {
    vec3 d=p-eye;float z=dot(d,forward);
    return vec2((dot(d,right)/(z*tangent)+1)*.5,(1-dot(d,up)/(z*tangent))*.5)*size;
}
bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    if(p.radius<0.) {
        vec2 uv=xy/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)
            +parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
        return p.depth/dot(p.geometry,ray);
    }
    return 1.0/(1.0/p.depth+dot(p.gradient,xy-p.center));
}
float footprint_distance(Projection p,vec2 xy) {
    if(p.radius<0.) {
        float z=pixel_depth(p,xy);
        if(isnan(z)||isinf(z)||z<=parameters.lens.z||z>=parameters.lens.w)return 2.;
        vec2 uv=xy/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)
            +parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
        vec3 d=ray*z-p.ellipse;return dot(d,d)/(p.radius*p.radius);
    }
    vec2 q=xy-p.center;
    return q.x*q.x*p.ellipse.x+2.*q.x*q.y*p.ellipse.y+q.y*q.y*p.ellipse.z;
}
struct SourceBounds { uvec4 interval; vec4 low; vec4 high; };
layout(set=0,binding=15,std430) readonly buffer SourceLimits {SourceBounds v[];} source_limits;
SourceBounds source_bounds(uint sid) {
    uint lo=0u,hi=uint(parameters.iris.x);
    while(lo+1u<hi) {uint mid=(lo+hi)/2u;if(source_limits.v[mid].interval.x<=sid)lo=mid;else hi=mid;}
    return source_limits.v[lo];
}
bool in_source(SourceBounds b,uint sid,vec3 local) {
    return sid<b.interval.y && all(greaterThanEqual(local,b.low.xyz-vec3(.000002))) && all(lessThanEqual(local,b.high.xyz+vec3(.000002)));
}
bool covered(Projection p,vec2 xy,Sample s,Instance inst,mat3 inverse_basis,SourceBounds bounds,uint sid) {
    if(footprint_distance(p,xy)>1) return false;
    // Keep coarse samples on their original source face. In particular, a
    // brick's projected discs cannot cover adjacent mortar or an opening.
    vec2 uv=xy/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
    vec3 local=inverse_basis*(parameters.eye.xyz+ray*pixel_depth(p,xy)-inst.origin.xyz);
    if(!in_source(bounds,sid,local))return false;
    if(inst.meta.z>0. && local.x>inst.meta.w+1e-7)return false;
    if(inst.meta.z<0. && local.x<inst.meta.w-1e-7)return false;
    vec3 n=abs(s.normal_gray.xyz);
    vec2 q=n.x>=n.y && n.x>=n.z?local.zy:n.y>=n.z?local.xz:local.xy;
    return all(greaterThanEqual(q,s.support.xy-vec2(.000002))) && all(lessThanEqual(q,s.support.zw+vec2(.000002)));
}




layout(set=0,binding=20,std430) buffer BankJobs {uvec4 v[];} bank_jobs;
uint job_index(uint invocation) {
    uint lo=0u,hi=uint(parameters.counts.y);
    while(lo+1u<hi) {uint mid=(lo+hi)/2u;if(bank_jobs.v[mid].x<=invocation)lo=mid;else hi=mid;}
    return lo;
}
uint hash(uint x) {x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float variation(uint id) {return float(hash(id+uint(parameters.settings.x))&65535u)/65535.0;}
vec3 material_color(Sample s,Instance inst) {
    uint id=uint(max(inst.meta.x,0))+uint(max(s.attributes.y,0));
    float v=(variation(id)-.5)*parameters.wall.w;
    return clamp(s.albedo.rgb*inst.tint.rgb*(1+v),vec3(0),vec3(1));
}


// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.



// LIE 6.5 camera surface contract. Projection remains 64 bytes.
// Positive radius: exact projected disk conic. Negative radius: a disk that
// intersects a clip plane, stored as eye-relative center + world radius.
// Large footprints are queued once and distributed over a 64-lane workgroup.
// Queue + optional probe counters live after the immutable jobs prefix; this
// keeps the existing twelve-storage-buffer descriptor contract.
#ifdef LIE_SURFACE_PROBE
#define LIE_PROBE_DECLARE uint tested=0u,supported=0u,material=0u
#define LIE_PROBE_TEST tested++
#define LIE_PROBE_SUPPORT supported++
#define LIE_PROBE_ACCEPT material++
#define LIE_PROBE_DEPTH lie_probe_add(0u,tested);lie_probe_add(1u,supported)
#define LIE_PROBE_MATERIAL lie_probe_add(2u,material)
#define LIE_DEPTH_WRITE(pixel,bits)
#define LIE_OWNER_WRITE(pixel,index)
#define LIE_MATERIAL_WRITE(pixel,index,p,s,inst,distance)
#else
#define LIE_PROBE_DECLARE
#define LIE_PROBE_TEST
#define LIE_PROBE_SUPPORT
#define LIE_PROBE_ACCEPT
#define LIE_PROBE_DEPTH
#define LIE_PROBE_MATERIAL
#define LIE_DEPTH_WRITE(pixel,bits) atomicMin(depths.v[pixel],bits)
#define LIE_OWNER_WRITE(pixel,index) atomicMin(winners.v[pixel],index)
#define LIE_MATERIAL_WRITE(pixel,index,p,s,inst,distance) lie_accumulate(pixel,index,p,s,inst,distance)
#endif
vec3 lie_camera_ray(vec2 xy) {
    vec2 uv=xy/vec2(parameters.counts.zw);
    return parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)
        +parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
}
bool lie_finite(float v) {return !isnan(v) && !isinf(v);}
uint lie_queue_header() {return uint(parameters.iris.y);}
void lie_probe_add(uint component,uint value) {
    if(parameters.iris.w<.5 || value==0u)return;
    uint h=lie_queue_header()+1u;
    uint previous=atomicAdd(bank_jobs.v[h][component],value);
    if(previous>0xffffffffu-value)atomicOr(bank_jobs.v[h].w,1u<<component);
}
void lie_enqueue(uint projection,uint job) {
    uint h=lie_queue_header();uint slot=atomicAdd(bank_jobs.v[h].w,1u);
    // At most one entry per selected invocation; host reserves work*8 bytes.
    uint at=(h+2u)*4u+slot*2u;
    bank_jobs.v[at/4u][at%4u]=projection;
    bank_jobs.v[(at+1u)/4u][(at+1u)%4u]=job;
    uint count=slot+1u;
    atomicMax(bank_jobs.v[h].x,min(count,32768u));
    atomicMax(bank_jobs.v[h].y,(count+32767u)/32768u);
}
ivec4 lie_clip_box(vec2 low,vec2 high) {
    vec2 size=vec2(parameters.counts.zw);
    low=clamp(floor(low)-vec2(1.),vec2(-1.),size);
    high=clamp(ceil(high)+vec2(1.),vec2(-1.),size);
    return ivec4(max(ivec2(low),ivec2(0)),min(ivec2(high),parameters.counts.zw-ivec2(1)));
}
ivec4 lie_surface_bounds(Projection p) {
    if(p.radius==0.)return ivec4(1,1,0,0);
    if(p.radius<0.)return ivec4(p.center,p.gradient);
    float det=p.ellipse.x*p.ellipse.z-p.ellipse.y*p.ellipse.y;
    vec2 extent=sqrt(max(vec2(p.ellipse.z,p.ellipse.x)/det,vec2(0.)));
    return lie_clip_box(p.center-extent,p.center+extent);
}
bool lie_empty_bounds(ivec4 b) {return b.z<b.x || b.w<b.y;}
bool lie_large_surface(Projection p,ivec4 b) {
    return p.radius<0. || b.z-b.x+1>128 || b.w-b.y+1>128;
}
ivec4 lie_supported_bounds(Projection p,Sample s,Instance inst,SourceBounds bounds) {
    // Intersect only already-authoritative source bounds, support rectangle
    // and instance cut. This bounds work; covered() still decides each pixel.
    vec3 low=bounds.low.xyz-vec3(.000002),high=bounds.high.xyz+vec3(.000002);
    vec3 n=abs(s.normal_gray.xyz);
    if(n.x>=n.y && n.x>=n.z) {low.zy=max(low.zy,s.support.xy-vec2(.000002));high.zy=min(high.zy,s.support.zw+vec2(.000002));}
    else if(n.y>=n.z) {low.xz=max(low.xz,s.support.xy-vec2(.000002));high.xz=min(high.xz,s.support.zw+vec2(.000002));}
    else {low.xy=max(low.xy,s.support.xy-vec2(.000002));high.xy=min(high.xy,s.support.zw+vec2(.000002));}
    if(inst.meta.z>0.)high.x=min(high.x,inst.meta.w+1e-7);
    if(inst.meta.z<0.)low.x=max(low.x,inst.meta.w-1e-7);
    if(any(greaterThan(low,high)))return ivec4(1,1,0,0);
    vec3 center=(low+high)*.5,extent=(high-low)*.5,origin=inst.origin.xyz-parameters.eye.xyz;
    vec3 right=vec3(dot(parameters.right.xyz,inst.x.xyz),dot(parameters.right.xyz,inst.y.xyz),dot(parameters.right.xyz,inst.z.xyz));
    vec3 up=vec3(dot(parameters.up.xyz,inst.x.xyz),dot(parameters.up.xyz,inst.y.xyz),dot(parameters.up.xyz,inst.z.xyz));
    vec3 forward=vec3(dot(parameters.forward.xyz,inst.x.xyz),dot(parameters.forward.xyz,inst.y.xyz),dot(parameters.forward.xyz,inst.z.xyz));
    vec3 c=vec3(dot(right,center)+dot(parameters.right.xyz,origin),dot(up,center)+dot(parameters.up.xyz,origin),dot(forward,center)+dot(parameters.forward.xyz,origin));
    vec3 e=vec3(dot(abs(right),extent),dot(abs(up),extent),dot(abs(forward),extent));
    // Expand camera-space bounds for cancellation at a grazing clip plane.
    e+=vec3(.000008)*(vec3(1.)+abs(c));low=c-e;high=c+e;
    low.z=max(low.z,parameters.lens.z);high.z=min(high.z,parameters.lens.w);
    if(low.z>high.z)return ivec4(1,1,0,0);
    vec2 screen_low=vec2(1e30),screen_high=vec2(-1e30);
    for(int k=0;k<8;k++) {
        vec3 q=vec3((k&1)==0?low.x:high.x,(k&2)==0?low.y:high.y,(k&4)==0?low.z:high.z);
        vec2 xy=vec2(q.x/(q.z*parameters.lens.x)+1.,1.-q.y/(q.z*parameters.lens.x))*.5*vec2(parameters.counts.zw);
        screen_low=min(screen_low,xy);screen_high=max(screen_high,xy);
    }
    ivec4 a=lie_surface_bounds(p),b=lie_clip_box(screen_low,screen_high);
    return ivec4(max(a.xy,b.xy),min(a.zw,b.zw));
}
ivec2 lie_surface_row(Projection p,ivec4 box,int y) {
    if(p.radius<0.)return box.xz;
    float dy=float(y)+.5-p.center.y;
    float A=p.ellipse.x,B=p.ellipse.y,C=p.ellipse.z;
    float section=1.-(C-B*B/A)*dy*dy;
    if(A<=0. || !lie_finite(section))return box.xz;
    float span=sqrt(max(section,0.)/A);
    float middle=p.center.x-B*dy/A-.5;
    // Clamp as floats before integer conversion: offscreen centers may be far.
    float low=max(float(box.x),floor(middle-span)-1.);
    float high=min(float(box.z),ceil(middle+span)+1.);
    if(low>high)return ivec2(1,0);
    return ivec2(low,high);
}
Projection lie_project_surface(vec3 delta,vec3 n,vec3 shading,float radius,float owner) {
    Projection p;
    p.normal=shading;p.depth=0.;p.center=vec2(0.);p.gradient=vec2(0.);
    p.geometry=n;p.owner=owner;p.ellipse=vec3(0.);p.radius=0.;
    float plane=dot(n,delta),z=dot(delta,parameters.forward.xyz);
    // Facing is a plane property; a positive grazing disk must not disappear
    // merely because its center cosine is below an arbitrary 0.015 threshold.
    if(!(plane<0.) || !(radius>0.) || !lie_finite(plane))return p;
    float nz=dot(n,parameters.forward.xyz);
    float rz=radius*sqrt(max(0.,1.-nz*nz));
    if(z+rz<=parameters.lens.z || z-rz>=parameters.lens.w)return p;
    if(z-rz>parameters.lens.z && z+rz<parameters.lens.w) {
        vec2 center=project(parameters.eye.xyz+delta,parameters.eye.xyz,
            parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,
            parameters.lens.x,vec2(parameters.counts.zw));
        vec3 rx=parameters.right.xyz*(2.*parameters.lens.x/float(parameters.counts.z));
        vec3 ry=parameters.up.xyz*(-2.*parameters.lens.x/float(parameters.counts.w));
        float dx=dot(n,rx),dy=dot(n,ry),d0=plane/z,r2=radius*radius;
        vec3 a=plane*rx-delta*dx,b=plane*ry-delta*dy;
        float A=dot(a,a)-r2*dx*dx,B=dot(a,b)-r2*dx*dy,C=dot(b,b)-r2*dy*dy;
        float det=A*C-B*B;
        vec2 linear=-r2*d0*vec2(dx,dy);
        if(A>0. && C>0. && det>0. && lie_finite(det)) {
            vec2 shift=vec2(B*linear.y-C*linear.x,B*linear.x-A*linear.y)/det;
            float scale=r2*d0*d0-dot(linear,shift);
            vec3 ellipse=vec3(A,B,C)/scale;
            float ellipse_det=ellipse.x*ellipse.z-ellipse.y*ellipse.y;
            center+=shift;
            float depth=plane/dot(n,lie_camera_ray(center));
            if(scale>0. && depth>0. && ellipse_det>0. && lie_finite(ellipse_det) && all(lessThan(abs(center),vec2(1e12)))
                && all(lessThan(abs(ellipse),vec3(1e30))) && lie_finite(depth)) {
                p.center=center;p.depth=depth;p.gradient=vec2(dx,dy)/plane;
                p.ellipse=ellipse;p.radius=radius;return p;
            }
        }
    }
    // Conservative camera-space AABB of the disk, clipped to positive depth.
    // Exact ray/plane/disk and source-support predicates remain authoritative.
    vec3 c=vec3(dot(delta,parameters.right.xyz),dot(delta,parameters.up.xyz),z);
    vec3 axes=vec3(dot(n,parameters.right.xyz),dot(n,parameters.up.xyz),nz);
    vec3 extent=radius*sqrt(max(vec3(0.),vec3(1.)-axes*axes));
    vec3 low=c-extent,high=c+extent;
    low.z=max(low.z,parameters.lens.z);high.z=min(high.z,parameters.lens.w);
    vec2 screen_low=vec2(1e30),screen_high=vec2(-1e30);
    for(int k=0;k<8;k++) {
        vec3 q=vec3((k&1)==0?low.x:high.x,(k&2)==0?low.y:high.y,(k&4)==0?low.z:high.z);
        vec2 xy=vec2(q.x/(q.z*parameters.lens.x)+1.,1.-q.y/(q.z*parameters.lens.x))*.5*vec2(parameters.counts.zw);
        screen_low=min(screen_low,xy);screen_high=max(screen_high,xy);
    }
    ivec4 box=lie_clip_box(screen_low,screen_high);
    if(lie_empty_bounds(box))return p;
    p.depth=plane;p.center=vec2(box.xy);p.gradient=vec2(box.zw);
    p.ellipse=delta;p.radius=-radius;return p;
}
#ifndef LIE_SURFACE_PROBE
void lie_accumulate(uint pixel,uint i,Projection p,Sample s,Instance inst,float distance) {
    uint owner=winners.v[pixel];
    if(owner==EMPTY || projected.v[owner].owner!=p.owner)return;
    uint w=max(uint(round(256.*exp(-2.*max(distance,0.)))),1u);
    uvec3 c=uvec3(round(material_color(s,inst)*float(w)));
    uvec3 n=uvec3(round((p.normal*.5+.5)*float(w)));
    atomicAdd(accumulated.v[pixel].color_weight.x,c.x);
    atomicAdd(accumulated.v[pixel].color_weight.y,c.y);
    atomicAdd(accumulated.v[pixel].color_weight.z,c.z);
    atomicAdd(accumulated.v[pixel].color_weight.w,w);
    atomicAdd(accumulated.v[pixel].normal_roughness.x,n.x);
    atomicAdd(accumulated.v[pixel].normal_roughness.y,n.y);
    atomicAdd(accumulated.v[pixel].normal_roughness.z,n.z);
    float rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
    if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {
        uint id=uint(max(inst.meta.x,0.));
        if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));
        rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);
    }
    atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(rough*float(w))));
}
#endif


void main() {
    uint invocation=gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x;
    if(invocation>=uint(parameters.counts.x))return;
    uint j=job_index(invocation);uvec4 address=bank_jobs.v[j];uint local_index=invocation-address.x;
    uint i=address.y+local_index;
    if(address.w!=0u) {uint cursor=address.y+local_index;i=bank_jobs.v[cursor/4u][cursor%4u];}
    uvec4 job=jobs.v[address.z];uint sid=job.x+i-job.w;
    Instance inst=instances.v[job.z];if(int(inst.meta.y)!=int(parameters.settings.z))return;
    Sample s=samples.v[sid];
    mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz),inverse_basis=inverse(basis);
    SourceBounds bounds=source_bounds(sid);Projection p;
    const int stage=2;
#ifndef LIE_SURFACE_PROBE
    if(stage==2) {
        vec3 local=s.position_radius.xyz;float radius=s.position_radius.w;
        if(parameters.settings.y<.5) {
            float r=length(local.xy),inner=.0017,outer=.006;
            if(int(s.attributes.x)==1 && r>1e-8) {
                float nr=parameters.iris.w+(r-inner)*(outer-parameters.iris.w)/(outer-inner);
                local.xy*=nr/r;radius*=max(nr/r,(outer-parameters.iris.w)/(outer-inner));
            } else if(int(s.attributes.x)==2) {local.xy*=parameters.iris.w/inner;radius*=parameters.iris.w/inner;}
        }
        vec3 delta=basis*local+inst.origin.xyz-parameters.eye.xyz;
        vec3 n=normalize(transpose(inverse_basis)*s.normal_gray.xyz),shading=n;
        if(parameters.settings.w>.5) {vec4 optical=optical_normals.v[sid];if(optical.w>.5)shading=normalize(transpose(inverse_basis)*optical.xyz);}
        radius*=max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
        p=lie_project_surface(delta,n,shading,radius,float(job.z));projected.v[i]=p;
    } else p=projected.v[i];
#else
    p=projected.v[i];
#endif
    if(p.radius==0.)return;
    ivec4 box=lie_surface_bounds(p);if(lie_empty_bounds(box))return;
    if(lie_large_surface(p,box)) {
#ifndef LIE_SURFACE_PROBE
        if(stage==2)lie_enqueue(i,address.z);
#endif
        return;
    }
    LIE_PROBE_DECLARE;
    for(int y=box.y;y<=box.w;y++) {
        ivec2 row=lie_surface_row(p,box,y);
        for(int x=row.x;x<=row.y;x++) {
            vec2 xy=vec2(x,y)+.5;float distance=footprint_distance(p,xy);
            if(distance>1. || !lie_finite(distance))continue;
            float z=pixel_depth(p,xy);if(z<=parameters.lens.z||z>=parameters.lens.w||!lie_finite(z))continue;
            uint pixel=uint(y*parameters.counts.z+x),bits=floatBitsToUint(z);
            if(stage==3 && depths.v[pixel]!=bits)continue;
            if(stage==12) {
                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;
                uint winner=winners.v[pixel];if(winner==EMPTY||projected.v[winner].owner!=p.owner)continue;
            }
            if(stage==2) {LIE_PROBE_TEST;}
            if(!covered(p,xy,s,inst,inverse_basis,bounds,sid))continue;
            if(stage==2) {LIE_PROBE_SUPPORT;LIE_DEPTH_WRITE(pixel,bits);}
            else if(stage==3) {LIE_OWNER_WRITE(pixel,i);}
            else {LIE_MATERIAL_WRITE(pixel,i,p,s,inst,distance);LIE_PROBE_ACCEPT;}
        }
    }
    if(stage==2) {LIE_PROBE_DEPTH;}
    if(stage==12) {LIE_PROBE_MATERIAL;}
}
