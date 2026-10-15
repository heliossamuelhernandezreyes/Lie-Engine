"""Fused shading, provenance-guided material filtering and finite emitters."""
from pathlib import Path
from lie_wall12_shader import generate as baseline
from lie_surface_light_shader import generate as field
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def common(name):return (ROOT/'gpu_compute/shaders/lib'/name).read_text()
def generate():
    s=baseline().replace('layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;','layout(rgba32ui,set=0,binding=8) uniform uimage2D diffuse_image;')
    s=replace(s,'void lie_resolve_surface(uint i) {','''layout(set=0,binding=33,std430) readonly buffer PipelineControl {uvec4 flags;} pipeline_control;
layout(set=0,binding=34,std430) readonly buffer EmitterShapes {vec4 values[];} emitter_shapes;
'''+common('lie_surface_filter.glslinc')+'''
LiePixelMaterial lie_material(uint i) {
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    return pipeline_control.flags.y!=0u?lie_unpack_material(imageLoad(diffuse_image,q)):lie_raw_material(i);
}
void lie_resolve_surface(uint i) {''')
    s=replace(s,'vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {',common('lie_area_emission.glslinc')+'''layout(set=0,binding=34,std430) readonly buffer EmitterShapesEarly {vec4 values[];} emitter_shapes_early;
vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {''')
    # Only one descriptor declaration; it must precede the direct-light helper.
    s=s.replace('layout(set=0,binding=34,std430) readonly buffer EmitterShapes {vec4 values[];} emitter_shapes;\n','')
    s=replace(s,'cosine*fade/(4.*PI*max(d2,power.w))','cosine*fade*lie_emitter_gain(emitter_shapes_early.values[l],-delta)/(4.*PI*max(d2,power.w))')
    s=replace(s,'''Accumulator acc=accumulated.v[i];
        vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);
        vec3 mean_normal=vec3(acc.normal_roughness.xyz)/max(float(acc.color_weight.w),1.)*2.-1.;
        roughness=float(acc.normal_roughness.w)/max(float(acc.color_weight.w),1.);
        mean_length=min(length(mean_normal),1.);''','''LiePixelMaterial material=lie_material(i);vec3 albedo=material.albedo,mean_normal=material.mean_normal;
        roughness=material.roughness;mean_length=material.mean_length;''')
    s=replace(s,'''Accumulator acc=accumulated.v[ix];
            vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);''','''vec3 albedo=lie_material(ix).albedo;''')
    start=s.index('    if(stage==4) {',s.index('void main()'))
    s=s[:start]+'''    if(stage==4) {
        bool fused=pipeline_control.flags.x!=0u,filtered=pipeline_control.flags.y!=0u;
        if(owner==EMPTY) {if(fused)imageStore(output_image,xy,vec4(0));return;}
        LiePixelMaterial material;
        if(filtered) {
            if(phase.value.w!=0) {
                uvec4 packet=lie_pack_material(lie_filter_material(i));imageStore(diffuse_image,xy,packet);
                material=lie_unpack_material(packet);
            } else material=lie_unpack_material(imageLoad(diffuse_image,xy));
        } else material=lie_raw_material(i);
        vec3 E=lie_irradiance_code(projected.v[owner]);
        if(fused)imageStore(output_image,xy,vec4(max(material.albedo*E,vec3(0)),1));
        else if(filtered)imageStore(specular_image,xy,vec4(E,1));
        else imageStore(diffuse_image,xy,floatBitsToUint(vec4(E,1)));
        return;
    }
    if(stage==6) {
        if(owner==EMPTY){imageStore(output_image,xy,vec4(0));return;}
        vec3 E=pipeline_control.flags.y!=0u?imageLoad(specular_image,xy).rgb:uintBitsToFloat(imageLoad(diffuse_image,xy)).rgb;
        imageStore(output_image,xy,vec4(max(lie_material(i).albedo*E,vec3(0)),1));
    }
}
'''
    # Pipeline phase is named data in the inherited shader.
    s=replace(s,'if(stage==10) {lie_resolve_surface(i);return;}','''if(stage==15) {
        if(i<uint(parameters.counts.z*parameters.counts.w))recovery_map.values[i]=EMPTY;
        if(i==0u){recovery_count.count=0u;recovery_count.overflow=0u;}return;
    }
    if(stage==10) {lie_resolve_surface(i);return;}''')
    return s
def generate_field():
    s=field();s=replace(s,'void main() {',common('lie_area_emission.glslinc')+'''layout(set=0,binding=26,std430) readonly buffer EmissionDescriptors {vec4 values[];} emission_descriptors;
void main() {''')
    return replace(s,'weights.values[i]=value;','weights.values[i]=value*lie_emitter_gain(emission_descriptors.values[l],patches.values[p].center_area.xyz-lights.values[l].position_radius.xyz);')
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall13_area.glsl').write_text(generate())
    (ROOT/'gpu_compute/shaders/lie_area_field.glsl').write_text(generate_field())
