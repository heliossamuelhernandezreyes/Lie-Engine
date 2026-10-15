#[compute]
#version 450
// LIE36: real preassembled WALL04 brick/mortar panels.
// Exact portable LIE0.9 BRDF and conservative LIE0.9 footprint bounds.
// The LIE0.9 patch-graph illumination is NOT transferred to this multiwall demo.
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

// LIE37: generic per-INSTANCE diffuse light transport over assembled
// photographed-sample panels. Unlike WALL12's fixed 872-node wall graph,
// this uses transformed panel geometry and arbitrary camera/light movement.
layout(set=0,binding=14,std430) buffer PanelDirect { vec4 energy[]; } panel_direct;
layout(set=0,binding=15,std430) buffer PairLinks { float weights[]; } pair_links;
layout(set=0,binding=16,std430) buffer PanelBounce { vec4 energy[]; } panel_bounce;
const int LIE_HOUSE_CAP=128;
const float PANEL_W=2.64675009727478;
const float PANEL_H=.6878780770301819;
// LIE37 seam repair: interpolate ONLY a one-pixel absence between matching
// captured neighbor surfaces. Never invent colors where authentic scanned
// geometry has already won, and never bridge silhouettes or wide apertures.
bool lie_neighbor_match(ivec2 a,ivec2 b) {
    if(any(lessThan(a,ivec2(0))) || any(lessThan(b,ivec2(0))) ||
       any(greaterThanEqual(a,parameters.counts.zw)) ||
       any(greaterThanEqual(b,parameters.counts.zw)))return false;
    ivec2 size=parameters.counts.zw;
    int ia=a.y*size.x+a.x,ib=b.y*size.x+b.x;
    uint wa=winners.v[ia],wb=winners.v[ib];
    if(wa==EMPTY || wb==EMPTY)return false;
    vec3 na=projected.v[wa].normal.xyz;
    vec3 nb=projected.v[wb].normal.xyz;
    if(dot(na,nb)<.94)return false;
    float za=uintBitsToFloat(depths.v[ia]),zb=uintBitsToFloat(depths.v[ib]);
    if(abs(za-zb)>.075+max(za,zb)*.003)return false;
    vec3 ca=imageLoad(output_image,a).rgb;
    vec3 cb=imageLoad(output_image,b).rgb;
    return length(ca-cb)<.29;
}

vec3 panel_normal(int idx) {
    Instance inst=instances.v[idx];
    return normalize(cross(inst.x.xyz,inst.y.xyz));
}
float panel_area(int idx) {
    Instance inst=instances.v[idx];
    return PANEL_W*PANEL_H*length(cross(inst.x.xyz,inst.y.xyz));
}
bool panel_blocks_ray(vec3 a,vec3 b,int skip0,int skip1) {
    vec3 direction=b-a;
    int n=parameters.counts.y;
    for(int k=0;k<n;k++) {
        if(k==skip0 || k==skip1)continue;
        Instance inst=instances.v[k];
        vec3 ex=inst.x.xyz,ey=inst.y.xyz;
        vec3 nrm=normalize(cross(ex,ey));
        float denom=dot(nrm,direction);
        if(abs(denom)<1e-7)continue;
        float t=dot(nrm,inst.origin.xyz-a)/denom;
        if(t<=.001 || t>=.999)continue;
        vec3 hit=a+t*direction-inst.origin.xyz;
        float u=dot(hit,ex)/max(dot(ex,ex),1e-9);
        float v=dot(hit,ey)/max(dot(ey,ey),1e-9);
        if(abs(u)>PANEL_W*.5 || abs(v)>PANEL_H*.5)continue;
        int kind=int(inst.meta.y+.5);
        if(kind==1 && abs(u)<.56 && abs(v)<.275)continue;
        if(kind==2 && abs(u)<.52)continue;
        if(kind==3 && abs(u)<.15)continue;
        return true;
    }
    return false;
}
vec3 panel_captured_albedo(int idx) {
    uvec4 job=jobs.v[idx];
    uint q=max(job.y,1u);
    Sample a=samples.v[job.x];
    Sample b=samples.v[job.x+q/2u];
    Sample c=samples.v[job.x+q-1u];
    return clamp((a.albedo.rgb+b.albedo.rgb+c.albedo.rgb)/3.,vec3(0),vec3(.95));
}

const uint EMPTY=0xffffffffu;
// LIE0.9 canonical shared GGX/Smith/Schlick microfacet implementation:
// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.
vec3 lie_opaque_direction(vec3 delta) {
    // A source exactly on a receiver has zero incident irradiance. Keep its
    // direction finite as well: normalize(0) is undefined on GPU hardware.
    return delta*inversesqrt(max(dot(delta,delta),1e-20));
}
float lie_fresnel(float cosine,float f0) {
    float m=clamp(1.-cosine,0.,1.);float m2=m*m;
    return f0+(1.-f0)*m2*m2*m;
}
float lie_filtered_roughness(float roughness,float mean_length,bool filtered) {
    float r=clamp(roughness,.2,.98);
    float variance=filtered?clamp(1.-mean_length,0.,1.):0.;
    // Normal variance broadens the squared microfacet width. It never
    // changes the captured geometric normal, source color or visibility.
    return sqrt(sqrt(min(r*r*r*r+variance,1.)));
}
vec3 lie_opaque_brdf(vec3 albedo,float roughness,float f0,float survival,vec3 normal,vec3 view,vec3 light) {
    float nl=dot(normal,light),nv=dot(normal,view);
    if(nl<=1e-6 || nv<=1e-6)return vec3(0);
    vec3 half_sum=view+light;float h2=dot(half_sum,half_sum);
    if(h2<=1e-12)return vec3(0);
    vec3 h=half_sum*inversesqrt(h2);
    float nh=max(dot(normal,h),0.),vh=max(dot(view,h),0.);
    float alpha=roughness*roughness,a2=alpha*alpha;
    float denominator=nh*nh*(a2-1.)+1.;
    float D=a2/(3.141592653589793*denominator*denominator);
    // Algebraically equivalent to G2/(4*nl*nv); stable near grazing.
    float smith=2.*(nv*sqrt(a2+(1.-a2)*nl*nl)+nl*sqrt(a2+(1.-a2)*nv*nv));
    float specular=D*lie_fresnel(vh,f0)/max(smith,1e-12);
    float diffuse=(1.-lie_fresnel(nl,f0))*(1.-lie_fresnel(nv,f0))/3.141592653589793;
    return albedo*diffuse+vec3(specular*survival);
}

// LIE0.9 canonical conservative splat row bounds:
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

void main() {
    uint i=gl_GlobalInvocationID.x,pixels=uint(parameters.counts.z*parameters.counts.w);
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
            vec3 ld=world-parameters.light.xyz;float lz=dot(ld,parameters.shadow_forward.xyz);
            if(lz>.00001 && dot(n,normalize(-ld))>.05) {
                vec2 xy=project(world,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
                float plane=dot(n,ld);vec2 gradient=vec2(2*1.25*dot(n,parameters.shadow_right.xyz),-2*1.25*dot(n,parameters.shadow_up.xyz))/(float(SHADOW_SIZE)*plane);
                for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {
                    ivec2 q=ivec2(xy)+ivec2(x,y);float z=1.0/(1.0/lz+dot(gradient,vec2(q)+.5-xy));
                    vec2 uv=(vec2(q)+.5)/float(SHADOW_SIZE);
                    vec3 ray=parameters.shadow_forward.xyz+parameters.shadow_right.xyz*((2*uv.x-1)*1.25)+parameters.shadow_up.xyz*((1-2*uv.y)*1.25);
                    if(z>.00001 && length(parameters.light.xyz+ray*z-world)<=radius+lz*1.25/float(SHADOW_SIZE) && all(greaterThanEqual(q,ivec2(0))) && all(lessThan(q,ivec2(SHADOW_SIZE))))atomicMin(shadow.v[q.y*SHADOW_SIZE+q.x],floatBitsToUint(z));
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
        ivec2 center=ivec2(floor(p.screen.xy));
        for(int y=-bound;y<=bound;y++) {
          ivec2 interval=lie_splat_row(p,center,center.y+y,bound);
          for(int qx=interval.x;qx<=interval.y;qx++) {
            ivec2 q=ivec2(qx,center.y+y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;
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
          }
        }return;
    }
    if(stage==8) {
        if(i>=uint(parameters.counts.y))return;
        int idx=int(i);
        vec3 p=instances.v[idx].origin.xyz;
        vec3 d=parameters.light.xyz-p;
        float dist2=max(dot(d,d),.01);
        vec3 dir=normalize(d);
        float cosine=abs(dot(panel_normal(idx),dir));
        bool blocked=panel_blocks_ray(p+dir*.008,parameters.light.xyz,idx,-1);
        float irradiance=parameters.light.w*cosine/(4.*PI*dist2);
        panel_direct.energy[idx]=vec4(blocked?vec3(0):parameters.light_color.rgb*irradiance,1.);
        return;
    }
    if(stage==9) {
        if(i>=uint(parameters.counts.y))return;
        int emitter=int(i), n=parameters.counts.y;
        vec3 a=instances.v[emitter].origin.xyz;
        vec3 na=panel_normal(emitter);
        float sum_w=0.;
        for(int dst=0;dst<n;dst++) {
            float w=0.;
            if(dst!=emitter) {
                vec3 b=instances.v[dst].origin.xyz;
                vec3 delta=b-a;
                float d2=dot(delta,delta);
                if(d2>.09) {
                    vec3 dir=delta*inversesqrt(d2);
                    float source_cos=abs(dot(na,dir));
                    float target_cos=abs(dot(panel_normal(dst),dir));
                    if(source_cos>.001 && target_cos>.001 &&
                        !panel_blocks_ray(a,b,emitter,dst)) {
                        w=clamp(panel_area(dst)*source_cos*target_cos/(PI*d2),0.,1.);
                    }
                }
            }
            pair_links.weights[emitter*LIE_HOUSE_CAP+dst]=w;
            sum_w+=w;
        }
        // Per-source passive energy normalization. For every RGB channel,
        // total emitted diffuse power cannot exceed the intercepted source
        // power; no invented light appears at seams or inside sealed rooms.
        float normalization=max(1.,sum_w);
        for(int dst=0;dst<n;dst++)
            pair_links.weights[emitter*LIE_HOUSE_CAP+dst]/=normalization;
        return;
    }
    if(stage==10) {
        if(i>=uint(parameters.counts.y))return;
        int target=int(i), n=parameters.counts.y;
        float receiver_area=max(panel_area(target),.001);
        vec3 indirect=vec3(0);
        for(int src=0;src<n;src++) {
            float w=pair_links.weights[src*LIE_HOUSE_CAP+target];
            if(w<=0.)continue;
            indirect+=panel_direct.energy[src].rgb*
                panel_captured_albedo(src)*.68*
                (panel_area(src)/receiver_area)*w;
        }
        panel_bounce.energy[target]=vec4(max(indirect,vec3(0)),1);
        return;
    }
    if(stage==11 || stage==12) {
        if(i>=pixels)return;
        ivec2 at=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
        if(stage==12) {imageStore(output_image,at,imageLoad(specular_image,at));return;}
        vec4 original=imageLoad(output_image,at);
        if(original.a>.5 || parameters.settings.w<.5) {
            imageStore(specular_image,at,original);
            return;
        }
        ivec2 left=at+ivec2(-1,0),right=at+ivec2(1,0);
        ivec2 top=at+ivec2(0,-1),bottom=at+ivec2(0,1);
        vec3 color=vec3(0);
        float count=0.;
        if(lie_neighbor_match(left,right)) {
            color+=.5*(imageLoad(output_image,left).rgb+imageLoad(output_image,right).rgb);
            count+=1.;
        }
        if(lie_neighbor_match(top,bottom)) {
            color+=.5*(imageLoad(output_image,top).rgb+imageLoad(output_image,bottom).rgb);
            count+=1.;
        }
        imageStore(specular_image,at,count>0.?vec4(color/count,1.):original);
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
        imageStore(final_image,xy,vec4(to_srgb(linear/(vec3(1)+linear)),coverage/float(scale*scale)));return;
    }
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {imageStore(diffuse_image,xy,vec4(0));imageStore(specular_image,xy,vec4(0));return;}
        Projection point=projected.v[owner];
        Accumulator acc=accumulated.v[i];
        float weight=max(float(acc.color_weight.w),1.);
        vec3 base=clamp(vec3(acc.color_weight.xyz)/weight,vec3(0),vec3(1));
        vec3 captured_normal=vec3(acc.normal_roughness.xyz)/weight*2.-1.;
        float normal_length=length(captured_normal);
        vec3 n=captured_normal*inversesqrt(max(dot(captured_normal,captured_normal),1e-12));
        float roughness=lie_filtered_roughness(
            float(acc.normal_roughness.w)/weight,normal_length,true);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
        vec3 world=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]);
        vec3 view=lie_opaque_direction(parameters.eye.xyz-world);
        vec3 to_light=parameters.light.xyz-world;
        float distance2=max(dot(to_light,to_light),.0001);
        vec3 light=lie_opaque_direction(to_light);
        float nl=max(dot(n,light),0.);
        float visibility_factor=parameters.options.x>.5?
            visibility(world+point.geometry.xyz*parameters.options.z*.45,point.geometry.xyz):1.;
        vec3 radiance=parameters.light_color.rgb*
            (parameters.light.w/(4.*PI*distance2))*visibility_factor;
        // LIE0.9 physically motivated opaque BRDF, evaluated under this
        // lab's ONE direct emitter, not under the WALL12 LIE11 patch graph.
        vec3 reflected=radiance*nl*lie_opaque_brdf(
            base,roughness,.04,1.,n,view,light);
        vec3 authored_fill=base*parameters.ambient.rgb*.12;
        int panel=int(point.gradient.z);
        vec3 incoming=parameters.settings.z>.5?panel_bounce.energy[panel].rgb:vec3(0);
        // The transport result is irradiance: one Lambert conversion and
        // diffuse Fresnel attenuation; the direct GGX term remains separate.
        vec3 interreflection=base*incoming*((1.-.04)*(1.-.04)/PI);
        imageStore(diffuse_image,xy,vec4(max(reflected+authored_fill+interreflection,vec3(0)),1));
        imageStore(specular_image,xy,vec4(0));return;
    }
        if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        imageStore(output_image,xy,vec4(max(imageLoad(diffuse_image,xy).rgb+imageLoad(specular_image,xy).rgb,vec3(0)),1));
    }
}
