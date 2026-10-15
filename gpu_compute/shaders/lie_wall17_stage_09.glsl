#[compute]
#version 450
// GENERATED dedicated stage 9; tools/lie_wall17_shader.py
// LIE-WALL-04: genuine source-colored bricks and real-photo mortar samples, LIE11 nodes.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };



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
layout(rgba32ui,set=0,binding=8) uniform uimage2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;


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







layout(set=0,binding=18,std430) buffer RecoveryMap { uint values[]; } recovery_map;
struct Recovery { uvec4 info; vec4 coefficients[9]; };
layout(set=0,binding=19,std430) buffer RecoveryRecords { Recovery values[]; } recovery;
layout(set=0,binding=20,std430) buffer RecoveryCount { uint count; uint overflow; uint reserved_a; uint reserved_b; } recovery_count;
const uint MAX_RECOVERY=65536u;
// A virtual sample is reconstructed from ONE original immutable brick master.
// Per-instance transforms, source subset IDs and tint recreate the old WALL04
// records; photo mortar records are copied unchanged. No original mesh draws.


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




bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}












// WALL04 has no analytic flat-plane mortar. Every mortar pixel must be
// depth-tested from a PHOTO-CAPTURED source sample in the original stage 2/3.
// The single 6-face invisible spatial envelope is NEVER a visible surface.




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










// Header: 64 uints. Each source-reference slot: two packed visibility words
// and one validity mask. The domain binds bank, reference SHA and scene SHA.
// Geometry/normal/radius are immutable in this domain; camera is not a key.













// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.




// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.


layout(set=0,binding=33,std430) readonly buffer PipelineControl {uvec4 flags;} pipeline_control;
// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};
LiePixelMaterial lie_raw_material(uint i) {
    Accumulator a=accumulated.v[i];float w=max(float(a.color_weight.w),1.);
    vec3 n=vec3(a.normal_roughness.xyz)/w*2.-1.;
    return LiePixelMaterial(vec3(a.color_weight.xyz)/w,n,float(a.normal_roughness.w)/w,min(length(n),1.));
}

LiePixelMaterial lie_unpack_material(uvec4 b) {
    vec2 a=unpackHalf2x16(b.x),c=unpackHalf2x16(b.y),n=unpackHalf2x16(b.z),z=unpackHalf2x16(b.w);
    return LiePixelMaterial(vec3(a,c.x),vec3(n,z.x),c.y,z.y);
}


LiePixelMaterial lie_material(uint i) {
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    return pipeline_control.flags.y!=0u?lie_unpack_material(imageLoad(diffuse_image,q)):lie_raw_material(i);
}




// Generic world-space hierarchy over adapter-evaluated immutable surface IDs.
// Four vec4s per node: center bounds and normal component intervals.









void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=9;

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
        vec3 coeff[9];float optical_coeff[9];for(int k=0;k<9;k++){coeff[k]=vec3(0);optical_coeff[k]=0.;}
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
            vec3 albedo=lie_material(ix).albedo;
            uvec2 stencil=lie_group(node);
            float stencil_sum=stencil.y==1u?1.:lie_stencil_sum(pr.world.xyz,node);
            for(uint k=0u;k<stencil.y;k++) {
                uint candidate=stencil.x+k;
                float w=stencil.y==1u?1.:lie_stencil_weight(pr.world.xyz,node,candidate)/max(stencil_sum,1e-30);
                coeff[candidate-node_base]+=albedo*(weight*w/PI);optical_coeff[candidate-node_base]+=weight*w;
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
                    for(int k=0;k<9;k++)r.coefficients[k]=vec4(coeff[k]/sum,optical_coeff[k]/sum);
                    recovery.values[slot]=r;recovery_map.values[i]=slot+1u;
                    RecoverySurface surface;
                    surface.world=vec4(lie_surface_world(projected.v[chosen_owner],vec2(q)+.5),1);
                    surface.normal=vec4(chosen_normal,float(chosen_owner+1u));recovery_surfaces.values[slot]=surface;
                } else {recovery_map.values[i]=EMPTY;atomicAdd(recovery_count.overflow,1u);}
            }
        } else imageStore(specular_image,q,base);
        return;
    
}
