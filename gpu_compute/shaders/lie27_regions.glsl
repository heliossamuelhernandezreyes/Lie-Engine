#[compute]
#version 450
// The visible representation consists of captured samples. Vertex/triangle
// buffers bind and deform those samples; they are never rasterized.
layout(local_size_x=64) in;
struct Vertex { vec4 position_weight; vec4 lid; vec4 jaw; vec4 normal_rest; vec4 normal_closed; vec4 normal_arc; };
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
    vec4 tissue0; vec4 reserved; vec4 tissue1; vec4 tissue2; vec4 tissue3;
} parameters;
layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=10) uniform image2D blur_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;
layout(rgba32f,set=0,binding=12) uniform image2D final_image;
layout(set=0,binding=13,std430) buffer Shadow { uint v[]; } shadow;
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=14,std430) buffer Accumulated { Accumulator v[]; } accumulated;
struct Bone {vec4 real;vec4 dual;};
layout(set=0,binding=15,std430) readonly buffer Bones {Bone v[];} bones;
layout(set=0,binding=16,std430) readonly buffer FaceControls {vec4 values0;vec4 values1;} face;
struct Region {vec4 center_channel;vec4 radii;vec4 delta;};
layout(set=0,binding=17,std430) readonly buffer FacialRegions {Region v[];} regions;
layout(set=0,binding=18,std430) readonly buffer OcularMaterial {
    vec4 sclera;vec4 iris;vec4 pupil;vec4 shape;vec4 right_center;vec4 left_center;
} ocular;
float channel_value(int c) {return c<4?face.values0[c]:face.values1[c-4];}
vec3 facial_position(vec3 p,out mat3 differential) {
    differential=mat3(1);vec3 result=p;
    if(p.y<1.42) return p;
    for(int k=0;k<9;k++) {
        Region r=regions.v[k];float control=channel_value(int(r.center_channel.w));
        if(control==0) continue;
        vec3 d=p-r.center_channel.xyz;float t=max(1-dot(d/r.radii.xyz,d/r.radii.xyz),0);
        vec3 delta=r.delta.xyz*control;result+=delta*t*t*t;
        vec3 gradient=-6*t*t*d/(r.radii.xyz*r.radii.xyz);
        differential+=outerProduct(delta,gradient);
    }
    return result;
}
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=1024;

Sample source_sample(uint i) { return samples.v[i]; }
mat3 yaw_rotation(float a) {float c=cos(a),s=sin(a);return mat3(c,0,-s,0,1,0,s,0,c);}
// Normalized dual quaternion blending, with antipodal sign correction.
// xyzw quaternions. Implemented from the published method, no vendor code.
vec4 qmul(vec4 a,vec4 b) {
    return vec4(a.w*b.xyz+b.w*a.xyz+cross(a.xyz,b.xyz),a.w*b.w-dot(a.xyz,b.xyz));
}
vec3 skin(vec3 p,Bone a,Bone b,float w,out mat3 rotation) {
    float sign=dot(a.real,b.real)<0?-1:1;
    vec4 r=mix(a.real,b.real*sign,w),d=mix(a.dual,b.dual*sign,w);
    float norm=length(r);r/=norm;d/=norm;
    vec3 x=vec3(1,0,0),y=vec3(0,1,0),z=vec3(0,0,1);
    rotation=mat3(x+2*cross(r.xyz,cross(r.xyz,x)+r.w*x),
                  y+2*cross(r.xyz,cross(r.xyz,y)+r.w*y),
                  z+2*cross(r.xyz,cross(r.xyz,z)+r.w*z));
    return rotation*p+2*qmul(d,vec4(-r.xyz,r.w)).xyz;
}
vec3 skin_sample(Sample s,out mat3 differential) {
    if(s.binding.w<0) {
        uvec3 ids=triangles.v[int(-s.binding.w)-1].xyz;
        vec3 a=vertices.v[ids.x].position_weight.xyz,b=vertices.v[ids.y].position_weight.xyz,c=vertices.v[ids.z].position_weight.xyz;
        vec3 pa=deformed.v[ids.x*2].xyz,pb=deformed.v[ids.y*2].xyz,pc=deformed.v[ids.z*2].xyz;
        vec3 n=normalize(cross(b-a,c-a)),pn=normalize(cross(pb-pa,pc-pa));
        differential=mat3(pb-pa,pc-pa,pn)*inverse(mat3(b-a,c-a,n));
        return pa*s.binding.x+pb*s.binding.y+pc*s.binding.z;
    }
    Bone a=bones.v[int(s.binding.w)],b=bones.v[int(s.material.z)];
    float w=s.material.y;mat3 face_differential=mat3(1);vec3 rest=s.binding.xyz;
    if(s.material.w<2) rest=facial_position(rest,face_differential);
    vec3 p=skin(rest,a,b,w,differential);differential=differential*face_differential;
    if(w>0 && w<1 && dot(s.gray_filter.yzw,s.gray_filter.yzw)>0) {
        // dP/dx = R(w) + dP/dw * gradient(w). This transports normals
        // contravariantly and the full captured footprint covariantly.
        float lo=max(w-.001,0),hi=min(w+.001,1);mat3 unused;
        vec3 derivative=(skin(rest,a,b,hi,unused)-skin(rest,a,b,lo,unused))/(hi-lo);
        differential+=outerProduct(derivative,s.gray_filter.yzw);
    }
    return p;
}
// Pigment is attached to captured skin in source space and follows its rig.
float eyebrow_fibers(vec3 p,vec3 eye_center) {
    if(p.y<eye_center.y+.016 || p.y>eye_center.y+.032 || p.z<eye_center.z+.002)return 0;
    float side=eye_center.x<0?-1.0:1.0;
    float t=(side*p.x-(abs(eye_center.x)-.018))/.038;
    if(t<0 || t>1)return 0;
    float curve=eye_center.y+.020+.0045*sin(PI*t)-.001*t;
    float half_width=.0016*(1-.65*t)+.00035,height=p.y-curve;
    float envelope=(1-smoothstep(half_width*.6,half_width,abs(height)))*smoothstep(0,.08,t)*(1-smoothstep(.91,1,t));
    if(envelope<=0)return 0;
    float phase=(side*p.x-mix(-.2,.85,t)*height)/.00055;
    float fiber=1-smoothstep(.08,.29,abs(fract(phase)-.5));
    return envelope*(.25+.75*fiber);
}
vec3 base_color(Sample s) {
    if(s.geometry_front.w==10) {
        vec3 center=s.binding.x<0?ocular.right_center.xyz:ocular.left_center.xyz;
        vec3 local=s.binding.xyz-center;float r=length(local.xy);
        if(local.z<ocular.shape.z || r>ocular.shape.x) return ocular.sclera.rgb;
        float angle=atan(local.y,local.x),t=r/ocular.shape.x;
        float fibers=.86+.14*sin(angle*43+sin(angle*7)*2+t*17);
        vec3 iris=ocular.iris.rgb*fibers;
        iris*=mix(1.0,.30,smoothstep(.88,1.0,t));
        float pupil=smoothstep(ocular.shape.y-.00015,ocular.shape.y+.00015,r);
        return mix(ocular.pupil.rgb,iris,pupil);
    }
    int layer=int(s.material.w);
    vec3 pigment=layer==0?parameters.tissue0.rgb:layer==1?parameters.tissue1.rgb:layer==2?parameters.tissue2.rgb:parameters.tissue3.rgb;
    vec3 color=clamp(s.gray_filter.x*pigment,vec3(0),vec3(1));
    if(layer==0 && s.binding.w>=0 && parameters.reserved.w>.5) {
        float brow=max(eyebrow_fibers(s.binding.xyz,ocular.left_center.xyz),eyebrow_fibers(s.binding.xyz,ocular.right_center.xyz));
        color=mix(color,vec3(.022,.012,.007),brow);
    }
    return color;
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
float ocular_depth(uint index,Projection p,vec3 ray,float plane_depth) {
    if(samples.v[index].geometry_front.w!=10)return plane_depth;
    // A captured ocular disk is curved. Its tangent plane can protrude at
    // grazing rays even inside its finite footprint. Use a local osculating
    // sphere anchored to the captured position and native geometric normal.
    vec3 n=p.geometry.xyz*p.geometry.w;float radius=.01545;
    vec3 center=p.world.xyz-n*radius,d=parameters.eye.xyz-center;
    float a=dot(ray,ray),b=dot(d,ray),c=dot(d,d)-radius*radius,disc=b*b-a*c;
    if(disc<0)return plane_depth;
    float root=sqrt(disc),near=(-b-root)/a,far=(-b+root)/a;
    return abs(near-plane_depth)<abs(far-plane_depth)?near:far;
}
bool lid_support(uint index,vec3 hit) {
    Sample s=samples.v[index];if(s.binding.w>=0)return true;
    uvec3 ids=triangles.v[int(-s.binding.w)-1].xyz;
    if(vertices.v[ids.x].normal_rest.w!=1)return true;
    vec3 a=deformed.v[ids.x*2].xyz,b=deformed.v[ids.y*2].xyz,c=deformed.v[ids.z*2].xyz;
    vec3 u=b-a,v=c-a,p=hit-a;float uv=dot(u,v),den=dot(u,u)*dot(v,v)-uv*uv;
    if(abs(den)<1e-20)return false;
    float y=(dot(v,v)*dot(p,u)-uv*dot(p,v))/den;
    float z=(dot(u,u)*dot(p,v)-uv*dot(p,u))/den;
    return y>=-.0001 && z>=-.0001 && y+z<=1.0001;
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
    uint i=gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,pixels=uint(parameters.counts.z*parameters.counts.w);
    int stage=phase.value.x;
    if(stage==0) {
        if(i>=uint(parameters.counts.y)) return;
        Vertex v=vertices.v[i];mat3 unused;
        vec3 rest=v.position_weight.xyz;
        if(v.normal_rest.w==1) {
            float blink=channel_value(1-int(v.jaw.w));
            rest+=v.jaw.xyz*blink+v.normal_rest.xyz*(4*blink*(1-blink));
        }
        mat3 ignored;rest=facial_position(rest,ignored);
        deformed.v[2*i]=vec4(skin(rest,bones.v[int(v.position_weight.w)],bones.v[int(v.lid.x)],v.lid.y,unused),1);
        vec3 smooth_normal=vec3(0,1,0);
        if(v.normal_rest.w==1) {
            float blink=channel_value(1-int(v.jaw.w));
            smooth_normal=mix(v.normal_closed.xyz,v.normal_arc.xyz,blink);
            mat3 cofactor=mat3(cross(ignored[1],ignored[2]),cross(ignored[2],ignored[0]),cross(ignored[0],ignored[1]));
            smooth_normal=normalize(unused*cofactor*smooth_normal);
        }
        deformed.v[2*i+1]=vec4(smooth_normal,0);
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
            Sample s=source_sample(i);
            if((int(parameters.pose.z)&(1<<int(s.material.w)))==0 || ((int(parameters.pose.z)&1)!=0 && s.geometry_front.w==20)) {
                projected.v[i]=Projection(vec4(0),vec4(0),vec4(0),vec4(0),vec4(0),vec4(0));return;
            }
            vec3 world,normal,geometry_normal,footprint_normal;
            mat3 footprint_transform=mat3(1);
            float radius=s.normal_radius.w;
            // A rigid bone transforms interiors exactly; joint weights transport
            // the captured position and its local surface differential.
            mat3 differential;
            world=skin_sample(s,differential);
            mat3 normal_transform=mat3(cross(differential[1],differential[2]),cross(differential[2],differential[0]),cross(differential[0],differential[1]));
            normal=normalize(normal_transform*s.normal_radius.xyz);
            if(s.binding.w<0) {
                uvec3 ids=triangles.v[int(-s.binding.w)-1].xyz;
                if(vertices.v[ids.x].normal_rest.w==1)
                    normal=normalize(deformed.v[ids.x*2+1].xyz*s.binding.x+deformed.v[ids.y*2+1].xyz*s.binding.y+deformed.v[ids.z*2+1].xyz*s.binding.z);
            }
            geometry_normal=normalize(normal_transform*s.geometry_front.xyz);
            footprint_normal=s.geometry_front.xyz;footprint_transform=differential;
            vec3 tangent=normalize(cross(footprint_normal,abs(footprint_normal.y)<.9?vec3(0,1,0):vec3(1,0,0)));
            vec3 footprint_u=footprint_transform*tangent*radius;
            vec3 footprint_v=footprint_transform*cross(footprint_normal,tangent)*radius;
            if(s.binding.w<0) {
                uvec3 ids=triangles.v[int(-s.binding.w)-1].xyz;
                if(vertices.v[ids.x].normal_rest.w==1 && s.gray_filter.y>0) {
                    float a=sqrt(s.gray_filter.y),b=s.gray_filter.z/a;
                    float c=sqrt(max(s.gray_filter.w-b*b,1e-20));
                    vec3 bitangent=cross(footprint_normal,tangent);
                    footprint_u=footprint_transform*(tangent*a+bitangent*b);
                    footprint_v=footprint_transform*bitangent*c;
                }
            }
            vec3 delta=world-parameters.eye.xyz;float depth=dot(delta,parameters.forward.xyz);
            float front=dot(geometry_normal,normalize(parameters.eye.xyz-world));
            float normal_sign=front<0?-1:1;
            // Soft medical surfaces are double-sided after a fold. Keep the
            // source surface visible and orient its lighting toward the viewer.
            if(s.material.w!=2 && front<0) {front=-front;geometry_normal=-geometry_normal;normal=-normal;}
            p.world=vec4(world,1);p.normal=vec4(normal,front);p.screen=vec4(0);p.gradient=vec4(0);p.geometry=vec4(geometry_normal,normal_sign);p.ellipse=vec4(0);
            p.gradient.z=sqrt(dot(footprint_u,footprint_u)+dot(footprint_v,footprint_v));
            vec3 light_delta=world-parameters.light.xyz;float light_depth=dot(light_delta,parameters.shadow_forward.xyz);
            float light_front=dot(geometry_normal,normalize(-light_delta));
            if(s.material.w!=2)light_front=abs(light_front);
            if(light_depth>.001 && light_front>.05) {
                vec2 xy=project(world,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
                // Each captured footprint lies on its geometric tangent plane.
                // Constant center depth across a footprint causes striped self-
                // shadows on inclined skin even when the samples are coplanar.
                float plane=dot(geometry_normal,light_delta);
                vec2 gradient=vec2(2*1.25*dot(geometry_normal,parameters.shadow_right.xyz),-2*1.25*dot(geometry_normal,parameters.shadow_up.xyz))/(float(SHADOW_SIZE)*plane);
                vec2 su=project(world+footprint_u,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE))-xy;
                vec2 sv=project(world+footprint_v,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE))-xy;
                float xx=dot(vec2(su.x,sv.x),vec2(su.x,sv.x))+(s.material.w==2?.04:.20)*pow(clamp(abs(light_front),0,1),4);
                float yy=dot(vec2(su.y,sv.y),vec2(su.y,sv.y))+(s.material.w==2?.04:.20)*pow(clamp(abs(light_front),0,1),4);
                float off=su.x*su.y+sv.x*sv.y,det=max(xx*yy-off*off,1e-8);
                int bound=int(ceil(clamp(sqrt(max(xx,yy)),.5,16)));
                for(int y=-bound;y<=bound;y++) for(int x=-bound;x<=bound;x++) {
                    ivec2 pixel=ivec2(xy)+ivec2(x,y);
                    vec2 q=vec2(pixel)+.5-xy;
                    if((q.x*q.x*yy-2*q.x*q.y*off+q.y*q.y*xx)/det>1)continue;
                    float plane_depth=1.0/(1.0/light_depth+dot(gradient,vec2(pixel)+.5-xy));
                    vec2 uv=(vec2(pixel)+.5)/float(SHADOW_SIZE);
                    vec3 ray=parameters.shadow_forward.xyz+parameters.shadow_right.xyz*((2*uv.x-1)*1.25)+parameters.shadow_up.xyz*((1-2*uv.y)*1.25);
                    float footprint=max(length(footprint_u),length(footprint_v))+light_depth*1.25/float(SHADOW_SIZE);
                    // A tangent plane is local, not an unbounded occluder.
                    // At grazing angles a single shadow texel can intersect it
                    // centimeters away from the captured skin sample.
                    vec3 hit=parameters.light.xyz+ray*plane_depth;
                    bool local_hit=length(hit-world)<=footprint && lid_support(i,hit);
                    if(local_hit && plane_depth>.001 && !isnan(plane_depth) && !isinf(plane_depth) && all(greaterThanEqual(pixel,ivec2(0))) && all(lessThan(pixel,ivec2(SHADOW_SIZE)))) atomicMin(shadow.v[pixel.y*SHADOW_SIZE+pixel.x],floatBitsToUint(plane_depth));
                }
            }
            if(depth>parameters.lens.z && depth<parameters.lens.w && front>(s.material.w==0?.003:.03)) {
                vec2 xy=project(world,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw));
                // Project the captured surface disk, then convolve its
                // covariance with a subpixel reconstruction footprint.
                vec2 u=project(world+footprint_u,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                vec2 v=project(world+footprint_v,parameters.eye.xyz,parameters.right.xyz,parameters.up.xyz,parameters.forward.xyz,parameters.lens.x,vec2(parameters.counts.zw))-xy;
                float xx=u.x*u.x+v.x*v.x+(s.material.w==2?.04:.20)*pow(clamp(front,0,1),4),yy=u.y*u.y+v.y*v.y+(s.material.w==2?.04:.20)*pow(clamp(front,0,1),4),off=u.x*u.y+v.x*v.y;
                float determinant=max(xx*yy-off*off,1e-8);
                p.ellipse=vec4(yy/determinant,-off/determinant,xx/determinant,0);
                // Adaptive lid captures cover an entire source triangle.
                // At face zoom their valid disk can exceed the general
                // 16-pixel splat budget. Keep its support before the exact
                // triangle clip; truncating it leaves uncovered lid corners.
                bool captured_lid=false;
                if(s.binding.w<0) {
                    uvec3 ids=triangles.v[int(-s.binding.w)-1].xyz;
                    captured_lid=vertices.v[ids.x].normal_rest.w==1;
                }
                p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,captured_lid?64.0:16.0));
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
            // EWA includes a subpixel filter, but it must not turn a local
            // captured disk into an unbounded plane at a grazing angle.
            // Otherwise a scleral tangent can appear in front of closed skin.
            vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
            vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
            depth=ocular_depth(i,p,ray,depth);
            float padding=depth*parameters.lens.x/float(parameters.counts.w);
            if(length(parameters.eye.xyz+ray*depth-p.world.xyz)>p.gradient.z+padding)continue;
            if(!lid_support(i,parameters.eye.xyz+ray*depth))continue;
            uint pixel=uint(xy.y*parameters.counts.z+xy.x),bits=floatBitsToUint(depth);
            if(stage==2) atomicMin(depths.v[pixel],bits);
            else if(stage==3) {
                if(depths.v[pixel]==bits) atomicMin(winners.v[pixel],i);
            } else {
                float nearest=uintBitsToFloat(depths.v[pixel]);
                // Do not average across separate surfaces or the far side of
                // a fold. At most 3 M samples * max weight 256 fits uint32.
                if(abs(depth-nearest)>.00065) continue;
                uint owner=winners.v[pixel];if(owner==EMPTY)continue;
                Sample s=source_sample(i);
            if((int(parameters.pose.z)&(1<<int(s.material.w)))==0) {
                projected.v[i]=Projection(vec4(0),vec4(0),vec4(0),vec4(0),vec4(0),vec4(0));return;
            }
                if(s.material.w!=source_sample(owner).material.w || ((s.geometry_front.w==10)!=(source_sample(owner).geometry_front.w==10)))continue;
                float g=exp(-2*footprint_distance(p,vec2(xy)+.5));
                uint weight=max(uint(round(256*g)),1u);vec3 base=base_color(s);
                uvec3 color=uvec3(round(base*float(weight)));
                uvec3 normal=uvec3(round((p.normal.xyz*.5+.5)*float(weight)));
                atomicAdd(accumulated.v[pixel].color_weight.x,color.x);atomicAdd(accumulated.v[pixel].color_weight.y,color.y);atomicAdd(accumulated.v[pixel].color_weight.z,color.z);atomicAdd(accumulated.v[pixel].color_weight.w,weight);
                float roughness=s.geometry_front.w==10?ocular.sclera.w:s.material.x;
                atomicAdd(accumulated.v[pixel].normal_roughness.x,normal.x);atomicAdd(accumulated.v[pixel].normal_roughness.y,normal.y);atomicAdd(accumulated.v[pixel].normal_roughness.z,normal.z);atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(clamp(roughness,0,1)*float(weight))));
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
        if(parameters.options.z>.5) {
            imageStore(diffuse_image,xy,vec4(1));imageStore(specular_image,xy,vec4(0));return;
        }
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        vec3 delta=parameters.light.xyz-p;float distance2=max(dot(delta,delta),.0001);vec3 l=normalize(delta);
        float nl=max(dot(n,l),0),nv=max(dot(n,v),1e-5);
        float shadow_factor=parameters.options.x>.5?visibility(p+point.geometry.xyz*.0007,point.geometry.xyz):1;
        vec3 li=parameters.light_color.rgb*parameters.light.w/(4*PI*distance2)*shadow_factor;
        float roughness=clamp(float(acc.normal_roughness.w)/weight*parameters.options.y,s.geometry_front.w==10?.08:.15,.95),alpha=roughness*roughness,a2=alpha*alpha;
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
        vec3 irradiance=parameters.pose.w>0?mix(original,scatter(xy,false),0.0):original;
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        vec3 radiance=max(base*irradiance+imageLoad(specular_image,xy).rgb,vec3(0));
        imageStore(output_image,xy,vec4(radiance,1));
    }
}
