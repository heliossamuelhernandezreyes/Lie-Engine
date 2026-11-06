#[compute]
#version 450
// LIE28: source RGB albedo and roughness captured without lighting.
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
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;

layout(set=0,binding=14,std430) readonly buffer BenchData {uvec4 header;vec4 v[];} bench;
layout(rgba32f,set=0,binding=15) uniform readonly image2D field_irradiance;
layout(set=0,binding=16,std430) readonly buffer SurfaceLights {uvec4 header;vec4 values[];} surface_lights;
layout(set=0,binding=18,std430) readonly buffer Emission {vec4 v[];} emission;
vec3 lie_position(uint node){return bench.v[24u+node*3u].xyz;}
float lie_area(uint node){return bench.v[24u+node*3u].w;}
vec3 lie_normal(uint node){return bench.v[24u+node*3u+1u].xyz;}
uvec2 lie_group(uint node){return uvec2(bench.v[24u+node*3u+2u].xy);}
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
layout(set=0,binding=19,std430) buffer IndirectNodes {vec4 v[];} indirect_nodes;
vec3 bench_indirect(vec3 p,uint node) {
    uvec2 group=lie_group(node);float sum=lie_stencil_sum(p,node);vec3 result=vec3(0);
    for(uint k=0u;k<group.y;k++) {
        uint j=group.x+k;float w=lie_stencil_weight(p,node,j)/max(sum,1e-30);
        result+=w*indirect_nodes.v[j].rgb;
    }
    return result;
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
// Relative total RGB power: an isotropic point has gain 1. A one-sided
// Lambert emitter has intensity Phi*cos(theta)/PI, hence gain 4*cos.
float lie_emitter_gain(vec4 shape,vec3 from_source) {
    if(shape.w<.5)return 1.;
    float d2=dot(from_source,from_source);
    return d2>1e-20?4.*max(dot(shape.xyz,from_source*inversesqrt(d2)),0.):0.;
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
float bench_visibility(uint light,vec3 p,vec3 geometric_normal) {
    vec3 d=p-surface_lights.values[light*2u].xyz;float z=dot(d,bench.v[light*3u+2u].xyz);
    if(z<=.001) return 1;
    vec2 uv=project(p,surface_lights.values[light*2u].xyz,bench.v[light*3u+0u].xyz,bench.v[light*3u+1u].xyz,bench.v[light*3u+2u].xyz,1.25,vec2(SHADOW_SIZE));
    if(any(lessThan(uv,vec2(1))) || any(greaterThan(uv,vec2(SHADOW_SIZE-2)))) return 1;
    float receiver_plane=dot(geometric_normal,d);
    if(abs(receiver_plane)<1e-7) return 1;
    vec2 gradient=vec2(2*1.25*dot(geometric_normal,bench.v[light*3u+0u].xyz),-2*1.25*dot(geometric_normal,bench.v[light*3u+1u].xyz))/(float(SHADOW_SIZE)*receiver_plane);
    float result=0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        ivec2 q=clamp(ivec2(uv)+ivec2(x,y),ivec2(0),ivec2(SHADOW_SIZE-1));
        float stored=uintBitsToFloat(shadow.v[light*uint(SHADOW_SIZE*SHADOW_SIZE)+uint(q.y*SHADOW_SIZE+q.x)]);
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

void main() {
    uint i=gl_GlobalInvocationID.x,pixels=uint(parameters.counts.z*parameters.counts.w);
    int stage=phase.value.x;
    if(stage==1) {
        if(i<pixels) {depths.v[i]=0x7f7fffffu;winners.v[i]=EMPTY;accumulated.v[i].color_weight=uvec4(0);accumulated.v[i].normal_roughness=uvec4(0);}
        if(i<uint(SHADOW_SIZE*SHADOW_SIZE))for(uint l=0u;l<8u;l++)shadow.v[l*uint(SHADOW_SIZE*SHADOW_SIZE)+i]=0x7f7fffffu;return;
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
            for(uint light=0u;light<surface_lights.header.y;light++) {
            vec3 ld=world-surface_lights.values[light*2u].xyz;float lz=dot(ld,bench.v[light*3u+2u].xyz);
            if(lz>.00001 && dot(n,normalize(-ld))>.05) {
                vec2 xy=project(world,surface_lights.values[light*2u].xyz,bench.v[light*3u+0u].xyz,bench.v[light*3u+1u].xyz,bench.v[light*3u+2u].xyz,1.25,vec2(SHADOW_SIZE));
                float plane=dot(n,ld);vec2 gradient=vec2(2*1.25*dot(n,bench.v[light*3u+0u].xyz),-2*1.25*dot(n,bench.v[light*3u+1u].xyz))/(float(SHADOW_SIZE)*plane);
                float offset_ratio=max(abs(dot(ld,bench.v[light*3u].xyz)),abs(dot(ld,bench.v[light*3u+1u].xyz)))/lz;
                int shadow_bound=min(SHADOW_SIZE,int(ceil(radius*(1.+offset_ratio)*float(SHADOW_SIZE)/(2.*1.25*max(lz-radius,1e-6)))+1.));
                for(int y=-shadow_bound;y<=shadow_bound;y++)for(int x=-shadow_bound;x<=shadow_bound;x++) {
                    ivec2 q=ivec2(xy)+ivec2(x,y);float z=1.0/(1.0/lz+dot(gradient,vec2(q)+.5-xy));
                    vec2 uv=(vec2(q)+.5)/float(SHADOW_SIZE);
                    vec3 ray=bench.v[light*3u+2u].xyz+bench.v[light*3u+0u].xyz*((2*uv.x-1)*1.25)+bench.v[light*3u+1u].xyz*((1-2*uv.y)*1.25);
                    vec3 local_hit=inverse(basis)*(surface_lights.values[light*2u].xyz+ray*z-inst.origin.xyz);
                    vec3 axis=abs(s.normal_gray.xyz);vec2 support_point=axis.x>=axis.y && axis.x>=axis.z?local_hit.zy:axis.y>=axis.z?local_hit.xz:local_hit.xy;
                    bool face_support=all(greaterThanEqual(support_point,s.support.xy-vec2(.000002))) && all(lessThanEqual(support_point,s.support.zw+vec2(.000002)));
                    if(face_support && z>.00001 && length(surface_lights.values[light*2u].xyz+ray*z-world)<=radius+lz*1.25/float(SHADOW_SIZE) && all(greaterThanEqual(q,ivec2(0))) && all(lessThan(q,ivec2(SHADOW_SIZE))))atomicMin(shadow.v[light*uint(SHADOW_SIZE*SHADOW_SIZE)+uint(q.y*SHADOW_SIZE+q.x)],floatBitsToUint(z));
                }
            }
            }
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
                atomicAdd(accumulated.v[pixel].normal_roughness.x,n.x);atomicAdd(accumulated.v[pixel].normal_roughness.y,n.y);atomicAdd(accumulated.v[pixel].normal_roughness.z,n.z);float rough=s.attributes.z;
                if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);}
                atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(rough*float(w))));
            }
        }return;
    }
    if(stage==8) {
        if(i>=bench.header.x)return;
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++)direct+=surface_lights.values[16u+l*bench.header.x+i].rgb;
        indirect_nodes.v[i]=vec4(max(imageLoad(field_irradiance,ivec2(int(i),0)).rgb-direct,vec3(0)),1);
        return;
    }
    if(stage==7) {
        ivec2 size=imageSize(final_image);if(i>=uint(size.x*size.y)) return;
        ivec2 xy=ivec2(int(i)%size.x,int(i)/size.x);int scale=phase.value.y;
        vec3 linear=vec3(0);float coverage=0;
        for(int y=0;y<scale;y++) for(int x=0;x<scale;x++) {
            vec4 value=imageLoad(output_image,xy*scale+ivec2(x,y));linear+=value.rgb*value.a;coverage+=value.a;
        }
        if(coverage==0) {imageStore(final_image,xy,vec4(0));return;}
        linear=max(linear/coverage*parameters.ambient.w,vec3(0));
        imageStore(final_image,xy,vec4(linear,coverage/float(scale*scale)));return;
    }
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {imageStore(diffuse_image,xy,vec4(0));imageStore(specular_image,xy,vec4(0));return;}
        Projection point=projected.v[owner];
        Accumulator acc=accumulated.v[i];float weight=max(float(acc.color_weight.w),1);
        vec3 base=vec3(acc.color_weight.xyz)/weight;
        vec3 n=normalize(vec3(acc.normal_roughness.xyz)/weight*2-1);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        Sample source=samples.v[uint(point.gradient.w)];
        uint node=uint(source.attributes.y)+uint(instances.v[uint(point.gradient.z)].meta.x);
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++) {
            vec3 E=lie_surface_unoccluded(l,p,n)*lie_emitter_gain(emission.v[l],p-surface_lights.values[l*2u].xyz);
            direct+=E*bench_visibility(l,p+point.geometry.xyz*parameters.options.z*.45,point.geometry.xyz);
        }
        imageStore(diffuse_image,xy,vec4(base*direct/PI,1));
        imageStore(specular_image,xy,vec4(base*bench_indirect(p,node)/PI,1));
        return;
    }
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        vec3 direct=imageLoad(diffuse_image,xy).rgb,indirect=imageLoad(specular_image,xy).rgb;
        int mode=int(parameters.settings.w);
        imageStore(output_image,xy,vec4(max(mode==1?direct:mode==2?indirect:direct+indirect,vec3(0)),1));
    }
}
