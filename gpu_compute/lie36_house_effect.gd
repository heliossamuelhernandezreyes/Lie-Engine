extends "res://lie28_building_effect.gd"
# LIE37: true multi-panel GPU transport; same immutable WALL04 captured bank.
# No fixed single-wall light node table; all 113 panel frames are transformed.
const HouseShader=preload("res://shaders/lie36_house_material.glsl")
const PANEL_CAP: int=128
var transport_dispatches: int=0

func shader_resource() -> RDShaderFile:return HouseShader
func capture_root() -> String:return "res://captures/liehouse36/"

func _make_set() -> void:
    # Per-panel direct irradiance, directional pair transfer and one bounce.
    # Fixed 128-entry topology permits arbitrary building layouts within cap.
    if not _buffers.has(14):_buffer(14,PANEL_CAP*16)
    if not _buffers.has(15):_buffer(15,PANEL_CAP*PANEL_CAP*4)
    if not _buffers.has(16):_buffer(16,PANEL_CAP*16)
    super._make_set()

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock()
    var next: Dictionary=_pending.duplicate()
    _mutex.unlock()
    if next.is_empty():return
    _collect_profile()
    var signature: PackedByteArray=next["parameters"].duplicate()
    signature.append_array(next["instances"])
    signature.append_array(next["jobs"])
    if signature==_resident:return
    var work: int=next["work"]
    var n: int=next["instances"].size()/96
    if n>PANEL_CAP or n<1:return
    if work>projection_capacity:
        if _set.is_valid():_rd.free_rid(_set);_set=RID()
        if _buffers[3].is_valid():_rd.free_rid(_buffers[3])
        allocation_bytes-=int(_lengths[3])
        projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536))*65536)
        _buffer(3,projection_capacity*96)
        _make_set()
    _rd.buffer_update(_buffers[6],0,256,next["parameters"])
    _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
    _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    _rd.capture_timestamp(_profile_marker("begin"))
    var cmds: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(cmds,_pipeline)
    _rd.compute_list_bind_uniform_set(cmds,_set,0)
    # Phase 8: direct lighting of arbitrary panel surfaces.
    # Phase 9: aperture-aware visibility, reciprocal oriented transfer,
    # normalized per-source before phase 10 collects bounced irradiance.
    for stage in [1,2,3,8,9,10,4,6,7]:
        var count: int=work if stage in [2,3] else maxi(render_size*render_size,512*512) if stage==1 else output_size*output_size if stage==7 else n if stage in [8,9,10] else render_size*render_size
        _rd.compute_list_set_push_constant(cmds,PackedInt32Array([stage,2,0,0]).to_byte_array(),16)
        _rd.compute_list_dispatch(cmds,int(ceil(float(count)/64)),1,1)
        _rd.compute_list_add_barrier(cmds)
    _rd.compute_list_end()
    _rd.capture_timestamp(_profile_marker("end"))
    transport_dispatches+=1
    _resident=signature
    sample_invocations=work
    instance_count=n
    frame_count+=1

func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    var n: int=mini(instance_count,PANEL_CAP)
    if n<=0:return
    var direct: PackedFloat32Array=_rd.buffer_get_data(_buffers[14]).to_float32_array()
    var bounce: PackedFloat32Array=_rd.buffer_get_data(_buffers[16]).to_float32_array()
    var dsum:=Vector3.ZERO
    var bsum:=Vector3.ZERO
    var positive: int=0
    for i in range(n):
        var d:=Vector3(direct[i*4],direct[i*4+1],direct[i*4+2])
        var b:=Vector3(bounce[i*4],bounce[i*4+1],bounce[i*4+2])
        dsum+=d
        bsum+=b
        if b.length_squared()>1e-12:positive+=1
    _mutex.lock()
    _readback["multiwall_transport"]={
        "panels":n,
        "direct_irradiance_sum":[dsum.x,dsum.y,dsum.z],
        "bounce_irradiance_sum":[bsum.x,bsum.y,bsum.z],
        "panels_with_bounce":positive,
        "dispatches":transport_dispatches,
        "graph":"GPU panel-centre, oriented and aperture-aware, one diffuse bounce",
        "limitations":"finite source/receiver panels; not full WALL12 micro-patch global illumination",
        "mobile_fps_measured":false
    }
    _mutex.unlock()
