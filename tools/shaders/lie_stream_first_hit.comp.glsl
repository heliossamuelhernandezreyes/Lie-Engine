#[compute]
#version 450
// LIE EXPERIMENTAL captured-cell first-hit resolver. NEVER original Blender mesh.
// Evaluates ONLY pixels marked in the real native pre-discard atomic risk SSBO.
// Full framebuffer dispatch for now; flagged threads traverse finite cells.
// No G-buffer overwrite. Single consistent hit record (world/owner, normal,
// material/color, reverse-Z and status). Explicit overflow: status=3.
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

const float EPS=1.e-7;
const int MAX_CELL_STEPS=1800;

bool is_flagged(uint idx,uint side) {
    uint words=(side*side+31u)/32u;
    for(uint channel=0u;channel<3u;channel++)
        if((risk.bits[channel*words+(idx>>5u)]&(1u<<(idx&31u)))!=0u)return true;
    return false;
}
float safe_dir(float d) {
    return abs(d)>1.e-16?d:(d<0.?-1.e-16:1.e-16);
}

void main() {
    uint pixel=gl_GlobalInvocationID.x;
    uint side=uint(push.value.x);
    if(side==0u||pixel>=side*side)return;
    if(!is_flagged(pixel,side))return; // zero record from cleared SSBO

    View v=views.v[0];
    vec2 screen=((vec2(pixel%side,pixel/side)+vec2(.5))*2./float(side))-vec2(1.);
    vec3 world_ray=v.forward.xyz+(v.right.xyz*screen.x-v.up.xyz*screen.y)*v.lens.z;

    float best=1.e30;
    vec4 best_world=vec4(0.);
    vec4 best_normal=vec4(0.);
    vec4 best_color=vec4(0.);
    float best_revz=0.;
    int winner=0;
    int traversed=0;
    bool overflow=false;

    // Independent of rejected raster candidates: query all 97 source proxies.
    for(int instance=0;instance<97;instance++) {
        Proxy p=proxies.p[instance];
        vec3 eye=(p.local*vec4(v.eye.xyz,1.)).xyz;
        vec3 ray=mat3(p.local)*world_ray;
        vec3 safe=vec3(safe_dir(ray.x),safe_dir(ray.y),safe_dir(ray.z));
        vec3 nearv=min((p.lo.xyz-eye)/safe,(p.hi.xyz-eye)/safe);
        vec3 farv=max((p.lo.xyz-eye)/safe,(p.hi.xyz-eye)/safe);
        float entry=max(max(nearv.x,nearv.y),nearv.z);
        float exit_t=min(min(farv.x,farv.y),farv.z);
        if(exit_t<max(entry,0.)||entry>=best)continue;

        int axis=nearv.x>=nearv.y&&nearv.x>=nearv.z?0:nearv.y>=nearv.z?1:2;
        int face=axis*2+(ray[axis]>0.?1:0);
        ivec2 axes=axis==0?ivec2(1,2):axis==1?ivec2(0,2):ivec2(0,1);
        ivec4 rect=faces.rect[int(p.meta.x)+face];
        vec2 lower=vec2(p.lo[axes.x],p.lo[axes.y]);
        vec2 range=vec2(p.hi[axes.x]-p.lo[axes.x],p.hi[axes.y]-p.lo[axes.y]);
        vec2 cells=vec2(rect.zw);
        vec2 size_cell=range/cells;
        vec2 uv_ray=vec2(ray[axes.x],ray[axes.y]);
        if(rect.z<=0||rect.w<=0||any(lessThanEqual(size_cell,vec2(0.))))continue;

        // Entry-axis traversal follows the SAME finite four-layer captured
        // cell sheets; nothing is fitted or interpolated across a missing cell.
        // Integer-index DDA: do NOT accumulate 1e-7 into metres of world
        // distance, as FP32 can skip/revisit a cell. Ray is rebased at AABB
        // entry and each crossing moves a discrete (cell.x,cell.y) index.
        float entry_base=max(entry,0.);
        eye+=ray*entry_base;
        float end_local=exit_t-entry_base;
        float t=1.e-6;
        vec2 uv0=vec2(eye[axes.x],eye[axes.y]);
        vec2 uv_start=uv0+uv_ray*t;
        ivec2 cell=clamp(ivec2(floor((uv_start-lower)/size_cell)),ivec2(0),rect.zw-1);
        ivec2 direction=ivec2(uv_ray.x>=0.?1:-1,uv_ray.y>=0.?1:-1);
        vec2 step_time=vec2(1.e30);
        vec2 boundary_time=vec2(1.e30);
        for(int a=0;a<2;a++) {
            if(abs(uv_ray[a])>1.e-16) {
                float edge=lower[a]+float(cell[a]+(direction[a]>0?1:0))*size_cell[a];
                boundary_time[a]=(edge-uv0[a])/uv_ray[a];
                step_time[a]=size_cell[a]/abs(uv_ray[a]);
                // One initial float32 rounding can put us infinitesimally
                // behind an edge. The next transition must never go backwards.
                boundary_time[a]=max(boundary_time[a],t);
            }
        }
        bool finished=false;
        for(int iteration=0;iteration<MAX_CELL_STEPS;iteration++) {
            if(t>end_local+EPS||entry_base+t>=best) {finished=true;break;}
            if(any(lessThan(cell,ivec2(0)))||any(greaterThanEqual(cell,rect.zw))) {
                finished=true;break;
            }
            traversed++;
            float stop=min(end_local,min(boundary_time.x,boundary_time.y));
            stop=min(stop,best-entry_base);
            if(stop<t-EPS) {overflow=true;break;}

            vec4 layers=texelFetch(depth_field,cell+rect.xy,0);
            float local_best=1.e30;
            int local_layer=-1;
            for(int layer=0;layer<4;layer++) {
                if(layers[layer]<0.)continue;
                float plane=(face%2==0)?p.hi[axis]-layers[layer]:p.lo[axis]+layers[layer];
                float candidate=(plane-eye[axis])/safe[axis];
                if(candidate>=t-EPS&&candidate<=stop+EPS&&candidate>0.&&candidate<local_best) {
                    local_best=candidate;
                    local_layer=layer;
                }
            }
            bool accepted=false;
            if(local_layer>=0 && entry_base+local_best<best) {
                vec3 local_hit=eye+ray*local_best;
                vec3 world=(p.world*vec4(local_hit,1.)).xyz;
                vec4 n=texelFetch(normal_field,ivec3(cell+rect.xy,local_layer),0);
                vec4 c=texelFetch(color_field,ivec3(cell+rect.xy,local_layer),0);
                float z=dot(world-v.eye.xyz,v.forward.xyz);
                if(z>v.lens.x&&z<v.lens.y) {
                    best=entry_base+local_best;
                    best_world=vec4(world,n.w+p.material.z+1.);
                    best_normal=vec4(normalize(transpose(mat3(p.local))*n.xyz),
                        clamp(c.a+p.material.y,.2,.95));
                    best_color=vec4(clamp(c.rgb*p.material.x,vec3(0.),vec3(1.)),1.);
                    best_revz=v.lens.x*(v.lens.y-z)/((v.lens.y-v.lens.x)*z);
                    winner=1;
                    accepted=true;
                }
            }
            if(accepted) {finished=true;break;}
            if(stop>=end_local-EPS||entry_base+stop>=best-EPS) {
                finished=true;break;
            }
            bool move_x=boundary_time.x<=boundary_time.y;
            bool move_y=boundary_time.y<=boundary_time.x;
            if(!move_x&&!move_y) {overflow=true;break;}
            if(move_x) {
                cell.x+=direction.x;
                boundary_time.x+=step_time.x;
            }
            if(move_y) {
                cell.y+=direction.y;
                boundary_time.y+=step_time.y;
            }
            t=stop;
        }
        if(!finished&&t<=end_local+EPS&&entry_base+t<best&&!overflow)overflow=true;
    }

    if(overflow) {
        output_hit.h[pixel].world=vec4(0.);
        output_hit.h[pixel].normal=vec4(0.);
        output_hit.h[pixel].color=vec4(0.);
        output_hit.h[pixel].info=vec4(0.,3.,float(traversed),0.);
    } else if(winner!=0) {
        output_hit.h[pixel].world=best_world;
        output_hit.h[pixel].normal=best_normal;
        output_hit.h[pixel].color=best_color;
        output_hit.h[pixel].info=vec4(best_revz,1.,float(traversed),best);
    } else {
        output_hit.h[pixel].world=vec4(0.);
        output_hit.h[pixel].normal=vec4(0.);
        output_hit.h[pixel].color=vec4(0.);
        output_hit.h[pixel].info=vec4(0.,2.,float(traversed),0.);
    }
}
