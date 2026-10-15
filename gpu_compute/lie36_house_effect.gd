extends "res://lie28_building_effect.gd"
## LIE38: reuse WALL05 dependency-separated geometry/light/exposure caching
## on the actual scanned house. Original source bank is never edited.
const HouseShader=preload("res://shaders/lie36_house_material.glsl")
const PassProfile=preload("res://lie_gpu_pass_profile.gd")
var pass_profile=PassProfile.new()
const PANEL_CAP: int=128
var transport_dispatches: int=0
var geometry_rebuilds: int=0
var shadow_rebuilds: int=0
var graph_rebuilds: int=0
var lighting_resolves: int=0
var output_resolves: int=0
var idle_reuses: int=0
var _geometry_key:=PackedByteArray()
var _graph_key:=PackedByteArray()
var _shadow_key:=PackedByteArray()
var _lighting_key:=PackedByteArray()
var _last_stages: Array=[]
var _cache_events: Array=[]

func shader_resource() -> RDShaderFile:return HouseShader
func capture_root() -> String:return "res://captures/liehouse36/"

func _make_set() -> void:
    if not _buffers.has(14):_buffer(14,PANEL_CAP*16)
    if not _buffers.has(15):_buffer(15,PANEL_CAP*PANEL_CAP*4)
    if not _buffers.has(16):_buffer(16,PANEL_CAP*16)
    super._make_set()

func _camera_geometry_key(params: PackedByteArray, instances: PackedByteArray, jobs: PackedByteArray) -> PackedByteArray:
    # WALL05-style dependency key: camera/LOD/pose, subpixel tolerance,
    # source deformations, variation and roughness; excludes ALL lighting.
    var key: PackedByteArray=params.slice(0,96)
    key.append_array(params.slice(156,160))
    key.append_array(params.slice(208,248))
    key.append_array(instances)
    key.append_array(jobs)
    return key

func _light_key(params: PackedByteArray) -> PackedByteArray:
    # Relighting still requires new source shadows when the light-space frame
    # moves; changes only in RGB power never invalidate the graph.
    var key: PackedByteArray=params.slice(96,108)
    key.append_array(params.slice(160,208))
    return key

func _appearance_key(params: PackedByteArray, geometry: PackedByteArray) -> PackedByteArray:
    var key: PackedByteArray=params.slice(96,140)
    key.append_array(params.slice(144,208))
    key.append_array(params.slice(248,256))
    key.append_array(geometry)
    # Exposure is at 140:144, deliberately excluded from shading.
    return key

func _dispatch_stage(cmds: int, stage: int, count: int) -> void:
    var names: Dictionary={1:"clear",2:"project_and_shadow",3:"raster",4:"material",
        6:"compose",7:"exposure",8:"direct",9:"panel_graph",10:"bounce",
        11:"seam_recovery",12:"seam_commit",13:"relight_shadow",14:"shadow_clear"}
    var label: String=names.get(stage,str(stage))
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,label,"begin"))
    _rd.compute_list_set_push_constant(cmds,PackedInt32Array([stage,2,0,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(cmds,ceili(float(count)/64.),1,1)
    _rd.compute_list_add_barrier(cmds)
    _rd.capture_timestamp(pass_profile.marker(get_instance_id(),frame_count+1,label,"end"))
    _last_stages.append(stage)

func _render_callback(_type: int,_data: RenderData) -> void:
    if not capture_loaded or (not gpu_ready and not _initialize()):return
    _mutex.lock()
    var next: Dictionary=_pending.duplicate()
    _mutex.unlock()
    if next.is_empty():return
    _collect_profile()
    pass_profile.collect(_rd,get_instance_id())
    var params: PackedByteArray=next["parameters"]
    var all: PackedByteArray=params.duplicate()
    all.append_array(next["instances"])
    all.append_array(next["jobs"])
    if all==_resident:
        idle_reuses+=1
        return
    var work: int=next["work"]
    var n: int=next["instances"].size()/96
    if n>PANEL_CAP or n<1:return
    var geometry: PackedByteArray=_camera_geometry_key(params,next["instances"],next["jobs"])
    var graph: PackedByteArray=next["instances"] # Independent of camera and LOD jobs.
    var light: PackedByteArray=_light_key(params)
    var appearance: PackedByteArray=_appearance_key(params,geometry)
    var rebuild_geometry: bool=geometry!=_geometry_key
    var rebuild_graph: bool=graph!=_graph_key
    var rebuild_shadow: bool=rebuild_geometry or light!=_shadow_key
    var relight: bool=rebuild_geometry or rebuild_graph or appearance!=_lighting_key
    var reallocate: bool=work>projection_capacity
    if reallocate:
        if _set.is_valid():_rd.free_rid(_set)
        _set=RID()
        if _buffers[3].is_valid():_rd.free_rid(_buffers[3])
        allocation_bytes-=int(_lengths[3])
        projection_capacity=mini(MAX_WORK,int(ceil(float(work)/65536.))*65536)
        _buffer(3,projection_capacity*96)
        _make_set()
        rebuild_geometry=true
        rebuild_shadow=true
        relight=true
    # Uniforms always update, but immutable instance jobs need only be
    # reuploaded when those bytes change. Light-only requests skip both.
    _rd.buffer_update(_buffers[6],0,256,params)
    if rebuild_geometry:
        _rd.buffer_update(_buffers[1],0,next["instances"].size(),next["instances"])
        _rd.buffer_update(_buffers[2],0,next["jobs"].size(),next["jobs"])
    var pixels: int=render_size*render_size
    var cmds: int=_rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(cmds,_pipeline)
    _rd.compute_list_bind_uniform_set(cmds,_set,0)
    _last_stages=[]
    pass_profile.set_context(frame_count+1,{"mode":"geometry" if rebuild_geometry else "relight" if relight else "exposure",
        "internal_resolution":render_size,"instances":n,"source_work":work})
    _rd.capture_timestamp(_profile_marker("begin"))
    if rebuild_geometry:
        # 1 resets sample depth/winners and the light-shadow atlas.
        _dispatch_stage(cmds,1,maxi(pixels,512*512))
        _dispatch_stage(cmds,2,work)
        _dispatch_stage(cmds,3,work)
        geometry_rebuilds+=1
        shadow_rebuilds+=1
    elif rebuild_shadow:
        # 14 resets SHADOW ONLY, 13 projects samples into light space ONLY.
        # Camera-space normals, coverage and depth remain identical.
        _dispatch_stage(cmds,14,512*512)
        _dispatch_stage(cmds,13,work)
        shadow_rebuilds+=1
    if rebuild_graph:
        # O(P^3) proof-of-concept graph, NOT yet the sparse CSR world solver.
        # This graph cannot depend on camera movement or light position.
        _dispatch_stage(cmds,9,n)
        graph_rebuilds+=1
    if relight:
        _dispatch_stage(cmds,8,n)
        _dispatch_stage(cmds,10,n)
        _dispatch_stage(cmds,4,pixels)
        _dispatch_stage(cmds,6,pixels)
        _dispatch_stage(cmds,11,pixels)
        _dispatch_stage(cmds,12,pixels)
        lighting_resolves+=1
        transport_dispatches+=1
    # Only exposure: just stage 7; no projection, shadow, graph or shading.
    _dispatch_stage(cmds,7,output_size*output_size)
    output_resolves+=1
    _rd.compute_list_end()
    _rd.capture_timestamp(_profile_marker("end"))
    _resident=all
    _geometry_key=geometry
    _graph_key=graph
    _shadow_key=light
    _lighting_key=appearance
    _cache_events.append({"frame":frame_count+1,"kind":"geometry" if rebuild_geometry else "relight" if relight else "exposure",
        "stages":_last_stages.duplicate()})
    if _cache_events.size()>24:_cache_events=_cache_events.slice(_cache_events.size()-24)
    sample_invocations=work
    instance_count=n
    frame_count+=1

func cache_metrics() -> Dictionary:
    return {"geometry_rebuilds":geometry_rebuilds,"shadow_rebuilds":shadow_rebuilds,
        "graph_rebuilds":graph_rebuilds,"lighting_resolves":lighting_resolves,
        "output_resolves":output_resolves,"idle_reuses":idle_reuses,
        "last_stages":_last_stages.duplicate(),"events":_cache_events.duplicate(true),
        "work_limit":MAX_WORK,
        "source":"WALL05 independent frame signatures; shared LIE22 sample bank"}

func force_geometry_rebuild() -> void:
    if gpu_ready:RenderingServer.call_on_render_thread(func():
        _geometry_key=PackedByteArray()
        _graph_key=PackedByteArray()
        _resident=PackedByteArray()
    )

func _capture() -> void:
    super._capture()
    if not gpu_ready:return
    pass_profile.collect(_rd,get_instance_id())
    var n: int=mini(instance_count,PANEL_CAP)
    if n<=0:return
    var direct: PackedFloat32Array=_rd.buffer_get_data(_buffers[14]).to_float32_array()
    var bounce: PackedFloat32Array=_rd.buffer_get_data(_buffers[16]).to_float32_array()
    var pairs: PackedFloat32Array=_rd.buffer_get_data(_buffers[15]).to_float32_array()
    var dsum:=Vector3.ZERO
    var bsum:=Vector3.ZERO
    var positive: int=0
    var active_links: int=0
    var energy_violations: int=0
    var max_row_sum: float=0.
    for emitter in range(n):
        var row_sum: float=0.
        for receiver in range(n):
            var w: float=pairs[emitter*PANEL_CAP+receiver]
            if w>0:active_links+=1
            if not is_finite(w) or w<0.:energy_violations+=1
            row_sum+=w
        max_row_sum=maxf(max_row_sum,row_sum)
        if row_sum>1.0001 or not is_finite(row_sum):energy_violations+=1
    for i in range(n):
        var d:=Vector3(direct[i*4],direct[i*4+1],direct[i*4+2])
        var b:=Vector3(bounce[i*4],bounce[i*4+1],bounce[i*4+2])
        dsum+=d
        bsum+=b
        if b.length_squared()>1e-12:positive+=1
    _mutex.lock()
    _readback["cache"]=cache_metrics()
    _readback["passes"]=pass_profile.snapshot()
    _readback["multiwall_transport"]={
        "panels":n,
        "direct_irradiance_sum":[dsum.x,dsum.y,dsum.z],
        "bounce_irradiance_sum":[bsum.x,bsum.y,bsum.z],
        "panels_with_bounce":positive,
        "active_links":active_links,
        "energy_violations":energy_violations,
        "max_row_sum":max_row_sum,
        "dispatches":transport_dispatches,
        "graph":"GPU panel-centre, oriented and aperture-aware, one diffuse bounce",
        "limitations":"finite source/receiver panels; not full WALL12 micro-patch global illumination",
        "mobile_fps_measured":false
    }
    _mutex.unlock()

func _release() -> void:
    super._release()
    _geometry_key=PackedByteArray()
    _graph_key=PackedByteArray()
    _shadow_key=PackedByteArray()
    _lighting_key=PackedByteArray()
