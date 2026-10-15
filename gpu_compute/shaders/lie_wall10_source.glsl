#[compute]
#version 450
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
layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;
layout(rgba32f,set=0,binding=12) uniform image2D final_image;
layout(set=0,binding=13,std430) buffer Shadow { uint v[]; } shadow;
/* LIGHT CODE SOURCE: output of LIE11's genuine GPU transport, not a
   second ad-hoc point light or baked ambient. 1 texel per finite patch. */
layout(rgba32f,set=0,binding=14) uniform readonly image2D injected_node_irradiance;
layout(set=0,binding=15,std430) readonly buffer InjectedMaterialCodes {
    vec4 values[];
} injected_material_codes;
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
layout(set=0,binding=18,std430) buffer RecoveryMap { uint values[]; } recovery_map;
struct Recovery { uvec4 info; vec4 coefficients[9]; };
layout(set=0,binding=19,std430) buffer RecoveryRecords { Recovery values[]; } recovery;
layout(set=0,binding=20,std430) buffer RecoveryCount { uint count; uint overflow; uint reserved_a; uint reserved_b; } recovery_count;
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
uint projection_node(Projection p) {
    return uint(round(p.world.w));
}
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;
layout(set=0,binding=21,std430) readonly buffer LightGroups { uvec4 header; uvec4 entries[]; } light_groups;
uvec2 lie_group(uint node) {return light_groups.header.x==0u?uvec2(node,1):light_groups.entries[node].xy;}
vec3 lie_position(uint node) {return injected_material_codes.values[node*3u].xyz;}
vec3 lie_normal(uint node) {return injected_material_codes.values[node*3u+1u].xyz;}
float lie_area(uint node) {return injected_material_codes.values[node*3u].w;}
// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.
float lie_stencil_weight(vec3 world,uint reference,uint candidate) {
    vec3 normal=normalize(lie_normal(reference));
    float agreement=dot(normal,normalize(lie_normal(candidate)));
    if(agreement<.9)return 0.;
    vec3 delta=world-lie_position(candidate);delta-=normal*dot(delta,normal);
    float alignment=max((agreement-.9)/.1,0.);
    return alignment*alignment/(dot(delta,delta)+max(lie_area(reference)*1e-4,1e-12));
}
float lie_stencil_sum(vec3 world,uint node) {
    uvec2 group=lie_group(node);float total=0.;
    for(uint k=0u;k<group.y;k++)total+=lie_stencil_weight(world,node,group.x+k);
    return total;
}

vec3 lie_irradiance_code(Projection point) {
    uint node=projection_node(point);uvec2 group=lie_group(node);
    vec3 total=vec3(0);float sum=group.y==1u?1.:lie_stencil_sum(point.world.xyz,node);
    for(uint k=0u;k<group.y;k++) {
        uint candidate=group.x+k;
        float w=group.y==1u?1.:lie_stencil_weight(point.world.xyz,node,candidate)/max(sum,1e-30);
        vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(candidate),0)).rgb,vec3(0));
        float absorption=clamp(injected_material_codes.values[candidate*3u+2u].w,0.,1.);
        total+=w*E*(1.-absorption)/PI;
    }
    return total;
}

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

float lambda(float cosine,float a2) {
    return .5*(sqrt(1+a2*max(1-cosine*cosine,0)/max(cosine*cosine,1e-8))-1);
}
float visibility(vec3 p,vec3 geometric_normal) {
    vec3 d=p-parameters.light.xyz;float z=dot(d,parameters.shadow_forward.xyz);
    if(z<=.001) return 1;
    vec2 uv=project(p,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
    if(any(lessThan(uv,vec2(1))) || any(greaterThan(uv,vec2(SHADOW_SIZE-2)))) return 1;
    float receiver_plane=dot(geometric_normal,d);
    if(abs(receiver_plane)<1e-7) return 1;
    vec2 gradient=vec2(2*1.25*dot(geometric_normal,parameters.shadow_right.xyz),-2*1.25*dot(geometric_normal,parameters.shadow_up.xyz))/(float(SHADOW_SIZE)*receiver_plane);
    float result=0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        ivec2 q=clamp(ivec2(uv)+ivec2(x,y),ivec2(0),ivec2(SHADOW_SIZE-1));
        float stored=uintBitsToFloat(shadow.v[q.y*SHADOW_SIZE+q.x]);
        // PCF taps refer to different rays. The receiver depth must follow
        // its plane at each tap; a constant center depth creates bands.
        float receiver_depth=1.0/(1.0/z+dot(gradient,vec2(q)+.5-uv));
        result+=(receiver_depth<=0 || receiver_depth<=stored+parameters.options.z)?1.0:0.0;
    }
    return result/9;
}
vec3 to_srgb(vec3 p) {
    return mix(p*12.92,1.055*pow(max(p,vec3(0)),vec3(1.0/2.4))-.055,greaterThan(p,vec3(.0031308)));
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


layout(set=0,binding=22,std430) readonly buffer SurfaceOptions { uvec4 flags; vec4 metric; } surface_options;
layout(set=0,binding=23,std430) readonly buffer SurfaceLights { uvec4 header; vec4 values[]; } surface_lights;
// 32 bytes per accepted recovery record instead of a full-frame world atlas.
struct RecoverySurface {vec4 world;vec4 normal;};
layout(set=0,binding=24,std430) buffer RecoverySurfaces { RecoverySurface values[]; } recovery_surfaces;
vec3 lie_surface_ray(vec2 screen) {
    vec2 uv=screen/vec2(parameters.counts.zw);
    return parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+
        parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
}
vec3 lie_surface_world(Projection p,vec2 screen) {
    return parameters.eye.xyz+lie_surface_ray(screen)*pixel_depth(p,screen);
}
vec2 lie_surface_project(vec3 world) {
    vec3 d=world-parameters.eye.xyz;float z=dot(d,parameters.forward.xyz);
    if(z<=parameters.lens.z)return vec2(-1e9);
    vec2 uv=vec2(dot(d,parameters.right.xyz),-dot(d,parameters.up.xyz))/(z*parameters.lens.x);
    return (uv*.5+.5)*vec2(parameters.counts.zw);
}
bool lie_surface_observed(ivec2 q,out vec3 point,out vec3 normal) {
    if(!inside(q))return false;
    uint owner=winners.v[uint(q.y*parameters.counts.z+q.x)];
    if(owner==EMPTY)return false;
    Projection p=projected.v[owner];point=lie_surface_world(p,vec2(q)+.5);
    normal=normalize(p.normal.xyz);return true;
}
// Bounded screen-space contact test. The host supplies projection and a REAL
// observed tangent plane per pixel; recovered holes never become occluders.
// The plane is bounded by its observed pixel cell, not an infinite surface or
// a guessed solid thickness. Missing/off-screen geometry contributes no shadow.
float lie_contact_visibility(vec3 world,vec3 normal,vec3 light,float reach,float bias,int steps) {
    vec3 delta=light-world;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 direction=delta/distance_to_light;
    vec3 origin=world+normal*bias;
    float limit=min(reach,distance_to_light-bias);
    if(limit<=bias)return 1.;
    float visibility=1.;
    for(int k=0;k<32;k++) {
        if(k>=steps)break;
        float t=limit*(float(k)+.5)/float(steps);
        vec2 screen=lie_surface_project(origin+direction*t);
        ivec2 q=ivec2(floor(screen));vec3 point,plane_normal;
        if(!lie_surface_observed(q,point,plane_normal))continue;
        float denominator=dot(plane_normal,direction);
        if(abs(denominator)<1e-6)continue;
        float hit=dot(plane_normal,point-origin)/denominator;
        if(hit<=bias || hit>=limit)continue;
        vec2 hit_screen=lie_surface_project(origin+direction*hit);
        if(any(lessThan(hit_screen,vec2(q))) || any(greaterThanEqual(hit_screen,vec2(q)+1.)))continue;
        // Fade only near the metric traversal limit; direct-only attenuation.
        visibility=min(visibility,smoothstep(.75*limit,limit,hit));
        if(visibility<=0.)break;
    }
    return clamp(visibility,0.,1.);
}
// Same point-source units, distance floor, range window and normalized power
// as the finite-patch field. No second emitter budget and no invented relief.
vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {
    vec4 source=surface_lights.values[l*2u],power=surface_lights.values[l*2u+1u];
    vec3 delta=source.xyz-world;float d2=dot(delta,delta);
    if(d2<=1e-10 || source.w<=0.)return vec3(0);
    float cosine=max(dot(normal,delta*inversesqrt(d2)),0.);
    float fade=pow(max(0.,1.-pow(sqrt(d2)/source.w,4.)),2.);
    return power.rgb*(cosine*fade/(4.*PI*max(d2,power.w)));
}
// Finite-patch visibility/transmittance gates the local direct response.
// Contact-only mode cannot brighten. Detail mode redistributes direct light
// locally; its image-space integral is not a certified finite-area quadrature.
vec3 lie_surface_refined(vec3 old_direct,vec3 unoccluded,
                        vec3 coefficient,vec3 local_direct,float visibility,bool detail) {
    vec3 gate=vec3(0);
    for(int c=0;c<3;c++)if(unoccluded[c]>1e-20)gate[c]=clamp(old_direct[c]/unoccluded[c],0.,1.);
    vec3 direct=detail?coefficient*local_direct*gate:old_direct;
    return direct*visibility;
}


layout(set=0,binding=25,std430) readonly buffer SourceBLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=26,std430) readonly buffer SourceLeaves {uint values[];} lie_visibility_refs;
layout(set=0,binding=27,std430) readonly buffer SourceScene {uint values[];} lie_visibility_scene;
layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;
vec4 lie_visibility_position_radius(uint sid) {return samples.v[sid].position_radius;}
vec3 lie_visibility_normal(uint sid) {return samples.v[sid].normal_gray.xyz;}
// Camera-independent queries against captured tangent disks. Bounds accelerate
// queries only; they never become opaque geometry or additional colliders.
// Host supplies source position/radius + normal accessors and the three SSBOs.
struct LieSourceNode {vec4 lo;vec4 hi;};
LieSourceNode lie_blas_node(uint i) {
    LieSourceNode n;n.lo=lie_visibility_blas.values[i*2u];n.hi=lie_visibility_blas.values[i*2u+1u];return n;
}
vec4 lie_scene_vec(uint at) {
    return uintBitsToFloat(uvec4(lie_visibility_scene.values[at],lie_visibility_scene.values[at+1u],lie_visibility_scene.values[at+2u],lie_visibility_scene.values[at+3u]));
}
LieSourceNode lie_scene_node(uint i) {
    LieSourceNode n;n.lo=lie_scene_vec(4u+i*8u);n.hi=lie_scene_vec(8u+i*8u);return n;
}
bool lie_source_box(vec3 o,vec3 d,vec3 low,vec3 high,float minimum,float maximum) {
    float enter=minimum,leave=maximum;
    for(int k=0;k<3;k++) {
        if(abs(d[k])<1e-12) {if(o[k]<low[k] || o[k]>high[k])return false;}
        else {float a=(low[k]-o[k])/d[k],b=(high[k]-o[k])/d[k];enter=max(enter,min(a,b));leave=min(leave,max(a,b));}
    }
    return enter<=leave;
}
float lie_source_trace(vec3 o,vec3 d,float minimum,float maximum,float early,uint root,uint skip) {
    uint end=floatBitsToUint(lie_blas_node(root).lo.w),i=root;
    float nearest=maximum;
    while(i<end) {
        LieSourceNode n=lie_blas_node(i);uint escape=floatBitsToUint(n.lo.w),leaf=floatBitsToUint(n.hi.w);
        if(!lie_source_box(o,d,n.lo.xyz,n.hi.xyz,minimum,nearest)){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint count=lie_visibility_refs.values[leaf];
        for(uint k=0u;k<count;k++) {
            uint sid=lie_visibility_refs.values[leaf+1u+k];if(sid==skip)continue;
            vec4 source=lie_visibility_position_radius(sid);vec3 normal=lie_visibility_normal(sid);
            float denominator=dot(normal,d);if(abs(denominator)<1e-8)continue;
            float t=dot(normal,source.xyz-o)/denominator;if(t<=minimum || t>=nearest)continue;
            vec3 delta=o+t*d-source.xyz;
            if(dot(delta,delta)>source.w*source.w)continue;
            nearest=t;if(nearest<=early)return nearest;
        }
        i=escape;
    }
    return nearest;
}
float lie_source_world_visibility(vec3 point,vec3 normal,vec3 light,float reach,float bias,uint owner,uint source_id) {
    vec3 delta=light-point;float distance_to_light=length(delta);
    if(distance_to_light<=bias || dot(normal,delta)<=0.)return 1.;
    vec3 o=point+normal*bias,d=delta/distance_to_light;
    float limit=min(reach,distance_to_light-bias),nearest=limit;
    if(limit<=bias)return 1.;
    uint i=0u,end=lie_visibility_scene.values[0];
    while(i<end) {
        LieSourceNode node=lie_scene_node(i);uint escape=floatBitsToUint(node.lo.w),leaf=floatBitsToUint(node.hi.w);
        if(!lie_source_box(o,d,node.lo.xyz,node.hi.xyz,bias,nearest)){i=escape;continue;}
        if(leaf==0xffffffffu){i++;continue;}
        uint list=lie_visibility_scene.values[1]+leaf,count=lie_visibility_scene.values[list];
        for(uint k=0u;k<count;k++) {
            uint instance=lie_visibility_scene.values[list+1u+k];uint at=lie_visibility_scene.values[2]+instance*16u;
            vec4 x=lie_scene_vec(at),y=lie_scene_vec(at+4u),z=lie_scene_vec(at+8u);
            vec3 local_o=vec3(dot(x,vec4(o,1)),dot(y,vec4(o,1)),dot(z,vec4(o,1)));
            vec3 local_d=vec3(dot(x.xyz,d),dot(y.xyz,d),dot(z.xyz,d));
            uint root=lie_visibility_scene.values[at+12u];
            nearest=lie_source_trace(local_o,local_d,bias,nearest,.75*limit,root,instance==owner?source_id:0xffffffffu);
            if(nearest<=.75*limit)return 0.;
        }
        i=escape;
    }
    return smoothstep(.75*limit,limit,nearest);
}

float lie_cached_source_visibility(uint projection,uint light) {
    uvec2 bits=source_visibility.values[projection];
    if(light<4u)return float((bits.x>>(light*8u))&255u)/255.;
    uint shift=(light-4u)*8u,mask=light==7u?127u:255u;
    return float((bits.y>>shift)&mask)/float(mask);
}
void lie_build_source_visibility(uint i) {
    if(i>=uint(parameters.counts.x))return;
    uvec2 bits=source_visibility.values[i];if((bits.y&0x80000000u)==0u)return;
    bits=uvec2(0xffffffffu);
    if(surface_options.flags.x!=0u && surface_options.flags.w!=0u) {
        Projection p=projected.v[i];
        for(uint l=0u;l<surface_lights.header.y;l++) {
            vec3 power=surface_lights.values[l*2u+1u].rgb;float visibility=1.;
            if(max(power.r,max(power.g,power.b))>0.)
                visibility=lie_source_world_visibility(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[l*2u].xyz,
                    surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)));
            uint mask=l==7u?127u:255u,shift=(l%4u)*8u;
            uint value=uint(round(clamp(visibility,0.,1.)*float(mask)));
            if(l<4u)bits.x=(bits.x&~(mask<<shift))|(value<<shift);
            else bits.y=(bits.y&~(mask<<shift))|(value<<shift);
        }
    }
    // Top bit is a persistent winner marker, surviving light-only changes.
    source_visibility.values[i]=bits;
}

void lie_resolve_surface(uint i) {
    if(i>=uint(parameters.counts.z*parameters.counts.w))return;
    if(surface_options.flags.x==0u && surface_options.flags.y==0u)return;
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    vec4 base=imageLoad(specular_image,q);if(base.a<.5)return;
    uint owner=winners.v[i],slot=recovery_map.values[i];
    uint source_projection=owner;
    vec3 world,normal;vec3 coefficients[9];for(int k=0;k<9;k++)coefficients[k]=vec3(0);
    uvec2 group;
    if(owner!=EMPTY) {
        Projection p=projected.v[owner];uint node=projection_node(p);group=lie_group(node);
        world=lie_surface_world(p,vec2(q)+.5);normal=normalize(p.normal.xyz);
        Accumulator acc=accumulated.v[i];
        vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);
        vec3 mean_normal=vec3(acc.normal_roughness.xyz)/max(float(acc.color_weight.w),1.)*2.-1.;
        if(dot(mean_normal,mean_normal)>1e-8 && dot(normalize(mean_normal),normal)>.9)normal=normalize(mean_normal);
        float sum=group.y==1u?1.:lie_stencil_sum(p.world.xyz,node);
        for(uint k=0u;k<group.y;k++) {
            float w=group.y==1u?1.:lie_stencil_weight(p.world.xyz,node,group.x+k)/max(sum,1e-30);
            coefficients[k]=albedo*(w/PI);
        }
    } else {
        // An overflow/unwitnessed hole stays on the accepted baseline path.
        if(slot==EMPTY || slot==0u || slot>MAX_RECOVERY)return;
        Recovery record=recovery.values[slot-1u];group=record.info.xy;
        RecoverySurface surface=recovery_surfaces.values[slot-1u];
        world=surface.world.xyz;normal=surface.normal.xyz;source_projection=uint(surface.normal.w)-1u;
        for(uint k=0u;k<group.y;k++)coefficients[k]=record.coefficients[k].rgb;
    }
    vec3 coefficient=vec3(0);
    for(uint k=0u;k<group.y;k++) {
        float absorption=clamp(injected_material_codes.values[(group.x+k)*3u+2u].w,0.,1.);
        coefficients[k]*=1.-absorption;coefficient+=coefficients[k];
    }
    vec3 old_total=vec3(0),new_total=vec3(0);
    for(uint l=0u;l<surface_lights.header.y;l++) {
        if(max(surface_lights.values[l*2u+1u].r,max(surface_lights.values[l*2u+1u].g,surface_lights.values[l*2u+1u].b))<=0.)continue;
        vec3 old_direct=vec3(0),unoccluded=vec3(0);
        for(uint k=0u;k<group.y;k++) {
            if(max(coefficients[k].r,max(coefficients[k].g,coefficients[k].b))<=0.)continue;
            uint node=group.x+k;
            old_direct+=coefficients[k]*surface_lights.values[16u+l*surface_lights.header.x+node].rgb;
            unoccluded+=coefficients[k]*lie_surface_unoccluded(l,lie_position(node),lie_normal(node));
        }
        float visibility=1.;
        if(surface_options.flags.x!=0u && max(old_direct.r,max(old_direct.g,old_direct.b))>0.) {
            if(surface_options.flags.w!=0u)visibility=lie_cached_source_visibility(source_projection,l);
            else visibility=lie_contact_visibility(world,normal,surface_lights.values[l*2u].xyz,
                surface_options.metric.x,surface_options.metric.y,int(surface_options.flags.z));
        }
        vec3 local_direct=lie_surface_unoccluded(l,world,normal);
        old_total+=old_direct;
        new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);
    }
    imageStore(specular_image,q,vec4(max(base.rgb-old_total,vec3(0))+new_total,base.a));
}

void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    int stage=phase.value.x;
    if(stage==10) {lie_resolve_surface(i);return;}
    if(stage==11) {lie_build_source_visibility(i);return;}
    if(stage==1) {
        if(i<uint(parameters.counts.x))source_visibility.values[i]=uvec2(0);
        if(i==0u) {recovery_count.count=0u;recovery_count.overflow=0u;}
        if(i<pixels) {recovery_map.values[i]=0u;depths.v[i]=0x7f7fffffu;winners.v[i]=EMPTY;accumulated.v[i].color_weight=uvec4(0);accumulated.v[i].normal_roughness=uvec4(0);}
        if(i<uint(SHADOW_SIZE*SHADOW_SIZE))shadow.v[i]=0x7f7fffffu;return;
    }
    if(stage==2 || stage==3) {
        if(i>=uint(parameters.counts.x))return;
        uint j=job_index(i);uvec4 job=jobs.v[j];uint sid=sample_refs.values[job.x+i-job.w];
        Instance source_inst=instances.v[job.z];Sample s=fetch_sample(sid,source_inst);Instance inst=render_instance(source_inst);
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
        Projection p;
        if(stage==2) {
            vec3 local=s.position_radius.xyz;float radius=s.position_radius.w;
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
            vec3 world=basis*local+inst.origin.xyz;
            vec3 source_normal=s.normal_gray.xyz;
            if(source_brick) source_normal.xy/=wall04_brick_xy_scale();
            vec3 n=normalize(transpose(inverse(basis))*source_normal);
            radius*=max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(n,normalize(-delta));
            p.world=vec4(world,float(source_node));p.normal=vec4(n,front);p.screen=vec4(0);p.gradient=vec4(0,0,float(job.z),float(sid));p.geometry=s.support;
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
        for(int y=-bound;y<=bound;y++)for(int x=-bound;x<=bound;x++) {
            ivec2 q=ivec2(floor(p.screen.xy))+ivec2(x,y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;
            float z=pixel_depth(p,vec2(q)+.5);if(z<=parameters.lens.z||isnan(z)||isinf(z))continue;
            uint pixel=uint(q.y*parameters.counts.z+q.x),bits=floatBitsToUint(z);
            if(stage==2)atomicMin(depths.v[pixel],bits);
            else {
                if(depths.v[pixel]==bits) {atomicMin(winners.v[pixel],i);atomicOr(source_visibility.values[i].y,0x80000000u);}
                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;
                uint w=max(uint(round(256*exp(-2*footprint_distance(p,vec2(q)+.5)))),1u);
                uvec3 c=uvec3(round(material_color(s,inst)*float(w))),n=uvec3(round((p.normal.xyz*.5+.5)*float(w)));
                atomicAdd(accumulated.v[pixel].color_weight.x,c.x);atomicAdd(accumulated.v[pixel].color_weight.y,c.y);atomicAdd(accumulated.v[pixel].color_weight.z,c.z);atomicAdd(accumulated.v[pixel].color_weight.w,w);
                atomicAdd(accumulated.v[pixel].normal_roughness.x,n.x);atomicAdd(accumulated.v[pixel].normal_roughness.y,n.y);atomicAdd(accumulated.v[pixel].normal_roughness.z,n.z);float rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
                if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);}
                atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(rough*float(w))));
            }
        }return;
    }
    if(stage==8 || stage==9) {
        // LIE-WALL04, after stage 6. GPU hole recovery within photographed-source support:
        // original brick neighborhoods or enclosed source-mortar joints. 4.6M internal pixels, with expensive
        // searches limited to invalid pixels. No new triangles/mesh/texture.
        // specular_image is reused as a scratch image AFTER stage 6 has read
        // the specular term. Stage 7 will read this scratch image.
        if(i>=uint(parameters.counts.z*parameters.counts.w)) return;
        ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
        vec4 base=imageLoad(output_image,q);
        if(base.a>.5) {
            imageStore(specular_image,q,base);
            return;
        }
        // Re-light already validated holes without searching source neighborhoods.
        if(stage==9 && recovery_map.values[i]!=EMPTY) {
            uint slot=recovery_map.values[i];
            if(slot==0u) {imageStore(specular_image,q,base);return;}
            Recovery record=recovery.values[slot-1u];
            vec3 rgb=vec3(0);uint node_base=record.info.x;
            for(uint k=0u;k<record.info.y;k++) {
                uint node=node_base+k;
                vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(node),0)).rgb,vec3(0));
                float absorption=clamp(injected_material_codes.values[node*3u+2u].w,0.,1.);
                rgb+=record.coefficients[k].rgb*E*(1.-absorption);
            }
            imageStore(specular_image,q,vec4(max(rgb,vec3(0)),1));return;
        }
        // Overflow deliberately falls back to the original photographic search.
        // Geometry-independent mortar joint coverage uses only the
        // synthetic mortar's eight original LIE11 irradiance codes.
        // Exactly the same operation in coverage-ON and coverage-OFF A/B.
        // Captured-mortar-only. No geometric plane, no flat RGB substitute.
        if(phase.value.z==0) {
            imageStore(specular_image,q,base);
            return;
        }
        uint chosen_group=EMPTY;uint chosen_owner=EMPTY;
        float chosen_depth=0.;
        vec3 chosen_normal=vec3(0.);
        // Find a genuine nearby source surface. Group is immutable parent
        // brick ID derived from 9 sample lighting patches; mortar gets 96.
        // Sampling never transfers appearance from a neighboring brick.
        for(int y=-2;y<=2 && chosen_group==EMPTY;y++)
        for(int x=-2;x<=2 && chosen_group==EMPTY;x++) {
            if(x==0 && y==0)continue;
            ivec2 p=q+ivec2(x,y);
            if(!inside(p))continue;
            uint ix=uint(p.y*parameters.counts.z+p.x);
            uint owner=winners.v[ix];
            if(owner==EMPTY || imageLoad(output_image,p).a<.5)continue;
            Projection pr=projected.v[owner];
            uint sid=uint(max(round(pr.gradient.w),0.0));
            uint node=projection_node(pr);
            if(node>=872u) continue;
            // Brick groups 0..95 unchanged; 8 photographed mortar course
            // groups 96..103 share the same genuine LIE11 source node ID.
            // Reuse existing lit PHOTO source pixels, NEVER a flat fill.
            chosen_group=node>=864u ? (96u+node-864u) : node/9u;
            chosen_depth=uintBitsToFloat(depths.v[ix]);
            chosen_normal=normalize(pr.normal.xyz);chosen_owner=owner;
        }
        if(chosen_group==EMPTY) {imageStore(specular_image,q,base);return;}
        // PHOTO SOURCE PRIORITY: the nearest source brick currently wins the
        // 3x3 seed search even for an empty pixel inside a physical joint.
        // Find the nearest surviving, depth-tested *genuine photographed*
        // mortar pixel instead; never create an analytic mortar surface.
        if(chosen_group<96u) {
            int nearest_sq=1000000;
            uint photo_group=EMPTY;uint photo_owner=EMPTY;
            float photo_depth=0.;
            vec3 photo_normal=vec3(0.);
            for(int yy=-6;yy<=6;yy++) for(int xx=-6;xx<=6;xx++) {
                int distance_sq=xx*xx+yy*yy;
                if(distance_sq>36 || distance_sq>=nearest_sq) continue;
                ivec2 p=q+ivec2(xx,yy);
                if(!inside(p) || imageLoad(output_image,p).a<.5) continue;
                uint ix=uint(p.y*parameters.counts.z+p.x);
                uint owner=winners.v[ix];
                if(owner==EMPTY) continue;
                Projection pr=projected.v[owner];
                uint sid=uint(max(round(pr.gradient.w),0.0));
                uint node=projection_node(pr);
                if(node<864u || node>=872u) continue;
                nearest_sq=distance_sq;
                photo_group=96u+node-864u;
                photo_depth=uintBitsToFloat(depths.v[ix]);
                photo_normal=normalize(pr.normal.xyz);photo_owner=owner;
            }
            if(photo_group!=EMPTY) {
                // Actual mortar-depth, actual source-owner and scanned
                // material codes continue to control the reconstructed RGB.
                chosen_group=photo_group;
                chosen_depth=photo_depth;
                chosen_normal=photo_normal;chosen_owner=photo_owner;
            }
        }
        vec3 color_sum=vec3(0.);
        vec3 coeff[9];for(int k=0;k<9;k++)coeff[k]=vec3(0);
        uint reference_node=chosen_group<96u?chosen_group*9u:864u+chosen_group-96u;
        uvec2 recovery_group=light_groups.entries[reference_node].xy;
        uint node_base=recovery_group.x;
        float sum=0., zmin=1e20, zmax=0.;
        int n=0;
        bool left=false,right=false,up=false,down=false;
        int search_radius=chosen_group>=96u ? 7 : 2;
        int nearest_source_sq=1000000;
        for(int y=-search_radius;y<=search_radius;y++)
        for(int x=-search_radius;x<=search_radius;x++) {
            if(x==0 && y==0)continue;
            ivec2 p=q+ivec2(x,y);
            if(!inside(p))continue;
            vec4 v=imageLoad(output_image,p);
            if(v.a<.5)continue;
            uint ix=uint(p.y*parameters.counts.z+p.x);
            uint owner=winners.v[ix];
            if(owner==EMPTY)continue;
            Projection pr=projected.v[owner];
            uint sid=uint(max(round(pr.gradient.w),0.0));
            uint node=projection_node(pr);
            if(node>=872u) continue;
            uint group=node>=864u ? (96u+node-864u) : node/9u;
            if(group!=chosen_group || dot(normalize(pr.normal.xyz),chosen_normal)<.65)continue;
            float depth=uintBitsToFloat(depths.v[ix]);
            // 16mm / 1% depth ceiling prevents jumping from front to the
            // far side of a real historical brick across a chipped edge.
            if(abs(depth-chosen_depth)>max(.016,.01*chosen_depth))continue;
            int distance_sq=x*x+y*y;
            if(chosen_group>=96u && distance_sq>49) continue;
            nearest_source_sq=min(nearest_source_sq,distance_sq);
            float weight=1./(float(distance_sq)+.25);
            color_sum+=v.rgb*weight;sum+=weight;
            Accumulator acc=accumulated.v[ix];
            vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);
            uvec2 stencil=lie_group(node);
            float stencil_sum=stencil.y==1u?1.:lie_stencil_sum(pr.world.xyz,node);
            for(uint k=0u;k<stencil.y;k++) {
                uint candidate=stencil.x+k;
                float w=stencil.y==1u?1.:lie_stencil_weight(pr.world.xyz,node,candidate)/max(stencil_sum,1e-30);
                coeff[candidate-node_base]+=albedo*(weight*w/PI);
            }
            zmin=min(zmin,depth);zmax=max(zmax,depth);n++;
            if(x<0)left=true;if(x>0)right=true;
            if(y<0)up=true;if(y>0)down=true;
        }
        // Only enclosed interior holes: must have real observed support on
        // BOTH sides of X and/or Y, with >=3 agreeing source neighbors.
        bool mortar=chosen_group>=96u;
        bool enclosed=n>=3 && ((left && right) || (up && down));
        bool source_physical_joint=true;
        if(mortar) {
            // A source-photographed mortar sample must be the observed owner
            // on multiple sides; never invent a planar gap surface. Restrict
            // to the physical 8.5mm joint and just under chipped source rims.
            uint row=chosen_group-96u;
            vec2 uv=(vec2(q)+vec2(.5))/vec2(parameters.counts.zw);
            vec3 ray=parameters.forward.xyz+
                parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+
                parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
            vec3 world=parameters.eye.xyz+ray*chosen_depth;
            float cy=joint.origin.y+float(row)*joint.dimensions.w;
            float vertical_offset=(row%2u==1u)?joint.origin.w*joint.dimensions.z:0.;
            float relative=(world.x-joint.origin.x-vertical_offset)/joint.dimensions.z-.5;
            float between=abs(relative-round(relative))*joint.dimensions.z;
            bool horizontal=row<7u && abs(world.y-(cy+.5*joint.dimensions.w))
                <(.5*joint.config.z+.003);
            bool vertical=abs(world.y-cy)<.5*joint.dimensions.y+.003
                && between<(.5*joint.config.z+.003);
            // 8.5mm true gap plus up to 6mm screen-space recovery under
            // chipped rims. This only admits existing PHOTO sample RGB;
            // never generates the wall from the coarse BoxShape3D.
            bool near_horizontal=row<7u && abs(world.y-(cy+.5*joint.dimensions.w))
                <(.5*joint.config.z+.006);
            bool near_vertical=abs(world.y-cy)<.5*joint.dimensions.y+.006
                && between<(.5*joint.config.z+.006);
            source_physical_joint=(horizontal || vertical || near_horizontal || near_vertical);
        }
        float tolerance=mortar?.004:max(.014,.008*chosen_depth);
        bool photographic_extension=mortar && n>=4 && nearest_source_sq<=36;
        bool witnessed=(enclosed || photographic_extension);
        if(witnessed && source_physical_joint && sum>0. && zmax-zmin<tolerance) {
            imageStore(specular_image,q,vec4(color_sum/sum,1.));
            if(stage==8) {
                uint slot=atomicAdd(recovery_count.count,1u);
                if(slot<MAX_RECOVERY) {
                    Recovery r;r.info=uvec4(node_base,recovery_group.y,0,0);
                    for(int k=0;k<9;k++)r.coefficients[k]=vec4(coeff[k]/sum,0);
                    recovery.values[slot]=r;recovery_map.values[i]=slot+1u;
                    RecoverySurface surface;
                    surface.world=vec4(lie_surface_world(projected.v[chosen_owner],vec2(q)+.5),1);
                    surface.normal=vec4(chosen_normal,float(chosen_owner+1u));recovery_surfaces.values[slot]=surface;
                } else {recovery_map.values[i]=EMPTY;atomicAdd(recovery_count.overflow,1u);}
            }
        } else imageStore(specular_image,q,base);
        return;
    }
    if(stage==7) {
        ivec2 size=imageSize(final_image);if(i>=uint(size.x*size.y)) return;
        ivec2 xy=ivec2(int(i)%size.x,int(i)/size.x);int scale=phase.value.y;
        vec3 linear=vec3(0);float coverage=0;
        float ratio=float(parameters.counts.z)/float(size.x);
        vec2 low=vec2(xy)*ratio, high=low+vec2(ratio);
        ivec2 begin=ivec2(floor(low)),end=ivec2(ceil(high));
        for(int y=begin.y;y<end.y;y++) for(int x=begin.x;x<end.x;x++) {
            vec2 overlap=max(vec2(0),min(vec2(x,y)+1.,high)-max(vec2(x,y),low));
            float weight=overlap.x*overlap.y;
            vec4 value=imageLoad(specular_image,ivec2(x,y));linear+=value.rgb*(value.a*weight);coverage+=value.a*weight;
        }
        if(coverage==0) {imageStore(final_image,xy,vec4(0));return;}
        linear=max(linear/coverage*parameters.ambient.w,vec3(0));
        imageStore(final_image,xy,vec4(to_srgb(linear/(vec3(1)+linear)),coverage/(ratio*ratio)));return;
    }
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {
            imageStore(diffuse_image,xy,vec4(0));
            imageStore(specular_image,xy,vec4(0));
            return;
        }
        Projection point=projected.v[owner];
        // Baked sample-to-node relationship is stable across all three LODs.
        // Unlike original LIE33, light intensity/color comes EXCLUSIVELY
        // from the real LIE11 GPU transport code texture.
        uint sid=uint(point.gradient.w);
        uint node=projection_node(point);
        if(node>=uint(imageSize(injected_node_irradiance).x)) {
            imageStore(diffuse_image,xy,vec4(0));
            imageStore(specular_image,xy,vec4(0));
            return;
        }
        vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(node),0)).rgb,vec3(0));
        // Each finite node material code has three vec4's (position-area,
        // normal-gray, linear filter-absorption), exactly LIE11 ABI.
        float absorption=clamp(injected_material_codes.values[node*3u+2u].w,0.,1.);
        vec3 diffuse_code=lie_irradiance_code(point);
        imageStore(diffuse_image,xy,vec4(diffuse_code,1));
        // No GGX/direct ambient here: would DOUBLE COUNT coded illumination.
        // Specular may return later through a separately audited transport.
        imageStore(specular_image,xy,vec4(0));
        return;
    }
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        imageStore(output_image,xy,vec4(max(base*imageLoad(diffuse_image,xy).rgb+imageLoad(specular_image,xy).rgb,vec3(0)),1));
    }
}
