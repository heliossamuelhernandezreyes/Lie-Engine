#[compute]
#version 450
// The visible representation consists of captured samples. Vertex/triangle
// buffers bind and deform those samples; they are never rasterized.
layout(local_size_x=64) in;
struct Vertex { vec4 position_weight; vec4 lid; vec4 jaw; };
struct Sample { vec4 binding; vec4 normal_radius; vec4 gray_filter; vec4 material; vec4 geometry_front; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
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
    vec4 skin; vec4 iris; vec4 gaze; vec4 left_anchor; vec4 right_anchor;
} parameters;
layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=10) uniform image2D blur_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;
layout(rgba32f,set=0,binding=12) uniform image2D final_image;
layout(set=0,binding=13,std430) buffer Shadow { uint v[]; } shadow;
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=14,std430) buffer Accumulated { Accumulator v[]; } accumulated;
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;

Sample source_sample(uint i) {
    uint face=uint(parameters.gaze.z),eye=uint(parameters.gaze.w);
    return samples.v[i<face?i:face+(i-face)%eye];
}
mat3 yaw_rotation(float a) {float c=cos(a),s=sin(a);return mat3(c,0,-s,0,1,0,s,0,c);}
mat3 pitch_rotation(float a) {float c=cos(a),s=sin(a);return mat3(1,0,0,0,c,s,0,-s,c);}
vec3 eye_anchor(uint i) {
    vec3 a=(i-uint(parameters.gaze.z))/uint(parameters.gaze.w)==0u?parameters.left_anchor.xyz:parameters.right_anchor.xyz;
    return yaw_rotation(parameters.pose.x)*(a-parameters.pivot.xyz)+parameters.pivot.xyz;
}
vec3 base_color(Sample s) {
    int region=int(s.material.w);vec3 tint=parameters.skin.rgb*s.gray_filter.yzw;
    if(region==1)tint=vec3(.95,.97,1);
    if(region==2)tint=parameters.iris.rgb;
    if(region==3)tint=vec3(.5,.6,.7);
    return clamp(s.gray_filter.x*tint,vec3(0),vec3(1));
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
bool covered(Projection p,vec2 xy) { return footprint_distance(p,xy)<=1; }
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
        result+=(receiver_depth<=0 || receiver_depth<=stored+.0015)?1.0:0.0;
    }
    return result/9;
}
vec3 to_srgb(vec3 p) {
    return mix(p*12.92,1.055*pow(max(p,vec3(0)),vec3(1.0/2.4))-.055,greaterThan(p,vec3(.0031308)));
}
vec3 scatter(ivec2 p,bool horizontal) {
    uint index=uint(p.y*parameters.counts.z+p.x),owner=winners.v[index];
    if(owner==EMPTY) return vec3(0);
    vec3 center=projected.v[owner].geometry.xyz;
    float depth=uintBitsToFloat(depths.v[index]);
    vec3 total=vec3(0),weight_sum=vec3(0);
    // Diffusion has a world-space radius, so zoom and supersampling change
    // pixel widths consistently. Only irradiance diffuses; skin color stays.
    float world_pixel=2*depth*parameters.lens.x/float(parameters.counts.w);
    vec3 sigma=clamp(vec3(.0018,.0009,.00045)*parameters.pose.w/max(world_pixel,1e-8),vec3(.01),vec3(6));
    for(int k=-12;k<=12;k++) {
        ivec2 q=p+(horizontal?ivec2(k,0):ivec2(0,k));
        if(!inside(q)) continue;
        uint qi=uint(q.y*parameters.counts.z+q.x),qo=winners.v[qi];
        if(qo==EMPTY || source_sample(qo).material.w!=source_sample(owner).material.w || abs(uintBitsToFloat(depths.v[qi])-depth)>.004 || dot(center,projected.v[qo].geometry.xyz)<.8) continue;
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
        if(i<pixels) {depths.v[i]=0x7f7fffffu;winners.v[i]=EMPTY;accumulated.v[i].color_weight=uvec4(0);accumulated.v[i].normal_roughness=uvec4(0);}
        if(i<uint(SHADOW_SIZE*SHADOW_SIZE)) shadow.v[i]=0x7f7fffffu;
        return;
    }
    if(stage==2 || stage==3 || stage==8) {
        if(i>=uint(parameters.counts.x)) return;
        Projection p;
        if(stage==2) {
            Sample s=source_sample(i);vec3 world,normal,geometry_normal,footprint_normal;
            mat3 footprint_transform=mat3(1);
            float radius=s.normal_radius.w;
            if(i>=uint(parameters.gaze.z)) {
                vec3 local=s.binding.xyz;float r=length(local.xy);int region=int(s.material.w);
                if(region==2 && r>1e-8) {
                    float nr=parameters.iris.w+(r-.0017)*(.006-parameters.iris.w)/(.006-.0017);
                    local.xy*=nr/r;radius*=max(nr/r,(.006-parameters.iris.w)/(.006-.0017));
                } else if(region==3) {local.xy*=parameters.iris.w/.0017;radius*=parameters.iris.w/.0017;}
                mat3 rotation=yaw_rotation(parameters.pose.x)*yaw_rotation(parameters.gaze.x)*pitch_rotation(parameters.gaze.y);
                world=eye_anchor(i)+rotation*local;normal=normalize(rotation*s.normal_radius.xyz);geometry_normal=normalize(rotation*s.geometry_front.xyz);footprint_normal=geometry_normal;
            } else {
            uvec3 ids=triangles.v[int(s.binding.w)].xyz;
            vec3 a=deformed.v[ids.x].xyz,b=deformed.v[ids.y].xyz,c=deformed.v[ids.z].xyz;
            vec3 ar=vertices.v[ids.x].position_weight.xyz,br=vertices.v[ids.y].position_weight.xyz,cr=vertices.v[ids.z].position_weight.xyz;
            vec3 rest_cross=cross(br-ar,cr-ar),now_cross=cross(b-a,c-a);
            if(dot(rest_cross,rest_cross)<1e-18 || dot(now_cross,now_cross)<1e-18) {p.world=vec4(0);p.screen=vec4(0);projected.v[i]=p;return;}
            mat3 rest=mat3(br-ar,cr-ar,normalize(rest_cross));
            mat3 now=mat3(b-a,c-a,normalize(now_cross));
            mat3 deformation=now*inverse(rest);
            mat3 normal_matrix=transpose(inverse(deformation));
            normal=normalize(normal_matrix*s.normal_radius.xyz);
            // Shading normals are smooth, but a depth footprint belongs to
            // its actual triangle plane. Treating a smoothed vertex normal as
            // that plane invents depth offsets across the closing lid folds.
            geometry_normal=normalize(now_cross);
            footprint_normal=normalize(rest_cross);footprint_transform=deformation;
            world=a*s.binding.x+b*s.binding.y+c*s.binding.z;
            }
            // A captured disk follows the same local affine deformation as
            // its surface attachment. Replacing it with a fixed-size disk
            // leaves holes where a blinking lid stretches between samples.
            vec3 tangent=normalize(cross(footprint_normal,abs(footprint_normal.y)<.9?vec3(0,1,0):vec3(1,0,0)));
            vec3 footprint_u=footprint_transform*tangent*radius;
            vec3 footprint_v=footprint_transform*cross(footprint_normal,tangent)*radius;
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(geometry_normal,normalize(parameters.eye.xyz-world));
            p.world=vec4(world,1);p.normal=vec4(normal,front);p.screen=vec4(0);p.gradient=vec4(0);p.geometry=vec4(geometry_normal,0);p.ellipse=vec4(0);
            vec3 light_delta=world-parameters.light.xyz;float light_depth=dot(light_delta,parameters.shadow_forward.xyz);
            float light_front=dot(geometry_normal,normalize(-light_delta));
            if(light_depth>.001 && light_front>.05) {
                vec2 xy=project(world,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
                // Each captured footprint lies on its geometric tangent plane.
                // Constant center depth across a footprint causes striped self-
                // shadows on inclined skin even when the samples are coplanar.
                float plane=dot(geometry_normal,light_delta);
                vec2 gradient=vec2(2*1.25*dot(geometry_normal,parameters.shadow_right.xyz),-2*1.25*dot(geometry_normal,parameters.shadow_up.xyz))/(float(SHADOW_SIZE)*plane);
                for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
                    ivec2 pixel=ivec2(xy)+ivec2(x,y);
                    float plane_depth=1.0/(1.0/light_depth+dot(gradient,vec2(pixel)+.5-xy));
                    vec2 uv=(vec2(pixel)+.5)/float(SHADOW_SIZE);
                    vec3 ray=parameters.shadow_forward.xyz+parameters.shadow_right.xyz*((2*uv.x-1)*1.25)+parameters.shadow_up.xyz*((1-2*uv.y)*1.25);
                    float footprint=max(length(footprint_u),length(footprint_v))+light_depth*1.25/float(SHADOW_SIZE);
                    // A tangent plane is local, not an unbounded occluder.
                    // At grazing angles a single shadow texel can intersect it
                    // centimeters away from the captured skin sample.
                    bool local_hit=length(parameters.light.xyz+ray*plane_depth-world)<=footprint;
                    if(local_hit && plane_depth>.001 && !isnan(plane_depth) && !isinf(plane_depth) && all(greaterThanEqual(pixel,ivec2(0))) && all(lessThan(pixel,ivec2(SHADOW_SIZE)))) atomicMin(shadow.v[pixel.y*SHADOW_SIZE+pixel.x],floatBitsToUint(plane_depth));
                }
            }
            if(depth>parameters.lens.z && depth<parameters.lens.w && front>.03) {
                vec2 xy=project(world,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw));
                // Project the captured surface disk, then convolve its
                // covariance with a subpixel reconstruction footprint.
                vec2 u=project(world+footprint_u,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                vec2 v=project(world+footprint_v,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                float xx=u.x*u.x+v.x*v.x+.20,yy=u.y*u.y+v.y*v.y+.20,off=u.x*u.y+v.x*v.y;
                float determinant=max(xx*yy-off*off,1e-8);
                p.ellipse=vec4(yy/determinant,-off/determinant,xx/determinant,0);
                p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,16));
                float plane=dot(geometry_normal,delta);
                if(abs(plane)>1e-7) p.gradient.xy=vec2(2*parameters.lens.x*dot(geometry_normal,parameters.right.xyz)/float(parameters.counts.z),-2*parameters.lens.x*dot(geometry_normal,parameters.up.xyz)/float(parameters.counts.w))/plane;
            }
            projected.v[i]=p;
        } else p=projected.v[i];
        if(p.screen.z<=0) return;
        int bound=int(ceil(p.screen.w));
        for(int y=-bound;y<=bound;y++) for(int x=-bound;x<=bound;x++) {
            ivec2 xy=ivec2(floor(p.screen.xy))+ivec2(x,y);
            if(!inside(xy) || !covered(p,vec2(xy)+.5)) continue;
            float depth=pixel_depth(p,vec2(xy)+.5);
            if(depth<=parameters.lens.z || isnan(depth) || isinf(depth)) continue;
            uint pixel=uint(xy.y*parameters.counts.z+xy.x),bits=floatBitsToUint(depth);
            if(stage==2) atomicMin(depths.v[pixel],bits);
            else if(stage==3) {
                if(depths.v[pixel]==bits) atomicMin(winners.v[pixel],i);
            } else {
                float nearest=uintBitsToFloat(depths.v[pixel]);
                // Do not average across separate surfaces or the far side of
                // a fold. One million samples * max weight 256 fits uint32.
                if(abs(depth-nearest)>.00065) continue;
                uint owner=winners.v[pixel];if(owner==EMPTY)continue;
                Sample s=source_sample(i);
                if(s.material.w!=source_sample(owner).material.w)continue;
                float g=exp(-2*footprint_distance(p,vec2(xy)+.5));
                uint weight=max(uint(round(256*g)),1u);vec3 base=base_color(s);
                uvec3 color=uvec3(round(base*float(weight)));
                uvec3 normal=uvec3(round((p.normal.xyz*.5+.5)*float(weight)));
                atomicAdd(accumulated.v[pixel].color_weight.x,color.x);atomicAdd(accumulated.v[pixel].color_weight.y,color.y);atomicAdd(accumulated.v[pixel].color_weight.z,color.z);atomicAdd(accumulated.v[pixel].color_weight.w,weight);
                atomicAdd(accumulated.v[pixel].normal_roughness.x,normal.x);atomicAdd(accumulated.v[pixel].normal_roughness.y,normal.y);atomicAdd(accumulated.v[pixel].normal_roughness.z,normal.z);atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(clamp(s.material.x,0,1)*float(weight))));
            }
        }
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
        Sample s=source_sample(owner);Projection point=projected.v[owner];
        Accumulator acc=accumulated.v[i];float weight=max(float(acc.color_weight.w),1);
        vec3 base=vec3(acc.color_weight.xyz)/weight;
        vec3 n=normalize(vec3(acc.normal_roughness.xyz)/weight*2-1);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        // Captured sphere-normal clearcoat, sharing the scene's depth and light.
        if(s.material.w>0)n=normalize(p-eye_anchor(owner));
        vec3 delta=parameters.light.xyz-p;float distance2=max(dot(delta,delta),.0001);vec3 l=normalize(delta);
        float nl=max(dot(n,l),0),nv=max(dot(n,v),1e-5);
        float shadow_factor=parameters.options.x>.5?visibility(p+point.geometry.xyz*.0007,point.geometry.xyz):1;
        vec3 li=parameters.light_color.rgb*parameters.light.w/(4*PI*distance2)*shadow_factor;
        float roughness=s.material.w>0?.12:clamp(float(acc.normal_roughness.w)/weight*parameters.options.y,.15,.95),alpha=roughness*roughness,a2=alpha*alpha;
        vec3 h=normalize(v+l);float nh=max(dot(n,h),0),vh=max(dot(v,h),0),denom=nh*nh*(a2-1)+1;
        vec3 F=vec3(.04)+(vec3(1)-vec3(.04))*pow(1-vh,5);
        float D=a2/(PI*denom*denom),G=1/(1+lambda(nv,a2)+lambda(nl,a2));
        vec3 specular=li*F*D*G/(4*nv)*(nl>0?1.0:0.0);
        vec3 ambient=parameters.ambient.rgb*.12;
        vec3 irradiance=(vec3(1)-F)*(li*nl/PI+ambient);
        imageStore(diffuse_image,xy,vec4(irradiance,1));
        imageStore(specular_image,xy,vec4(specular,1));return;
    }
    if(stage==5) {imageStore(blur_image,xy,vec4(scatter(xy,true),owner==EMPTY?0:1));return;}
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        vec3 original=imageLoad(diffuse_image,xy).rgb;
        vec3 irradiance=parameters.pose.w>0?mix(original,scatter(xy,false),source_sample(owner).material.z):original;
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        vec3 radiance=max(base*irradiance+imageLoad(specular_image,xy).rgb,vec3(0));
        imageStore(output_image,xy,vec4(radiance,1));
    }
}
