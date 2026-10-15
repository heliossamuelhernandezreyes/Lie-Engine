#[compute]
#version 450
// GENERATED dedicated stage 2; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample v[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Instances { Instance v[]; } instances;
layout(set=0,binding=2,std430) readonly buffer Jobs { uvec4 v[]; } jobs;
layout(set=0,binding=3,std430) buffer Projected { Projection v[]; } projected;
layout(set=0,binding=4,std430) buffer Depth { uint v[]; } depths;
layout(set=0,binding=5,std430) buffer Winner { uint v[]; } winners;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=7,std430) buffer Accumulated { Accumulator v[]; } accumulated;





/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */


/* 48 immutable bytes derived from real brick layout. Geometry remains source
   LIE samples, NOT faces of the coarse invisible spatial envelope. */
layout(set=0,binding=16,std430) readonly buffer WallJointLayout {
    vec4 dimensions; // real brick X length, Y height, x pitch, y pitch
    vec4 origin;     // first brick X/Y, recessed mortar plane Z, row stagger
    vec4 config;     // column count, row count, nominal mortar gap, enabled
} joint;

// WALL04 only: close the nominal 8.5mm spacing toward the 3mm visual boundary over the 6mm photographed core
// by expanding EACH original scanned brick about its original XY center.
// The GPU source sample buffer remains byte-identical to WALL03; there is
// no mesh creation and the one invisible box/collider is unchanged.
const float WALL04_VISIBLE_JOINT_M = 0.003;
vec2 wall04_brick_center(uint node) {
    uint brick=node/9u;
    uint row=brick/12u, col=brick%12u;
    float stagger=(row%2u==1u)?joint.origin.w*joint.dimensions.z:0.0;
    return joint.origin.xy+vec2(float(col)*joint.dimensions.z+stagger,
                                float(row)*joint.dimensions.w);
}
vec2 wall04_brick_xy_scale() {
    return vec2((joint.dimensions.z-WALL04_VISIBLE_JOINT_M)/joint.dimensions.x,
                (joint.dimensions.w-WALL04_VISIBLE_JOINT_M)/joint.dimensions.y);
}
vec2 wall04_expanded_xy(vec2 xy, uint node) {
    vec2 center=wall04_brick_center(node);
    return center+(xy-center)*wall04_brick_xy_scale();
}
vec2 wall04_unexpanded_xy(vec2 xy, uint node) {
    vec2 center=wall04_brick_center(node);
    return center+(xy-center)/wall04_brick_xy_scale();
}


layout(set=0,binding=17,std430) readonly buffer SampleReferences { uint values[]; } sample_refs;

struct Recovery { uvec4 info; vec4 coefficients[9]; };


const uint MAX_RECOVERY=65536u;
// A virtual sample is reconstructed from ONE original immutable brick master.
// Per-instance transforms, source subset IDs and tint recreate the old WALL04
// records; photo mortar records are copied unchanged. No original mesh draws.
Sample fetch_sample(uint sid, Instance inst) {
    Sample s=samples.v[sid];
    uint brick=uint(inst.meta.x)/128u;
    if(brick<96u) {
        vec3 n=s.normal_gray.xyz,p=s.position_radius.xyz;
        vec3 an=abs(n);
        uint patch_id=an.x>=an.y && an.x>=an.z ? (n.x>=0?0u:1u) :
                   an.y>=an.z ? (n.y>=0?2u:3u) :
                   n.z<0?4u:5u+uint(p.x>=0)+2u*uint(p.y>=0);
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
        p=basis*p+inst.origin.xyz;n=basis*n;
        s.position_radius=vec4(p,max(s.position_radius.w,inst.meta.z));
        s.normal_gray.xyz=n;s.attributes.y=float(brick*9u+patch_id);s.attributes.w=0.;
        s.albedo.rgb=clamp(s.albedo.rgb*inst.tint.rgb,vec3(0),vec3(1));
        an=abs(n);vec2 q=an.x>=an.y && an.x>=an.z?p.zy:an.y>=an.z?p.xz:p.xy;
        float r=2.*s.position_radius.w;s.support=vec4(q-r,q+r);
    }
    return s;
}
Instance render_instance(Instance inst) {
    inst.x=vec4(1,0,0,0);inst.y=vec4(0,1,0,0);inst.z=vec4(0,0,1,0);
    inst.origin=vec4(0);inst.tint.rgb=vec3(1);return inst;
}

layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;





// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.





vec2 project(vec3 p,vec3 eye,vec3 right,vec3 up,vec3 forward,float tangent,vec2 size) {
    vec3 d=p-eye;float z=dot(d,forward);
    return vec2((dot(d,right)/(z*tangent)+1)*.5,(1-dot(d,up)/(z*tangent))*.5)*size;
}
bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}
float footprint_distance(Projection p,vec2 xy) {
    vec2 q=xy-p.screen.xy;
    return q.x*q.x*p.ellipse.x+2*q.x*q.y*p.ellipse.y+q.y*q.y*p.ellipse.z;
}
bool covered(Projection p,vec2 xy) {
    if(footprint_distance(p,xy)>1) return false;
    vec2 uv=xy/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
    vec3 local=parameters.eye.xyz+ray*pixel_depth(p,xy);
    if(p.gradient.z<96.) local.xy=wall04_unexpanded_xy(local.xy,uint(p.gradient.z)*9u);
    int axis=int(p.ellipse.w);vec2 q=axis==0?local.zy:axis==1?local.xz:local.xy;
    return all(greaterThanEqual(q,p.geometry.xy-vec2(.000002))) && all(lessThanEqual(q,p.geometry.zw+vec2(.000002)));
}





uint job_index(uint invocation) {
    uint lo=0u,hi=uint(parameters.counts.y);
    while(lo+1u<hi) {uint mid=(lo+hi)/2u;if(jobs.v[mid].w<=invocation)lo=mid;else hi=mid;}
    return lo;
}
uint hash(uint x) {x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float variation(uint id) {return float(hash(id+uint(parameters.settings.x))&65535u)/65535.0;}
vec3 material_color(Sample s,Instance inst) {
    uint id=uint(max(inst.meta.x,0))+uint(max(s.attributes.y,0));
    float v=(variation(id)-.5)*parameters.wall.w;
    return clamp(s.albedo.rgb*inst.tint.rgb*(1+v),vec3(0),vec3(1));
}

// WALL04 has no analytic flat-plane mortar. Every mortar pixel must be
// depth-tested from a PHOTO-CAPTURED source sample in the original stage 2/3.
// The single 6-face invisible spatial envelope is NEVER a visible surface.




// 32 bytes per accepted recovery record instead of a full-frame world atlas.
struct RecoverySurface {vec4 world;vec4 normal;};





// Bounded screen-space contact test. The host supplies projection and a REAL
// observed tangent plane per pixel; recovered holes never become occluders.
// The plane is bounded by its observed pixel cell, not an infinite surface or
// a guessed solid thickness. Missing/off-screen geometry contributes no shadow.

// Same point-source units, distance floor, range window and normalized power
// as the finite-patch field. No second emitter budget and no invented relief.
// Relative total RGB power: an isotropic point has gain 1. A one-sided
// Lambert emitter has intensity Phi*cos(theta)/PI, hence gain 4*cos.



// Finite-patch visibility/transmittance gates the local direct response.
// Contact-only mode cannot brighten. Detail mode redistributes direct light
// locally; its image-space integral is not a certified finite-area quadrature.






layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;


// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};




// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.



// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.










// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.
layout(set=0,binding=29,std430) readonly buffer SourceBlocks {uvec2 values[];} source_blocks;











layout(set=0,binding=32,std430) buffer AppearanceControl {uint words[];} appearance_control;
// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.




// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.
ivec2 lie_splat_row(Projection p,ivec2 center,int y,int bound) {
    float dy=float(y)+.5-p.screen.y;
    float A=p.ellipse.x,B=p.ellipse.y,C=p.ellipse.z;
    float cross_section=1.-(C-B*B/A)*dy*dy;
    if(A<=0. || isnan(cross_section) || isinf(cross_section))return ivec2(center.x-bound,center.x+bound);
    // A one-pixel guard on both ends preserves floating-point boundary cases.
    // Even a slightly negative section receives a conservative candidate.
    float span=sqrt(max(cross_section,0.)/A);
    float middle=p.screen.x-B*dy/A-.5;
    return ivec2(max(center.x-bound,int(floor(middle-span))-1),
                 min(center.x+bound,int(ceil(middle+span))+1));
}


// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};









void lie_query_geometry(Sample s,Instance inst,out vec3 world,out vec3 n,out float radius) {
            mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
            vec3 local=s.position_radius.xyz;radius=s.position_radius.w;
            uint source_node=uint(max(round(s.attributes.y),0.0));
            bool source_brick=source_node<864u;
            if(source_brick) {
                local.xy=wall04_expanded_xy(local.xy,source_node);
                vec2 scale=wall04_brick_xy_scale();
                radius*=max(scale.x,scale.y);
            }
            if(parameters.settings.y<.5) {
                float r=length(local.xy),inner=.0017,outer=.006;
                if(int(s.attributes.x)==1 && r>1e-8) {
                    float nr=parameters.iris.w+(r-inner)*(outer-parameters.iris.w)/(outer-inner);
                    local.xy*=nr/r;radius*=max(nr/r,(outer-parameters.iris.w)/(outer-inner));
                } else if(int(s.attributes.x)==2) {local.xy*=parameters.iris.w/inner;radius*=parameters.iris.w/inner;}
            }
            world=basis*local+inst.origin.xyz;
            vec3 source_normal=s.normal_gray.xyz;
            if(source_brick) source_normal.xy/=wall04_brick_xy_scale();
            n=normalize(transpose(inverse(basis))*source_normal);
            radius*=max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
}
// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.
layout(set=0,binding=36,std430) buffer QueryArena {uint words[];} query_arena;








void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=2;

        uint j;
        if(phase.value.w<0) {
            uint group=gl_WorkGroupID.x;
            uvec2 block=source_blocks.values[query_arena.words[4u+group]];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else if(phase.value.w>0) {
            uint group=gl_WorkGroupID.x+gl_WorkGroupID.y*gl_NumWorkGroups.x;
            uvec2 block=source_blocks.values[uint(phase.value.w)-1u+group];j=block.x;
            uint local=block.y+gl_LocalInvocationID.x;
            if(local>=jobs.v[j].y)return;
            i=jobs.v[j].w+local;
        } else {if(i>=uint(parameters.counts.x))return;j=job_index(i);}
        uvec4 job=jobs.v[j];uint reference_index=job.x+i-job.w;
        uint sid=sample_refs.values[reference_index];
        Sample s;Instance inst;Projection p;
        if(stage==2) {
            Instance source_inst=instances.v[job.z];s=fetch_sample(sid,source_inst);inst=render_instance(source_inst);
            vec3 world,n;float radius;lie_query_geometry(s,inst,world,n,radius);
            uint source_node=uint(max(round(s.attributes.y),0.0));
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(n,normalize(-delta));
            p.world=vec4(world,float(source_node));p.normal=vec4(n,float(reference_index));p.screen=vec4(0);p.gradient=vec4(0,0,float(job.z),float(sid));p.geometry=s.support;
            vec3 support_normal=abs(s.normal_gray.xyz);
            float support_axis=support_normal.x>=support_normal.y && support_normal.x>=support_normal.z?0.:support_normal.y>=support_normal.z?1.:2.;
            p.ellipse=vec4(0,0,0,support_axis);
            // Source light energy, blocker visibility and indirect generations
            // are handled by ORIGINAL LIE11 PRE_OPAQUE transport on the GPU.
            // Do not rebuild LIE33's obsolete shadow map a second time.
            if(depth>parameters.lens.z && depth<parameters.lens.w && front>.015) {
                vec2 xy=project(world,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw));
                vec3 tangent=normalize(cross(n,abs(n.y)<.9?vec3(0,1,0):vec3(1,0,0)));vec3 bitangent=cross(n,tangent);
                vec2 u=project(world+tangent*radius,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                vec2 v=project(world+bitangent*radius,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                float xx=dot(vec2(u.x,v.x),vec2(u.x,v.x))+.20,yy=dot(vec2(u.y,v.y),vec2(u.y,v.y))+.20,off=u.x*u.y+v.x*v.y,det=max(xx*yy-off*off,1e-8);
                p.ellipse=vec4(yy/det,-off/det,xx/det,p.ellipse.w);p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,8));
                float plane=dot(n,delta);if(abs(plane)>1e-8)p.gradient.xy=vec2(2*parameters.lens.x*dot(n,parameters.right.xyz)/float(parameters.counts.z),-2*parameters.lens.x*dot(n,parameters.up.xyz)/float(parameters.counts.w))/plane;
            }
            projected.v[i]=p;
        }else p=projected.v[i];
        if(p.screen.z<=0)return;
        int bound=int(ceil(p.screen.w));
        ivec2 center=ivec2(floor(p.screen.xy));
        bool tight=appearance_control.words[1]!=0u;
        if(tight && (center.x+bound<0 || center.y+bound<0 || center.x-bound>=parameters.counts.z || center.y-bound>=parameters.counts.w))return;
        if(stage==3) {Instance source_inst=instances.v[job.z];s=fetch_sample(sid,source_inst);inst=render_instance(source_inst);}
        vec3 sample_color=stage==3?material_color(s,inst):vec3(0);
        float sample_rough=stage==3?clamp(s.attributes.z+inst.tint.w,.2,.95):0.;
        if(stage==3 && (int(s.attributes.x)==3 || int(s.attributes.x)==6)) {
            uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));
            sample_rough=clamp(sample_rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);
        }
        uint candidates=0u;
        int ymin=center.y-bound,ymax=center.y+bound;
        if(tight){ymin=max(ymin,0);ymax=min(ymax,parameters.counts.w-1);}
        for(int y=ymin;y<=ymax;y++) {
          ivec2 interval=tight?lie_splat_row(p,center,y,bound):ivec2(center.x-bound,center.x+bound);
          if(tight){interval.x=max(interval.x,0);interval.y=min(interval.y,parameters.counts.z-1);}
          for(int x=interval.x;x<=interval.y;x++) {
            candidates++;
            ivec2 q=ivec2(x,y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;
            float z=pixel_depth(p,vec2(q)+.5);if(z<=parameters.lens.z||isnan(z)||isinf(z))continue;
            uint pixel=uint(q.y*parameters.counts.z+q.x),bits=floatBitsToUint(z);
            if(stage==2)atomicMin(depths.v[pixel],bits);
            else {
                if(depths.v[pixel]==bits) {atomicMin(winners.v[pixel],i);atomicOr(source_visibility.values[i].y,0x80000000u);}
                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;
                uint w=max(uint(round(256*exp(-2*footprint_distance(p,vec2(q)+.5)))),1u);
                uvec3 c=uvec3(round(sample_color*float(w))),n=uvec3(round((p.normal.xyz*.5+.5)*float(w)));
                atomicAdd(accumulated.v[pixel].color_weight.x,c.x);atomicAdd(accumulated.v[pixel].color_weight.y,c.y);atomicAdd(accumulated.v[pixel].color_weight.z,c.z);atomicAdd(accumulated.v[pixel].color_weight.w,w);
                atomicAdd(accumulated.v[pixel].normal_roughness.x,n.x);atomicAdd(accumulated.v[pixel].normal_roughness.y,n.y);atomicAdd(accumulated.v[pixel].normal_roughness.z,n.z);
                atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(sample_rough*float(w))));
            }
          }
        }
        if(appearance_control.words[12]!=0u) {
            atomicAdd(appearance_control.words[stage==2?4u:5u],candidates);
            atomicAdd(appearance_control.words[stage==2?6u:7u],1u);
        }
        return;
    
}
