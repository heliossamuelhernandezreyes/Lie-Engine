#[compute]
#version 450
// LIE-WALL-01: genuine source color and normal, LIE11 GPU coded node lighting.
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
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}
float footprint_distance(Projection p,vec2 xy) {
    vec2 q=xy-p.screen.xy;
    return q.x*q.x*p.ellipse.x+2*q.x*q.y*p.ellipse.y+q.y*q.y*p.ellipse.z;
}
bool covered(Projection p,vec2 xy) {
    if(footprint_distance(p,xy)>1) return false;
    // Keep coarse samples on their original source face. In particular, a
    // brick's projected discs cannot cover adjacent mortar or an opening.
    Sample s=samples.v[uint(p.gradient.w)];
    Instance inst=instances.v[uint(p.gradient.z)];
    vec2 uv=xy/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
    vec3 local=inverse(mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz))*(parameters.eye.xyz+ray*pixel_depth(p,xy)-inst.origin.xyz);
    vec3 n=abs(s.normal_gray.xyz);
    vec2 q=n.x>=n.y && n.x>=n.z?local.zy:n.y>=n.z?local.xz:local.xy;
    return all(greaterThanEqual(q,s.support.xy-vec2(.000002))) && all(lessThanEqual(q,s.support.zw+vec2(.000002)));
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

vec4 real_joint_light(ivec2 pixel) {
    // A missing color pixel may be a hole INSIDE a scanned brick (do not
    // fabricate its geometry) or a bona fide physical mortar joint.
    // Intersect a screen ray with the separate recessed procedural mortar
    // plane and reject every measured brick nominal XY footprint.
    vec2 uv=(vec2(pixel)+vec2(.5))/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz +
        parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+
        parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
    if(abs(ray.z)<1e-7) return vec4(0);
    float t=(joint.origin.z-parameters.eye.z)/ray.z;
    float camera_depth=t*dot(ray,parameters.forward.xyz);
    if(t<=0. || camera_depth<=parameters.lens.z || camera_depth>=parameters.lens.w)
        return vec4(0);
    vec2 hit=(parameters.eye.xyz+ray*t).xy;
    float pitch_x=joint.dimensions.z;
    float pitch_y=joint.dimensions.w;
    if(pitch_x<=0. || pitch_y<=0.) return vec4(0);
    int r=int(round((hit.y-joint.origin.y)/pitch_y));
    if(r<0 || r>=int(joint.config.y)) return vec4(0);
    float stagger=mod(float(r),2.)*joint.origin.w*pitch_x;
    float c0=joint.origin.x+stagger;
    int col=int(round((hit.x-c0)/pitch_x));
    if(col<0 || col>=int(joint.config.x)) return vec4(0);
    vec2 delta=abs(hit-vec2(c0+float(col)*pitch_x,
                             joint.origin.y+float(r)*pitch_y));
    vec2 halfbrick=joint.dimensions.xy*.5;
    // Never retexture the genuine scan, including its chipped edges.
    // The safe inset also absorbs up to 1.5 mm of slightly rotated bricks.
    if(all(lessThanEqual(delta,halfbrick+vec2(.0015)))) return vec4(0);
    // Joints only: no phantom plane extending beyond the outer wall.
    float margin=joint.config.z*.62;
    if(any(greaterThan(delta,halfbrick+vec2(margin)))) return vec4(0);
    uint node=864u+uint(r);
    if(node>=uint(imageSize(injected_node_irradiance).x)) return vec4(0);
    vec3 irradiance=max(imageLoad(injected_node_irradiance,
                                 ivec2(int(node),0)).rgb,vec3(0));
    float absorption=clamp(injected_material_codes.values[node*3u+2u].w,0.,1.);
    // The mortar is explicitly PROCEDURAL. This is its neutral linear RGB
    // base from the existing physical joint master, lit by LIE11 nodal codes.
    vec3 mortar_albedo=vec3(.295,.273,.247);
    return vec4(mortar_albedo*(1.-absorption)*irradiance/PI,1.);
}

void main() {
    // 2D workgroup dispatch: linear index across rows of <= 65535 x-groups.
    // gl_GlobalInvocationID.x covers the row, and Y advances by the complete
    // number of x-workgroups * 64; no duplicate/missing work items.
    uint i=gl_GlobalInvocationID.x+
        gl_WorkGroupID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,
        pixels=uint(parameters.counts.z*parameters.counts.w);
    int stage=phase.value.x;
    if(stage==1) {
        if(i<pixels) {depths.v[i]=0x7f7fffffu;winners.v[i]=EMPTY;accumulated.v[i].color_weight=uvec4(0);accumulated.v[i].normal_roughness=uvec4(0);}
        if(i<uint(SHADOW_SIZE*SHADOW_SIZE))shadow.v[i]=0x7f7fffffu;return;
    }
    if(stage==2 || stage==3) {
        if(i>=uint(parameters.counts.x))return;
        uint j=job_index(i);uvec4 job=jobs.v[j];uint sid=job.x+i-job.w;
        Sample s=samples.v[sid];Instance inst=instances.v[job.z];
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
        Projection p;
        if(stage==2) {
            vec3 local=s.position_radius.xyz;float radius=s.position_radius.w;
            if(parameters.settings.y<.5) {
                float r=length(local.xy),inner=.0017,outer=.006;
                if(int(s.attributes.x)==1 && r>1e-8) {
                    float nr=parameters.iris.w+(r-inner)*(outer-parameters.iris.w)/(outer-inner);
                    local.xy*=nr/r;radius*=max(nr/r,(outer-parameters.iris.w)/(outer-inner));
                } else if(int(s.attributes.x)==2) {local.xy*=parameters.iris.w/inner;radius*=parameters.iris.w/inner;}
            }
            vec3 world=basis*local+inst.origin.xyz;
            vec3 n=normalize(transpose(inverse(basis))*s.normal_gray.xyz);
            radius*=max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(n,normalize(-delta));
            p.world=vec4(world,1);p.normal=vec4(n,front);p.screen=vec4(0);p.gradient=vec4(0,0,float(job.z),float(sid));p.geometry=vec4(n,s.attributes.x);p.ellipse=vec4(0);
            // Source light energy, blocker visibility and indirect generations
            // are handled by ORIGINAL LIE11 PRE_OPAQUE transport on the GPU.
            // Do not rebuild LIE33's obsolete shadow map a second time.
            if(depth>parameters.lens.z && depth<parameters.lens.w && front>.015) {
                vec2 xy=project(world,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw));
                vec3 tangent=normalize(cross(n,abs(n.y)<.9?vec3(0,1,0):vec3(1,0,0)));vec3 bitangent=cross(n,tangent);
                vec2 u=project(world+tangent*radius,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                vec2 v=project(world+bitangent*radius,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                float xx=dot(vec2(u.x,v.x),vec2(u.x,v.x))+.20,yy=dot(vec2(u.y,v.y),vec2(u.y,v.y))+.20,off=u.x*u.y+v.x*v.y,det=max(xx*yy-off*off,1e-8);
                p.ellipse=vec4(yy/det,-off/det,xx/det,0);p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,8));
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
                if(depths.v[pixel]==bits)atomicMin(winners.v[pixel],i);
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
    if(stage==8) {
        // LIE-WALL03, after stage 6. GPU hole recovery ONLY INSIDE EXISTING
        // source-brick neighborhoods. 4.6M internal pixels, with expensive
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
        // Geometry-independent mortar joint coverage uses only the
        // synthetic mortar's eight original LIE11 irradiance codes.
        // Exactly the same operation in coverage-ON and coverage-OFF A/B.
        vec4 mortar=real_joint_light(q);
        if(mortar.a>.5) {
            imageStore(specular_image,q,mortar);
            return;
        }
        if(phase.value.z==0) {
            imageStore(specular_image,q,base);
            return;
        }
        uint chosen_group=EMPTY;
        float chosen_depth=0.;
        vec3 chosen_normal=vec3(0.);
        // Find a genuine nearby source surface. Group is immutable parent
        // brick ID derived from 9 sample lighting patches; mortar gets 96.
        // Sampling never transfers appearance from a neighboring brick.
        for(int y=-1;y<=1 && chosen_group==EMPTY;y++)
        for(int x=-1;x<=1 && chosen_group==EMPTY;x++) {
            if(x==0 && y==0)continue;
            ivec2 p=q+ivec2(x,y);
            if(!inside(p))continue;
            uint ix=uint(p.y*parameters.counts.z+p.x);
            uint owner=winners.v[ix];
            if(owner==EMPTY || imageLoad(output_image,p).a<.5)continue;
            Projection pr=projected.v[owner];
            uint sid=uint(max(round(pr.gradient.w),0.0));
            uint node=uint(max(round(samples.v[sid].attributes.y),0.0));
            chosen_group=node<864u?node/9u:96u;
            chosen_depth=uintBitsToFloat(depths.v[ix]);
            chosen_normal=normalize(pr.normal.xyz);
        }
        if(chosen_group==EMPTY) {imageStore(specular_image,q,base);return;}
        vec3 color_sum=vec3(0.);
        float sum=0., zmin=1e20, zmax=0.;
        int n=0;
        bool left=false,right=false,up=false,down=false;
        for(int y=-2;y<=2;y++)
        for(int x=-2;x<=2;x++) {
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
            uint node=uint(max(round(samples.v[sid].attributes.y),0.0));
            uint group=node<864u?node/9u:96u;
            if(group!=chosen_group || dot(normalize(pr.normal.xyz),chosen_normal)<.65)continue;
            float depth=uintBitsToFloat(depths.v[ix]);
            // 16mm / 1% depth ceiling prevents jumping from front to the
            // far side of a real historical brick across a chipped edge.
            if(abs(depth-chosen_depth)>max(.016,.01*chosen_depth))continue;
            float weight=1./(float(x*x+y*y)+.25);
            color_sum+=v.rgb*weight;sum+=weight;
            zmin=min(zmin,depth);zmax=max(zmax,depth);n++;
            if(x<0)left=true;if(x>0)right=true;
            if(y<0)up=true;if(y>0)down=true;
        }
        // Only enclosed interior holes: must have real observed support on
        // BOTH sides of X and/or Y, with >=3 agreeing source neighbors.
        bool enclosed=n>=3 && ((left && right) || (up && down));
        if(enclosed && sum>0. && zmax-zmin<max(.014,.008*chosen_depth)) {
            imageStore(specular_image,q,vec4(color_sum/sum,1.));
        } else imageStore(specular_image,q,base);
        return;
    }
    if(stage==7) {
        ivec2 size=imageSize(final_image);if(i>=uint(size.x*size.y)) return;
        ivec2 xy=ivec2(int(i)%size.x,int(i)/size.x);int scale=phase.value.y;
        vec3 linear=vec3(0);float coverage=0;
        for(int y=0;y<scale;y++) for(int x=0;x<scale;x++) {
            vec4 value=imageLoad(specular_image,xy*scale+ivec2(x,y));linear+=value.rgb*value.a;coverage+=value.a;
        }
        if(coverage==0) {imageStore(final_image,xy,vec4(0));return;}
        linear=max(linear/coverage*parameters.ambient.w,vec3(0));
        imageStore(final_image,xy,vec4(to_srgb(linear/(vec3(1)+linear)),coverage/float(scale*scale)));return;
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
        Sample surf=samples.v[sid];
        uint node=uint(max(round(surf.attributes.y),0.0));
        if(node>=uint(imageSize(injected_node_irradiance).x)) {
            imageStore(diffuse_image,xy,vec4(0));
            imageStore(specular_image,xy,vec4(0));
            return;
        }
        vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(node),0)).rgb,vec3(0));
        // Each finite node material code has three vec4's (position-area,
        // normal-gray, linear filter-absorption), exactly LIE11 ABI.
        float absorption=clamp(injected_material_codes.values[node*3u+2u].w,0.,1.);
        vec3 diffuse_code=E*(1.-absorption)/PI;
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
