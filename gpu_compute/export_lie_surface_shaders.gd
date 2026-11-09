extends SceneTree
const Kernels=preload("res://lie_construction_scene_kernels.gd")
## Diagnostic export only. No rendering or source-bank substitution.
func _initialize() -> void:
    for probe in [false,true]:
        var folder: String="surface-probe-shaders" if probe else "surface-shaders"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://"+folder))
        for stage in [1,2,3,9,10,11,12]:
            var shader: RDShaderFile=Kernels.PROBE[stage] if probe and stage!=1 else Kernels.SHADERS[stage]
            var spirv: RDShaderSPIRV=shader.get_spirv()
            var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
            if error!="":printerr(error);quit(1);return
            var file:=FileAccess.open("res://%s/stage-%d.spv" % [folder,stage],FileAccess.WRITE)
            file.store_buffer(spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE));file.close()
    print("SURFACE SHADERS EXPORTED")
    quit()
