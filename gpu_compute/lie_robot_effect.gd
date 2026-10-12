extends "res://lie22_modular_effect.gd"
## Shared material captures; the only extra per-frame data are cable frames.
const RobotShader=preload("res://shaders/lie_robot.glsl")
const CURVE_POINTS=16
const CURVE_BYTES=CURVE_POINTS*48
const MAX_CURVES=16
var _active_jobs:=PackedInt32Array()
var _active_instances:=PackedFloat32Array()
var _active_curves:=PackedFloat32Array()

func capture_root() -> String:return "res://captures/robot_refined/" if FileAccess.file_exists("res://captures/robot_refined/catalog.json") else "res://captures/robot_modular/"
func sample_stride() -> int:return 96
func shader_resource() -> RDShaderFile:return RobotShader
func maximum_output_size() -> int:return 1024
func initialize_extra_buffers() -> void:_buffer(14,MAX_CURVES*CURVE_BYTES)
func extra_signature(next: Dictionary) -> PackedByteArray:return next.get("curves",PackedByteArray())
func update_extra_buffers(next: Dictionary) -> void:
    var data: PackedByteArray=next["curves"]
    if not data.is_empty():_rd.buffer_update(_buffers[14],0,data.size(),data)
    _active_jobs=next["jobs"].to_int32_array();_active_instances=next["instances"].to_float32_array();_active_curves=data.to_float32_array()

func configure_robot(parameters: PackedByteArray,instances: PackedByteArray,jobs: PackedByteArray,work: int,curves: PackedByteArray) -> bool:
    if not valid_configuration(parameters,instances,jobs,work) or curves.size()%CURVE_BYTES!=0 or curves.size()>MAX_CURVES*CURVE_BYTES:return false
    var values: PackedFloat32Array=curves.to_float32_array()
    for value in values:
        if not is_finite(value):return false
    var objects: PackedFloat32Array=instances.to_float32_array()
    for value in objects:
        if not is_finite(value):return false
    for i in range(0,objects.size(),24):
        var curve: float=objects[i+17]
        if curve!=floor(curve) or curve< -1 or curve>=curves.size()/CURVE_BYTES:return false
    _mutex.lock();_pending={"parameters":parameters.duplicate(),"instances":instances.duplicate(),"jobs":jobs.duplicate(),"work":work,"curves":curves.duplicate()};_mutex.unlock();return true

func _capture() -> void:
    if not gpu_ready:return
    var probes: Array=[]
    for i in range(0,_active_jobs.size(),4):
        var count: int=_active_jobs[i+1]
        for local_index in [0,int(count/2),count-1]:
            var invocation: int=_active_jobs[i+3]+local_index
            var raw: PackedFloat32Array=_rd.buffer_get_data(_buffers[3],invocation*96,96).to_float32_array()
            probes.append({"sample":_active_jobs[i]+local_index,"instance":_active_jobs[i+2],"position":[raw[0],raw[1],raw[2]],"shading_normal":[raw[4],raw[5],raw[6]],"geometric_normal":[raw[16],raw[17],raw[18]]})
    var result: Dictionary={"color":_rd.texture_get_data(output_rid,0).to_float32_array(),"depth":_rd.buffer_get_data(_buffers[4]).to_int32_array(),
        "output_size":output_size,"internal_size":render_size,"asset_uploads":asset_uploads,"allocation_bytes":allocation_bytes,"frames":frame_count,"sample_invocations":sample_invocations,"instances":instance_count,"device":_rd.get_device_name(),"library_bytes":_samples.size(),"probes":probes,"instance_packet":_active_instances.duplicate(),"curve_packet":_active_curves.duplicate()}
    _mutex.lock();_readback=result;_mutex.unlock()
