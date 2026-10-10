#[compute]
#version 450
// The visible representation consists of captured samples. Vertex/triangle
// buffers bind and deform those samples; they are never rasterized.
layout(local_size_x=64) in;
struct Vertex { vec4 position_weight; vec4 lid; vec4 jaw; };
struct Sample { vec4 binding; vec4 normal_radius; vec4 gray_filter; vec4 material; vec4 geometry_front; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; };
layout(set=0,binding=0,std430) readonly buffer Vertices { Vertex v[]; } vertices;
layout(set=0,binding=1,std430) readonly buffer Triangles { uvec4 v[]; } triangles;
layout(set=0,binding=2,std430) readonly buffer Samples { Sample v[]; } samples;
layout(set=0,binding=3,std430) buffer Deformed { vec4 v[]; } deformed;
layout(set=0,binding=4,std430) buffer Projected { Projection v[]; } projected;
layout(set=0,binding=5,std430) buffer Depth { uint v[]; } depths;
layout(set=0,binding=6,std430) buffer Winner { uint v[]; } winners;
layout(set=0,binding=7,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; vec4 pivot;
    ivec4 counts; vec4 pose; vec4 light; vec4 light_color; vec4 ambient;
    vec4 options; vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
} parameters;
layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=10) uniform image2D blur_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;
layout(set=0,binding=12,std430) buffer Shadow { uint v[]; } shadow;
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=256;

vec2 project(vec3 p,vec3 eye,vec3 right,vec3 up,vec3 forward,float tangent,vec2 size) {
    vec3 d=p-eye;float z=dot(d,forward);
    return vec2((dot(d,right)/(z*tangent)+1)*.5,(1-dot(d,up)/(z*tangent))*.5)*size;
}
bool inside(ivec2 p) { return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,parameters.counts.zw)); }
float pixel_depth(Projection p,vec2 xy) {
    return 1.0/(1.0/p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));
}
bool covered(Projection p,vec2 xy) { return dot(xy-p.screen.xy,xy-p.screen.xy)<=p.screen.w*p.screen.w; }
float lambda(float cosine,float a2) {
    return .5*(sqrt(1+a2*max(1-cosine*cosine,0)/max(cosine*cosine,1e-8))-1);
}
float visibility(vec3 p) {
    vec3 d=p-parameters.light.xyz;float z=dot(d,parameters.shadow_forward.xyz);
    if(z<=.001) return 1;
    vec2 uv=project(p,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
    if(any(lessThan(uv,vec2(1))) || any(greaterThan(uv,vec2(SHADOW_SIZE-2)))) return 1;
    float result=0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=ivec2(uv)+ivec2(x,y);
        float stored=uintBitsToFloat(shadow.v[q.y*SHADOW_SIZE+q.x]);
        result+=z<=stored+.0035?1.0:0.0;
    }
    return result*.25;
}
vec3 to_srgb(vec3 p) {
    return mix(p*12.92,1.055*pow(max(p,vec3(0)),vec3(1.0/2.4))-.055,greaterThan(p,vec3(.0031308)));
}
vec3 scatter(ivec2 p,bool horizontal) {
    uint index=uint(p.y*parameters.counts.z+p.x),owner=winners.v[index];
    if(owner==EMPTY) return vec3(0);
    vec3 center=projected.v[owner].normal.xyz;
    float depth=uintBitsToFloat(depths.v[index]);
    vec3 total=vec3(0),weight_sum=vec3(0);
    float strength=parameters.pose.w*samples.v[owner].material.z;
    for(int k=-6;k<=6;k++) {
        ivec2 q=p+(horizontal?ivec2(k,0):ivec2(0,k));
        if(!inside(q)) continue;
        uint qi=uint(q.y*parameters.counts.z+q.x),qo=winners.v[qi];
        if(qo==EMPTY || abs(uintBitsToFloat(depths.v[qi])-depth)>.006 || dot(center,projected.v[qo].normal.xyz)<.7) continue;
        vec3 sigma=vec3(2.8,1.5,.9)*max(strength*4,.01);
        vec3 weight=exp(-float(k*k)/(2*sigma*sigma));
        vec3 value=horizontal?imageLoad(diffuse_image,q).rgb:imageLoad(blur_image,q).rgb;
        total+=weight*value;weight_sum+=weight;
    }
    return total/max(weight_sum,vec3(1e-8));
}

void main() {
    uint i=gl_GlobalInvocationID.x,pixels=uint(parameters.counts.z*parameters.counts.w);
    int stage=phase.value.x;
    if(stage==0) {
        if(i>=uint(parameters.counts.y)) return;
        Vertex v=vertices.v[i];vec3 p=v.position_weight.xyz+v.lid.xyz*parameters.pose.y+v.jaw.xyz*parameters.pose.z;
        float c=cos(parameters.pose.x),s=sin(parameters.pose.x);vec3 q=p-parameters.pivot.xyz;
        vec3 rotated=vec3(c*q.x+s*q.z,q.y,-s*q.x+c*q.z)+parameters.pivot.xyz;
        deformed.v[i]=vec4(mix(p,rotated,v.position_weight.w),1);
        return;
    }
    if(stage==1) {
        if(i<pixels) {depths.v[i]=0x7f7fffffu;winners.v[i]=EMPTY;}
        if(i<uint(SHADOW_SIZE*SHADOW_SIZE)) shadow.v[i]=0x7f7fffffu;
        return;
    }
    if(stage==2 || stage==3) {
        if(i>=uint(parameters.counts.x)) return;
        Projection p;
        if(stage==2) {
            Sample s=samples.v[i];uvec3 ids=triangles.v[int(s.binding.w)].xyz;
            vec3 a=deformed.v[ids.x].xyz,b=deformed.v[ids.y].xyz,c=deformed.v[ids.z].xyz;
            vec3 ar=vertices.v[ids.x].position_weight.xyz,br=vertices.v[ids.y].position_weight.xyz,cr=vertices.v[ids.z].position_weight.xyz;
            vec3 rest_cross=cross(br-ar,cr-ar),now_cross=cross(b-a,c-a);
            mat3 rest=mat3(br-ar,cr-ar,normalize(rest_cross));
            mat3 now=mat3(b-a,c-a,normalize(now_cross));
            mat3 normal_matrix=transpose(inverse(now*inverse(rest)));
            vec3 normal=normalize(normal_matrix*s.normal_radius.xyz);
            vec3 geometry_normal=normalize(normal_matrix*s.geometry_front.xyz);
            vec3 world=a*s.binding.x+b*s.binding.y+c*s.binding.z;
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(geometry_normal,normalize(parameters.eye.xyz-world));
            p.world=vec4(world,1);p.normal=vec4(normal,front);p.screen=vec4(0);p.gradient=vec4(0);
            vec3 light_delta=world-parameters.light.xyz;float light_depth=dot(light_delta,parameters.shadow_forward.xyz);
            if(light_depth>.001) {
                vec2 xy=project(world,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
                for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
                    ivec2 pixel=ivec2(xy)+ivec2(x,y);
                    if(all(greaterThanEqual(pixel,ivec2(0))) && all(lessThan(pixel,ivec2(SHADOW_SIZE)))) atomicMin(shadow.v[pixel.y*SHADOW_SIZE+pixel.x],floatBitsToUint(light_depth));
                }
            }
            if(depth>parameters.lens.z && depth<parameters.lens.w && front>.03) {
                vec2 xy=project(world,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw));
                float radius=clamp(s.normal_radius.w*float(parameters.counts.w)/(2*depth*parameters.lens.x)+.45,.75,2.75);
                p.screen=vec4(xy,depth,radius);
                float plane=dot(geometry_normal,delta);
                if(abs(plane)>1e-7) p.gradient.xy=vec2(2*parameters.lens.x*dot(geometry_normal,parameters.right.xyz)/float(parameters.counts.z),-2*parameters.lens.x*dot(geometry_normal,parameters.up.xyz)/float(parameters.counts.w))/plane;
            }
            projected.v[i]=p;
        } else p=projected.v[i];
        if(p.screen.z<=0) return;
        for(int y=-3;y<=3;y++) for(int x=-3;x<=3;x++) {
            ivec2 xy=ivec2(floor(p.screen.xy))+ivec2(x,y);
            if(!inside(xy) || !covered(p,vec2(xy)+.5)) continue;
            float depth=pixel_depth(p,vec2(xy)+.5);
            if(depth<=parameters.lens.z || isnan(depth) || isinf(depth)) continue;
            uint pixel=uint(xy.y*parameters.counts.z+xy.x),bits=floatBitsToUint(depth);
            if(stage==2) atomicMin(depths.v[pixel],bits);
            else if(depths.v[pixel]==bits) atomicMin(winners.v[pixel],i);
        }
        return;
    }
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {imageStore(diffuse_image,xy,vec4(0));imageStore(specular_image,xy,vec4(0));return;}
        Sample s=samples.v[owner];Projection point=projected.v[owner];
        vec3 base=s.gray_filter.x*s.gray_filter.yzw;
        vec3 p=point.world.xyz,n=point.normal.xyz,v=normalize(parameters.eye.xyz-p);
        vec3 delta=parameters.light.xyz-p;float distance2=max(dot(delta,delta),.0001);vec3 l=normalize(delta);
        float nl=max(dot(n,l),0),nv=max(dot(n,v),1e-5);
        float shadow_factor=parameters.options.x>.5?visibility(p+n*.001):1;
        vec3 li=parameters.light_color.rgb*parameters.light.w/(4*PI*distance2)*shadow_factor;
        float roughness=clamp(s.material.x*parameters.options.y,.15,.95),alpha=roughness*roughness,a2=alpha*alpha;
        vec3 h=normalize(v+l);float nh=max(dot(n,h),0),vh=max(dot(v,h),0),denom=nh*nh*(a2-1)+1;
        vec3 F=vec3(.028)+(vec3(1)-vec3(.028))*pow(1-vh,5);
        float D=a2/(PI*denom*denom),G=1/(1+lambda(nv,a2)+lambda(nl,a2));
        vec3 specular=li*F*D*G/(4*nv)*(nl>0?1.0:0.0);
        vec3 ambient=parameters.ambient.rgb*(.55+.45*max(n.y,0));
        vec3 diffuse=(vec3(1)-F)*base*(li*nl+ambient)/PI;
        imageStore(diffuse_image,xy,vec4(diffuse*(1-s.material.y),1));
        imageStore(specular_image,xy,vec4(specular*(1-s.material.y),1));return;
    }
    if(stage==5) {imageStore(blur_image,xy,vec4(scatter(xy,true),owner==EMPTY?0:1));return;}
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        vec3 diffuse=parameters.pose.w>0?scatter(xy,false):imageLoad(diffuse_image,xy).rgb;
        vec3 radiance=max((diffuse+imageLoad(specular_image,xy).rgb)*parameters.ambient.w,vec3(0));
        vec3 tone=radiance/(vec3(1)+radiance);
        imageStore(output_image,xy,vec4(to_srgb(tone),1));
    }
}
