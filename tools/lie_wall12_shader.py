"""Generate bounded raster work and separately evaluated opaque direct response."""
from pathlib import Path
from lie_wall11_shader import generate as baseline
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=baseline()
    include=(ROOT/'gpu_compute/shaders/lib/lie_opaque_brdf.glslinc').read_text()
    work=(ROOT/'gpu_compute/shaders/lib/lie_splat_work.glslinc').read_text()
    s=replace(s,'void lie_resolve_surface(uint i) {', '''layout(set=0,binding=32,std430) buffer AppearanceControl {uint words[];} appearance_control;
'''+include+work+'''
void lie_resolve_surface(uint i) {''')
    s=replace(s,'if(surface_options.flags.x==0u && surface_options.flags.y==0u)return;', 'if(surface_options.flags.x==0u && surface_options.flags.y==0u && appearance_control.words[0]==0u)return;')
    s=replace(s,'vec3 world,normal;vec3 coefficients[9];for(int k=0;k<9;k++)coefficients[k]=vec3(0);', 'vec3 world,normal;vec3 coefficients[9];float optical_weights[9];for(int k=0;k<9;k++){coefficients[k]=vec3(0);optical_weights[k]=0.;}')
    s=replace(s,'coefficients[k]=albedo*(w/PI);','coefficients[k]=albedo*(w/PI);optical_weights[k]=w;')
    s=replace(s,'uint source_projection=owner;','uint source_projection=owner;\n    float roughness=.8,mean_length=1.;')
    s=replace(s,'vec3 mean_normal=vec3(acc.normal_roughness.xyz)/max(float(acc.color_weight.w),1.)*2.-1.;', '''vec3 mean_normal=vec3(acc.normal_roughness.xyz)/max(float(acc.color_weight.w),1.)*2.-1.;
        roughness=float(acc.normal_roughness.w)/max(float(acc.color_weight.w),1.);
        mean_length=min(length(mean_normal),1.);''')
    s=replace(s,'for(uint k=0u;k<group.y;k++)coefficients[k]=record.coefficients[k].rgb;', '''for(uint k=0u;k<group.y;k++){coefficients[k]=record.coefficients[k].rgb;optical_weights[k]=record.coefficients[k].w;}
        Projection witness=projected.v[source_projection];
        uint sid=uint(round(witness.gradient.w));
        roughness=clamp(samples.v[sid].attributes.z+instances.v[uint(witness.gradient.z)].tint.w,.2,.95);''')
    s=replace(s,'surface_options.flags.x!=0u && max(old_direct.r,max(old_direct.g,old_direct.b))>0.', 'surface_options.flags.x!=0u && (max(old_direct.r,max(old_direct.g,old_direct.b))>0. || (appearance_control.words[0]!=0u && max(optical_direct.r,max(optical_direct.g,optical_direct.b))>0.))')
    s=replace(s,'vec3 old_total=vec3(0),new_total=vec3(0);','''vec3 old_total=vec3(0),new_total=vec3(0);
    roughness=lie_filtered_roughness(roughness,mean_length,appearance_control.words[2]!=0u);
    vec3 view=lie_opaque_direction(parameters.eye.xyz-world);
    float survival=0.;
    for(uint k=0u;k<group.y;k++)survival+=optical_weights[k]*(1.-clamp(injected_material_codes.values[(group.x+k)*3u+2u].w,0.,1.));
    float f0=uintBitsToFloat(appearance_control.words[3]);''')
    s=replace(s,'vec3 old_direct=vec3(0),unoccluded=vec3(0);','vec3 old_direct=vec3(0),unoccluded=vec3(0),optical_direct=vec3(0),optical_unoccluded=vec3(0);')
    s=replace(s,'''            if(max(coefficients[k].r,max(coefficients[k].g,coefficients[k].b))<=0.)continue;
            uint node=group.x+k;
            old_direct+=coefficients[k]*surface_lights.values[16u+l*surface_lights.header.x+node].rgb;
            unoccluded+=coefficients[k]*lie_surface_unoccluded(l,lie_position(node),lie_normal(node));''','''            bool optical=appearance_control.words[0]!=0u && surface_options.flags.y!=0u;
            if(max(coefficients[k].r,max(coefficients[k].g,coefficients[k].b))<=0. && (!optical || optical_weights[k]<=0.))continue;
            uint node=group.x+k;
            vec3 incident=lie_surface_unoccluded(l,lie_position(node),lie_normal(node));
            vec3 coarse=surface_lights.values[16u+l*surface_lights.header.x+node].rgb;
            old_direct+=coefficients[k]*coarse;
            if(optical) {
                optical_direct+=optical_weights[k]*coarse;
                optical_unoccluded+=optical_weights[k]*incident;
            } else unoccluded+=coefficients[k]*incident;''')
    s=replace(s,'new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);', '''if(appearance_control.words[0]!=0u && surface_options.flags.y!=0u) {
            // Replace the existing direct term. The indirect field is retained
            // once, outside this loop. No second point emitter or cached RGB.
            vec3 gate=vec3(0);
            for(int c=0;c<3;c++)if(optical_unoccluded[c]>1e-20)gate[c]=clamp(optical_direct[c]/optical_unoccluded[c],0.,1.);
            vec3 direction=lie_opaque_direction(surface_lights.values[l*2u].xyz-world);
            vec3 response=lie_opaque_brdf(coefficient*PI,roughness,f0,survival,normal,view,direction);
            new_total+=max(response,vec3(0))*local_direct*gate*visibility;
        } else new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);''')
    s=replace(s,'vec3 coeff[9];for(int k=0;k<9;k++)coeff[k]=vec3(0);','vec3 coeff[9];float optical_coeff[9];for(int k=0;k<9;k++){coeff[k]=vec3(0);optical_coeff[k]=0.;}')
    s=replace(s,'coeff[candidate-node_base]+=albedo*(weight*w/PI);','coeff[candidate-node_base]+=albedo*(weight*w/PI);optical_coeff[candidate-node_base]+=weight*w;')
    s=replace(s,'vec4(coeff[k]/sum,0)','vec4(coeff[k]/sum,optical_coeff[k]/sum)')
    s=replace(s,'if(i==0u) {recovery_count.count=0u;recovery_count.overflow=0u;}', '''if(i==0u) {recovery_count.count=0u;recovery_count.overflow=0u;
            for(uint k=4u;k<12u;k++)appearance_control.words[k]=0u;
        }''')
    # Stage 3 previously fetched all 80B samples before rejecting backfaces.
    s=replace(s,'''Instance source_inst=instances.v[job.z];Sample s=fetch_sample(sid,source_inst);Instance inst=render_instance(source_inst);
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
        Projection p;
        if(stage==2) {''', '''Sample s;Instance inst;Projection p;
        if(stage==2) {
            Instance source_inst=instances.v[job.z];s=fetch_sample(sid,source_inst);inst=render_instance(source_inst);
            mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);''')
    start='''        int bound=int(ceil(p.screen.w));
        for(int y=-bound;y<=bound;y++)for(int x=-bound;x<=bound;x++) {
            ivec2 q=ivec2(floor(p.screen.xy))+ivec2(x,y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;'''
    s=replace(s,start,'''        int bound=int(ceil(p.screen.w));
        ivec2 center=ivec2(floor(p.screen.xy));
        bool tight=appearance_control.words[1]!=0u;
        if(tight && (center.x+bound<0 || center.y+bound<0 || center.x-bound>=parameters.counts.z || center.y-bound>=parameters.counts.w))return;
        if(stage==3) {Instance source_inst=instances.v[job.z];s=fetch_sample(sid,source_inst);inst=render_instance(source_inst);}
        vec3 sample_color=stage==3?material_color(s,inst):vec3(0);
        float sample_rough=stage==3?clamp(s.attributes.z+inst.tint.w,.2,.95):0.;
        if(stage==3 && (int(s.attributes.x)==3 || int(s.attributes.x)==6)) {
            uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));
            sample_rough=clamp(sample_rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);
        }
        uint candidates=0u;
        int ymin=center.y-bound,ymax=center.y+bound;
        if(tight){ymin=max(ymin,0);ymax=min(ymax,parameters.counts.w-1);}
        for(int y=ymin;y<=ymax;y++) {
          ivec2 interval=tight?lie_splat_row(p,center,y,bound):ivec2(center.x-bound,center.x+bound);
          if(tight){interval.x=max(interval.x,0);interval.y=min(interval.y,parameters.counts.z-1);}
          for(int x=interval.x;x<=interval.y;x++) {
            candidates++;
            ivec2 q=ivec2(x,y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;''')
    s=replace(s,'material_color(s,inst)*float(w)','sample_color*float(w)')
    s=replace(s,'''float rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
                if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);}
                atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(rough*float(w))));''','''
                atomicAdd(accumulated.v[pixel].normal_roughness.w,uint(round(sample_rough*float(w))));''')
    s=replace(s,'''        }return;
    }
    if(stage==8 || stage==9) {''','''          }
        }
        if(appearance_control.words[12]!=0u) {
            atomicAdd(appearance_control.words[stage==2?4u:5u],candidates);
            atomicAdd(appearance_control.words[stage==2?6u:7u],1u);
        }
        return;
    }
    if(stage==8 || stage==9) {''')
    return s
def generate_test():
    common=(ROOT/'gpu_compute/shaders/lib/lie_opaque_brdf.glslinc').read_text()
    work=(ROOT/'gpu_compute/shaders/lib/lie_splat_work.glslinc').read_text()
    return '''#[compute]
#version 450
layout(local_size_x=64) in;
struct Projection {vec4 world;vec4 normal;vec4 screen;vec4 gradient;vec4 geometry;vec4 ellipse;};
layout(set=0,binding=0,std430) readonly buffer Inputs {vec4 values[];} source;
layout(set=0,binding=1,std430) buffer Results {vec4 values[];} result;
layout(push_constant,std430) uniform Options {uvec4 counts;} options;
'''+common+work+'''
void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=options.counts.x)return;
    uint at=i*5u;vec4 albedo=source.values[at],view=source.values[at+1u],light=source.values[at+2u],normal=source.values[at+3u],config=source.values[at+4u];
    float rough=lie_filtered_roughness(albedo.w,config.x,config.y>.5);
    result.values[i]=vec4(lie_opaque_brdf(albedo.rgb,rough,config.z,config.w,normalize(normal.xyz),lie_opaque_direction(view.xyz),lie_opaque_direction(light.xyz)),rough);
}
'''
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall12_material.glsl').write_text(generate())
    (ROOT/'gpu_compute/shaders/lie_opaque_test.glsl').write_text(generate_test())
