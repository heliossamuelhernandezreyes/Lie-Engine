#[compute]
#version 450
// LIE robot: immutable PBR captures, articulated rigid parts and curve-warped cables.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; vec4 shading; };
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
struct Knot { vec4 center; vec4 normal; vec4 tangent; };
layout(set=0,binding=14,std430) readonly buffer CableFrames { Knot v[]; } cables;
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
void cable_frame(int curve,float t,out vec3 c,out vec3 n,out vec3 binormal,out vec3 tangent) {
    float v=clamp(t,0,1)*15;int k=min(int(v),14);float f=v-float(k);
    Knot a=cables.v[curve*16+k],b=cables.v[curve*16+k+1];float step_length=a.tangent.w/15;
    float f2=f*f,f3=f2*f;
    c=(2*f3-3*f2+1)*a.center.xyz+(f3-2*f2+f)*a.tangent.xyz*step_length+(-2*f3+3*f2)*b.center.xyz+(f3-f2)*b.tangent.xyz*step_length;
    tangent=normalize(mix(a.tangent.xyz,b.tangent.xyz,f));
    n=mix(a.normal.xyz,b.normal.xyz,f);n=normalize(n-tangent*dot(n,tangent));binormal=cross(n,tangent);
}
vec3 cable_position(int curve,vec3 local,float radius_scale) {
    vec3 c,n,b,t;cable_frame(curve,local.y*2+.5,c,n,b,t);
    return c+n*local.x*radius_scale+b*local.z*radius_scale;
}
mat3 deformation(Instance inst,vec3 local,out vec3 world) {
    if(inst.meta.y<0) {
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);world=basis*local+inst.origin.xyz;return basis;
    }
    int curve=int(inst.meta.y);float scale=inst.meta.z;vec3 c,n,b,t;
    cable_frame(curve,local.y*2+.5,c,n,b,t);world=c+n*local.x*scale+b*local.z*scale;
    float epsilon=.0003;float lo=max(local.y-epsilon,-.25),hi=min(local.y+epsilon,.25);
    vec3 derivative=(cable_position(curve,vec3(local.x,hi,local.z),scale)-cable_position(curve,vec3(local.x,lo,local.z),scale))/max(hi-lo,.00001);
    return mat3(n*scale,derivative,b*scale);
}
bool covered(Projection p,vec2 xy) {
    if(footprint_distance(p,xy)>1) return false;
    Sample s=samples.v[uint(p.gradient.w)];Instance inst=instances.v[uint(p.gradient.z)];
    vec2 uv=xy/vec2(parameters.counts.zw);
    vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
    vec3 center;mat3 jacobian=deformation(inst,s.position_radius.xyz,center);
    vec3 local=s.position_radius.xyz+inverse(jacobian)*(parameters.eye.xyz+ray*pixel_depth(p,xy)-center);
    vec3 n=abs(s.normal_gray.xyz);vec2 q=n.x>=n.y && n.x>=n.z?local.zy:n.y>=n.z?local.xz:local.xy;
    return all(greaterThanEqual(q,s.support.xy-vec2(.000003))) && all(lessThanEqual(q,s.support.zw+vec2(.000003)));
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
    vec3 tint=int(s.attributes.x)==1?parameters.iris.rgb:vec3(1);
    return clamp(s.albedo.rgb*tint*inst.tint.rgb*(1+v),vec3(0),vec3(1));
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
            vec3 world;mat3 jacobian=deformation(inst,local,world);
            vec3 n=normalize(transpose(inverse(jacobian))*s.normal_gray.xyz);
            vec3 shade=normalize(transpose(inverse(jacobian))*s.shading.xyz);
            radius*=max(length(jacobian[0]),max(length(jacobian[1]),length(jacobian[2])));
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(n,normalize(-delta));
            p.world=vec4(world,1);p.normal=vec4(shade,front);p.screen=vec4(0);p.gradient=vec4(0,0,float(job.z),float(sid));p.geometry=vec4(n,s.attributes.x);p.ellipse=vec4(0);
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
                p.ellipse=vec4(yy/det,-off/det,xx/det,0);p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,32));
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
        Accumulator acc=accumulated.v[i];float weight=max(float(acc.color_weight.w),1);
        vec3 base=vec3(acc.color_weight.xyz)/weight;
        vec3 n=normalize(vec3(acc.normal_roughness.xyz)/weight*2-1);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        vec3 delta=parameters.light.xyz-p;float distance2=max(dot(delta,delta),.0001);vec3 l=normalize(delta);
        float nl=max(dot(n,l),0),nv=max(dot(n,v),1e-5);
        float shadow_factor=parameters.options.x>.5?visibility(p+point.geometry.xyz*parameters.options.z*.45,point.geometry.xyz):1;
        vec3 li=parameters.light_color.rgb*parameters.light.w/(4*PI*distance2)*shadow_factor;
        Sample material=samples.v[uint(point.gradient.w)];Instance object=instances.v[uint(point.gradient.z)];
        float roughness=clamp(float(acc.normal_roughness.w)/weight*parameters.options.y,.12,.95),alpha=roughness*roughness,a2=alpha*alpha;
        float metal=clamp(material.attributes.w,0,1);vec3 F0=mix(vec3(.04),base,metal);
        vec3 h=normalize(v+l);float nh=max(dot(n,h),0),vh=max(dot(v,h),0),denom=nh*nh*(a2-1)+1;
        vec3 F=F0+(vec3(1)-F0)*pow(1-vh,5);
        float D=a2/(PI*denom*denom),G=1/(1+lambda(nv,a2)+lambda(nl,a2));
        vec3 specular=li*F*D*G/(4*nv)*(nl>0?1.0:0.0);
        // Original analytic studio environment, recalculated from the current
        // view and captured shading normal. Reflections are never baked RGB.
        vec3 r=reflect(-v,n);float angle=parameters.settings.z;
        r=mat3(cos(angle),0,-sin(angle),0,1,0,sin(angle),0,cos(angle))*r;
        vec3 sky=mix(vec3(.075,.085,.10),vec3(.58,.68,.82),clamp(r.y*.5+.5,0,1));
        float width=.025+roughness*roughness*.75;
        vec3 env=sky*.50;
        env+=vec3(2.8,3.2,3.7)*exp((dot(r,normalize(vec3(-.7,.8,.5)))-1)/width);
        env+=vec3(1.8,.95,.45)*exp((dot(r,normalize(vec3(.8,.35,-.6)))-1)/(width*1.5));
        env+=vec3(.28,.65,1.15)*exp((dot(r,normalize(vec3(-.4,.15,-1)))-1)/(width*2));
        vec3 envF=F0+(max(vec3(1-roughness),F0)-F0)*pow(1-nv,5);
        specular+=env*envF*parameters.settings.w;
        vec3 ambient=parameters.ambient.rgb*.20;
        vec3 irradiance=(1-metal)*(vec3(1)-F)*(li*nl/PI+ambient);
        specular+=base*material.albedo.w*object.tint.w;
        imageStore(diffuse_image,xy,vec4(irradiance,1));imageStore(specular_image,xy,vec4(specular,1));return;
    }
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        vec3 result=parameters.settings.w<0?base:max(base*imageLoad(diffuse_image,xy).rgb+imageLoad(specular_image,xy).rgb,vec3(0));
        imageStore(output_image,xy,vec4(result,1));
    }
}
