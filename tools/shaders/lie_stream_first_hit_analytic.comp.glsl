#[compute]
#version 450
// V5 correctness experiment: analytic rectangle enumeration, no DDA advances.
// Compensated FP32 camera/instance rays, global first-hit arbitration and
// half-open cell support. Captured-cell reference only; no G-buffer writes.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
struct Proxy {mat4 world;mat4 local;vec4 lo;vec4 hi;vec4 material;uvec4 meta;};
struct View {vec4 eye;vec4 right;vec4 up;vec4 forward;vec4 lens;};
layout(set=0,binding=0,std430) readonly buffer Proxies {Proxy p[];} proxies;
layout(set=0,binding=1,std430) readonly buffer Views {View v[];} views;
layout(set=0,binding=2) uniform sampler2D depth_field;
layout(set=0,binding=3) uniform sampler2DArray normal_field;
layout(set=0,binding=4) uniform sampler2DArray color_field;
layout(set=0,binding=5,std430) readonly buffer Faces {ivec4 rect[];} faces;
layout(set=0,binding=6,std430) readonly buffer CandidateRisk {uint bits[];} risk;
struct HitRecord {vec4 world;vec4 normal;vec4 color;vec4 info;};
layout(set=0,binding=7,std430) buffer HitOut {HitRecord h[];} output_hit;
layout(push_constant,std430) uniform Push {ivec4 value;} push;

precise vec2 ds_sum(float a,float b) {
    precise float s=a+b;
    precise float bb=s-a;
    precise float e=(a-(s-bb))+(b-bb);
    return vec2(s,e);
}
precise vec2 ds_product(float a,float b) {
    precise float hi=a*b;
    precise float lo=fma(a,b,-hi);
    return vec2(hi,lo);
}
precise vec2 ds_add(vec2 a,vec2 b) {
    precise vec2 s=ds_sum(a.x,b.x);
    return ds_sum(s.x,s.y+a.y+b.y);
}
precise vec2 ds_sub(vec2 a,vec2 b) {return ds_add(a,-b);}
precise vec2 ds_mul(vec2 a,vec2 b) {
    precise vec2 p=ds_product(a.x,b.x);
    return ds_sum(p.x,p.y+a.x*b.y+a.y*b.x);
}
precise vec2 ds_div(vec2 a,vec2 b) {
    precise float q=a.x/b.x;
    precise vec2 residual=ds_sub(a,ds_mul(b,vec2(q,0.)));
    return ds_add(vec2(q,0.),vec2((residual.x+residual.y)/b.x,0.));
}
int ds_sign(vec2 a) {return a.x>0.?1:a.x<0.?-1:a.y>0.?1:a.y<0.?-1:0;}
bool ds_less(vec2 a,vec2 b) {return ds_sign(ds_sub(a,b))<0;}
float ds_float(vec2 a) {return a.x+a.y;}

struct Ray {vec2 eye[3];vec2 dir[3];};
Ray local_ray(Proxy p,View v,vec2 sx,vec2 sy) {
    Ray ray;
    for(int axis=0;axis<3;axis++) {
        precise vec2 o=vec2(p.local[3][axis],0.);
        precise vec2 f=vec2(0.),r=vec2(0.),u=vec2(0.);
        for(int j=0;j<3;j++) {
            o=ds_add(o,ds_product(p.local[j][axis],v.eye[j]));
            f=ds_add(f,ds_product(p.local[j][axis],v.forward[j]));
            r=ds_add(r,ds_product(p.local[j][axis],v.right[j]));
            u=ds_add(u,ds_product(p.local[j][axis],v.up[j]));
        }
        ray.eye[axis]=o;
        ray.dir[axis]=ds_add(f,ds_mul(ds_sub(ds_mul(r,sx),ds_mul(u,sy)),vec2(v.lens.z,0.)));
    }
    return ray;
}

bool slab(Proxy p,Ray r,out vec2 entry,out vec2 exit_t,out int axis) {
    entry=vec2(-1.e30,0.);exit_t=vec2(1.e30,0.);axis=0;
    for(int k=0;k<3;k++) {
        if(ds_sign(r.dir[k])==0) {
            if(ds_less(r.eye[k],vec2(p.lo[k],0.))||ds_less(vec2(p.hi[k],0.),r.eye[k]))return false;
            continue;
        }
        precise vec2 a=ds_div(ds_sub(vec2(p.lo[k],0.),r.eye[k]),r.dir[k]);
        precise vec2 b=ds_div(ds_sub(vec2(p.hi[k],0.),r.eye[k]),r.dir[k]);
        if(ds_less(b,a)) {vec2 swap=a;a=b;b=swap;}
        // Strict > keeps the same X/Y/Z tie precedence as the legacy contract.
        if(ds_less(entry,a)) {entry=a;axis=k;}
        if(ds_less(b,exit_t))exit_t=b;
    }
    if(ds_sign(entry)<0)entry=vec2(0.);
    return !ds_less(exit_t,entry);
}

bool cell_support(Proxy p,Ray r,int axis,ivec2 axes,ivec4 rect,ivec2 cell,vec2 plane) {
    // Cross-multiplied support avoids division/cancellation at a cell edge.
    int orientation=ds_sign(r.dir[axis]);
    for(int a=0;a<2;a++) {
        int u=axes[a];
        precise vec2 extent=ds_sub(vec2(p.hi[u],0.),vec2(p.lo[u],0.));
        precise vec2 relative=ds_sub(r.eye[u],vec2(p.lo[u],0.));
        precise vec2 dim=vec2(float(rect[2+a]),0.);
        precise vec2 depth=ds_sub(plane,r.eye[axis]);
        precise vec2 shift=ds_mul(ds_mul(depth,r.dir[u]),dim);
        precise vec2 lower=ds_add(ds_mul(ds_sub(ds_mul(relative,dim),
            ds_mul(vec2(float(cell[a]),0.),extent)),r.dir[axis]),shift);
        precise vec2 upper=ds_add(ds_mul(ds_sub(ds_mul(relative,dim),
            ds_mul(vec2(float(cell[a]+1),0.),extent)),r.dir[axis]),shift);
        if(orientation*ds_sign(lower)<0||orientation*ds_sign(upper)>=0)return false;
    }
    return true;
}

void main() {
    uint pixel=gl_GlobalInvocationID.x;
    uint side=uint(push.value.x);
    if(side==0u||pixel>=side*side)return;
    uint words=(side*side+31u)/32u;
    bool flagged=false;
    for(uint c=0u;c<3u;c++)flagged=flagged||((risk.bits[c*words+(pixel>>5u)]&(1u<<(pixel&31u)))!=0u);
    if(!flagged)return;
    View v=views.v[0];
    precise vec2 sx=ds_sub(ds_div(vec2(float(pixel%side)*2.+1.,0.),vec2(float(side),0.)),vec2(1.,0.));
    precise vec2 sy=ds_sub(ds_div(vec2(float(pixel/side)*2.+1.,0.),vec2(float(side),0.)),vec2(1.,0.));
    precise vec2 best=vec2(1.e30,0.);
    vec4 best_world=vec4(0.),best_normal=vec4(0.),best_color=vec4(0.);
    float best_revz=0.;
    bool winner=false,invalid=false;
    int tested=0;
    for(int instance=0;instance<97;instance++) {
        Proxy p=proxies.p[instance];
        Ray r=local_ray(p,v,sx,sy);
        vec2 entry,exit_t;int axis;
        if(!slab(p,r,entry,exit_t,axis)||!ds_less(entry,best))continue;
        int face=axis*2+(ds_sign(r.dir[axis])>0?1:0);
        ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
        ivec4 rect=faces.rect[int(p.meta.x)+face];
        // Under this explicit metadata limit, rounding either DS endpoint to
        // FP32 cannot move it by a whole cell. One extra cell on both sides
        // conservatively includes exact boundaries; support makes the choice.
        if(any(lessThanEqual(rect.zw,ivec2(0)))||any(greaterThan(rect.zw,ivec2(1048576)))) {
            invalid=true;continue;
        }
        ivec2 low,high;
        for(int a=0;a<2;a++) {
            int u=axes[a];
            precise vec2 extent=ds_sub(vec2(p.hi[u],0.),vec2(p.lo[u],0.));
            precise vec2 first=ds_mul(ds_div(ds_sub(ds_add(r.eye[u],ds_mul(r.dir[u],entry)),
                vec2(p.lo[u],0.)),extent),vec2(float(rect[2+a]),0.));
            precise vec2 last=ds_mul(ds_div(ds_sub(ds_add(r.eye[u],ds_mul(r.dir[u],exit_t)),
                vec2(p.lo[u],0.)),extent),vec2(float(rect[2+a]),0.));
            low[a]=max(0,int(floor(min(ds_float(first),ds_float(last))))-1);
            high[a]=min(rect[2+a]-1,int(floor(max(ds_float(first),ds_float(last))))+1);
        }
        for(int y=low.y;y<=high.y;y++)for(int x=low.x;x<=high.x;x++) {
            ivec2 cell=ivec2(x,y);
            vec4 depths=texelFetch(depth_field,cell+rect.xy,0);
            tested++;
            for(int layer=0;layer<4;layer++) {
                if(depths[layer]<0.)continue;
                precise vec2 plane=face%2==0?ds_sub(vec2(p.hi[axis],0.),vec2(depths[layer],0.))
                    :ds_add(vec2(p.lo[axis],0.),vec2(depths[layer],0.));
                precise vec2 t=ds_div(ds_sub(plane,r.eye[axis]),r.dir[axis]);
                if(ds_sign(t)<=0||ds_less(t,entry)||ds_less(exit_t,t)||!ds_less(t,best))continue;
                if(!cell_support(p,r,axis,axes,rect,cell,plane))continue;
                vec3 world;
                for(int j=0;j<3;j++) {
                    precise vec2 dir=ds_add(vec2(v.forward[j],0.),ds_mul(ds_sub(
                        ds_mul(vec2(v.right[j],0.),sx),ds_mul(vec2(v.up[j],0.),sy)),vec2(v.lens.z,0.)));
                    world[j]=ds_float(ds_add(vec2(v.eye[j],0.),ds_mul(dir,t)));
                }
                float z=dot(world-v.eye.xyz,v.forward.xyz);
                if(z<=v.lens.x||z>=v.lens.y)continue;
                vec4 n=texelFetch(normal_field,ivec3(cell+rect.xy,layer),0);
                vec4 c=texelFetch(color_field,ivec3(cell+rect.xy,layer),0);
                best=t;winner=true;
                best_world=vec4(world,n.w+p.material.z+1.);
                best_normal=vec4(normalize(transpose(mat3(p.local))*n.xyz),clamp(c.a+p.material.y,.2,.95));
                best_color=vec4(clamp(c.rgb*p.material.x,vec3(0.),vec3(1.)),1.);
                best_revz=v.lens.x*(v.lens.y-z)/((v.lens.y-v.lens.x)*z);
            }
        }
    }
    if(invalid)output_hit.h[pixel]=HitRecord(vec4(0.),vec4(0.),vec4(0.),vec4(0.,3.,float(tested),0.));
    else if(winner)output_hit.h[pixel]=HitRecord(best_world,best_normal,best_color,vec4(best_revz,1.,float(tested),ds_float(best)));
    else output_hit.h[pixel]=HitRecord(vec4(0.),vec4(0.),vec4(0.),vec4(0.,2.,float(tested),0.));
}
