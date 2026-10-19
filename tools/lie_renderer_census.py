"""Separate instrumented copies of the accepted kernels; never used for FPS.

Counters count logical work, not DRAM reads, instructions or hardware rays.
The original shader files remain byte-identical.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
STAGES = (2, 3, 4, 10, 11)
NAMES = ["selected_sample_invocations", "project_active", "project_candidates",
         "raster_candidates", "material_contributions", "base_node_evaluations",
         "refined_pixels", "refined_group_nodes", "refined_light_node_evaluations",
         "local_light_evaluations", "source_light_pairs", "shadow_cache_hits",
         "witness_attempts", "witness_hits", "full_shadow_traversals",
         "scene_nodes", "blas_nodes", "disk_tests"]

def change(source, before, after):
    assert source.count(before) == 1, (before, source.count(before))
    return source.replace(before, after)

def add(source, name, text):
    return change(source, name, name + text)

def generate(stage):
    source = (ROOT / f"gpu_compute/shaders/lie_wall17_stage_{stage:02d}.glsl").read_text()
    source = change(source, "#version 450", "#version 450\n// GENERATED diagnostic census; excludes performance results.")
    header = "layout(set=0,binding=49,std430) buffer LieCensus {uint values[];} lie_census;\n"
    header += "void lie_count(uint at,uint n) {atomicAdd(lie_census.values[at],n);}\n"
    # Helpers, including tracing, must see this declaration.
    at = source.index("\nstruct ")
    source = source[:at] + "\n" + header + source[at:]
    if stage in (2, 3):
        if stage == 2:
            source = add(source, "uint sid=sample_refs.values[reference_index];", "lie_count(0u,1u);")
            source = add(source, "if(p.screen.z<=0)return;", "lie_count(1u,1u);")
        source = change(source, "uint candidates=0u;", "uint candidates=0u,accepted=0u;")
        source = add(source, "if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;", "accepted++;")
        source = add(source, "if(appearance_control.words[12]!=0u) {",
                     "")  # Preserve the original optional counters, disabled by this lab.
        source = change(source, "        if(appearance_control.words[12]!=0u) {",
                        f"        lie_count({2 if stage == 2 else 3}u,candidates);" +
                        ("lie_count(4u,accepted);" if stage == 3 else "") +
                        "\n        if(appearance_control.words[12]!=0u) {")
    elif stage == 4:
        source = add(source, "uint node=projection_node(point);uvec2 group=lie_group(node);", "lie_count(5u,group.y);")
    elif stage == 10:
        source = add(source, "vec4 base=imageLoad(specular_image,q);if(base.a<.5)return;", "lie_count(6u,1u);")
        source = add(source, "vec3 old_total=vec3(0),new_total=vec3(0);", "lie_count(7u,group.y);")
        source = add(source, "uint node=group.x+k;", "lie_count(8u,1u);")
        source = add(source, "vec3 local_direct=lie_surface_unoccluded(l,world,normal);", "lie_count(9u,1u);")
    elif stage == 11:
        source = add(source, "LieSourceNode n=lie_blas_node(i);", "lie_count(16u,1u);")
        source = add(source, "uint sid=lie_visibility_refs.values[leaf+1u+k];if(sid==skip)continue;", "lie_count(17u,1u);")
        source = add(source, "lie_query_stat(0u);", "lie_count(12u,1u);")
        source = add(source, "found=hint;lie_query_stat(1u);", "lie_count(13u,1u);")
        source = add(source, "lie_query_stat(2u);", "lie_count(14u,1u);")
        source = add(source, "LieSourceNode node=lie_scene_node(i);", "lie_count(15u,1u);")
        source = add(source, "if(max(power.r,max(power.g,power.b))>0.) {", "lie_count(10u,1u);")
        source = add(source, "if(use_cache && (valid&(1u<<light))!=0u) {", "lie_count(11u,1u);")
    return '\n'.join(line.rstrip() for line in source.splitlines()) + '\n'

def outputs():
    result = {}; bindings = {}
    import re
    for stage in STAGES:
        shader = generate(stage)
        result[f"gpu_compute/shaders/lie_renderer_census_{stage:02d}.glsl"] = shader
        bindings[stage] = sorted(map(int, re.findall(r"layout\([^)]*\bbinding=(\d+)", shader)))
    manifest = "extends RefCounted\n## Generated diagnostic copies, not performance kernels.\nconst SHADERS={\n"
    for stage in STAGES:
        manifest += f'\t{stage}:preload("res://shaders/lie_renderer_census_{stage:02d}.glsl"),\n'
    manifest += "}\nconst BINDINGS=" + json.dumps(bindings, separators=(",", ":")).replace('"', '') + "\n"
    manifest += "const NAMES=" + json.dumps(NAMES, separators=(",", ":")) + "\n"
    result["gpu_compute/lie_renderer_census_kernels.gd"] = manifest
    return result

if __name__ == "__main__":
    for name, data in outputs().items():
        (ROOT / name).write_text(data)
