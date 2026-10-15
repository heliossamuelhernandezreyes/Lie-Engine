#[compute]
#version 450
// GENERATED dedicated stage 18; tools/lie_wall17_shader.py
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



layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;






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









// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};




// Conservative broad phase with a per-ray reciprocal. Primitive intersections
// and their order remain unchanged. Padding can only admit extra BVH nodes.



// A hint is evidence only after retesting the ORIGINAL disk against this ray.
// Encoding: 10-bit scene instance and 22-bit (source ID + 1), zero = absent.
// Out-of-capacity IDs simply use the full traversal. No clear-ray certificate.
layout(set=0,binding=39,std430) buffer QueryMemory {uint words[];} query_memory;









// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.
layout(set=0,binding=29,std430) readonly buffer SourceBlocks {uvec2 values[];} source_blocks;












// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.




// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.



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

void lie_query_store(uint i,vec4 value){uint at=query_memory.words[6]+i*4u;uvec4 v=floatBitsToUint(value);for(uint k=0u;k<4u;k++)query_arena.words[at+k]=v[k];}
shared vec3 query_positions[64];
shared vec3 query_normals[64];

void lie_query_build(uint group,uint lane) {
    uvec2 block=source_blocks.values[query_memory.words[5]+group];uvec4 job=jobs.v[block.x];
    uint local=block.y+lane;vec3 point=vec3(0),normal=vec3(0);
    if(local<job.y) {
        uint sid=sample_refs.values[job.x+local];Instance source_inst=instances.v[job.z];
        Sample s=fetch_sample(sid,source_inst);Instance inst=render_instance(source_inst);float radius;
        lie_query_geometry(s,inst,point,normal,radius);
    }
    query_positions[lane]=point;query_normals[lane]=normal;barrier();
    if(lane==0u) {
        vec3 low=vec3(3.402823e38),high=-low,nlow=low,nhigh=-low;
        uint count=min(64u,job.y-block.y);
        for(uint k=0u;k<count;k++){low=min(low,query_positions[k]);high=max(high,query_positions[k]);nlow=min(nlow,query_normals[k]);nhigh=max(nhigh,query_normals[k]);}
        lie_query_store(group*4u,vec4(low,0));lie_query_store(group*4u+1u,vec4(high,0));
        lie_query_store(group*4u+2u,vec4(nlow,0));lie_query_store(group*4u+3u,vec4(nhigh,0));
    }
}




void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=18;
lie_query_build(gl_WorkGroupID.x,gl_LocalInvocationID.x);return;
}
