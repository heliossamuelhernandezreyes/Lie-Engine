extends "res://lie22_modular_effect.gd"
## Shared material captures; the only extra per-frame data are cable frames.
const RobotShader=preload("res://shaders/lie_robot.glsl")
const CURVE_POINTS=16
const CURVE_BYTES=CURVE_POINTS*48
const MAX_CURVES=16
var _active_jobs:=PackedInt32Array()
var _active_instances:=PackedFloat32Array()
var _active_curves:=PackedFloat32Array()
var partial_cache_enabled: bool=true
var _world_keys: Array=[]
var _job_key:=PackedByteArray()
var _world_globals:=PackedByteArray()
var _cached_capacity: int=-1
var _static_shadow_key:=PackedByteArray()
var _combined_shadow_key:=PackedByteArray()
var _raster_key:=PackedByteArray()
var _pass_frame: int=-1
var _pass_profiles: Array=[]
var _cache_totals: Dictionary={"transformed_samples":0,"reused_world_samples":0,"static_shadow_rebuilds":0,"static_shadow_hits":0,"combined_shadow_rebuilds":0,"combined_shadow_hits":0,"raster_rebuilds":0,"raster_hits":0}

func capture_root() -> String:return "res://captures/robot_refined/" if FileAccess.file_exists("res://captures/robot_refined/catalog.json") else "res://captures/robot_modular/"
func sample_stride() -> int:return 96
func shader_resource() -> RDShaderFile:return RobotShader
func maximum_output_size() -> int:return 1024
func initialize_extra_buffers() -> void:
    _buffer(14,MAX_CURVES*CURVE_BYTES)
    _buffer(15,maximum_instances()*48) # One inverse rigid frame per instance.
    _buffer(16,512*512*4) # Persistent static shadow depth, only 1 MiB.
func extra_signature(next: Dictionary) -> PackedByteArray:
    var bytes: PackedByteArray=next.get("curves",PackedByteArray()).duplicate()
    bytes.append_array(PackedInt32Array([next.get("static_begin",next["instances"].size()/96),int(partial_cache_enabled)]).to_byte_array());return bytes
func update_extra_buffers(next: Dictionary) -> void:
    var data: PackedByteArray=next["curves"]
    if not data.is_empty():_rd.buffer_update(_buffers[14],0,data.size(),data)
    _active_jobs=next["jobs"].to_int32_array();_active_instances=next["instances"].to_float32_array();_active_curves=data.to_float32_array()

func configure_robot(parameters: PackedByteArray,instances: PackedByteArray,jobs: PackedByteArray,work: int,curves: PackedByteArray,static_begin: int=-1) -> bool:
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
    if static_begin<0:static_begin=instances.size()/96
    if static_begin>instances.size()/96:return false
    _mutex.lock();_pending={"parameters":parameters.duplicate(),"instances":instances.duplicate(),"jobs":jobs.duplicate(),"work":work,"curves":curves.duplicate(),"static_begin":static_begin};_mutex.unlock();return true

func _pass(label: String,stage: int,ranges: Array,static_target: int=0) -> void:
    if ranges.is_empty():return
    _rd.capture_timestamp("robot-"+label+"-begin")
    var list: int=_rd.compute_list_begin();_rd.compute_list_bind_compute_pipeline(list,_pipeline);_rd.compute_list_bind_uniform_set(list,_set,0)
    for span in ranges:
        if span[1]<=0:continue
        _rd.compute_list_set_push_constant(list,PackedInt32Array([stage,span[1] if stage in [8,9] else 2,span[0],static_target]).to_byte_array(),16)
        _rd.compute_list_dispatch(list,int(ceil(float(span[1])/64)),1,1)
    _rd.compute_list_end();_rd.capture_timestamp("robot-"+label+"-end")

func dispatch_reconstruction(next: Dictionary,work: int) -> void:
    var parameters: PackedByteArray=next["parameters"];var objects: PackedByteArray=next["instances"]
    var jobs: PackedInt32Array=next["jobs"].to_int32_array();var curves: PackedByteArray=next["curves"]
    var globals: PackedByteArray=parameters.slice(208,224);globals.append_array(parameters.slice(244,248))
    var all_dirty: bool=not partial_cache_enabled or _job_key!=next["jobs"] or _world_globals!=globals or _cached_capacity!=projection_capacity
    var keys: Array=[];var changed: Array=[];var static_key:=PackedByteArray();var combined_key:=PackedByteArray()
    var static_ranges: Array=[];var dynamic_ranges: Array=[];var transformed: int=0
    for j in range(jobs.size()/4):
        var object: int=jobs[j*4+2];var offset: int=object*96
        var key: PackedByteArray=objects.slice(offset,offset+64);key.append_array(objects.slice(offset+68,offset+76))
        var curve: int=int(objects.decode_float(offset+68))
        if curve>=0:key.append_array(curves.slice(curve*CURVE_BYTES,(curve+1)*CURVE_BYTES))
        keys.append(key)
        var span: Array=[jobs[j*4+3],jobs[j*4+1]]
        if all_dirty or j>=_world_keys.size() or key!=_world_keys[j]:changed.append(span);transformed+=span[1]
        var shadow_part: PackedByteArray=key.duplicate();shadow_part.append_array(next["jobs"].slice(j*16,j*16+16))
        combined_key.append_array(shadow_part)
        if object>=next["static_begin"]:static_key.append_array(shadow_part);static_ranges.append(span)
        else:dynamic_ranges.append(span)
    var light_key: PackedByteArray=parameters.slice(96,108);light_key.append_array(parameters.slice(160,208));light_key.append_array(globals)
    static_key.append_array(light_key);combined_key.append_array(light_key)
    var static_dirty: bool=not partial_cache_enabled or _static_shadow_key!=static_key
    var shadow_dirty: bool=not partial_cache_enabled or _combined_shadow_key!=combined_key
    var raster_key: PackedByteArray=parameters.slice(0,96);raster_key.append_array(parameters.slice(156,160));raster_key.append_array(parameters.slice(208,248))
    raster_key.append_array(objects);raster_key.append_array(next["jobs"]);raster_key.append_array(curves)
    var raster_dirty: bool=not partial_cache_enabled or all_dirty or _raster_key!=raster_key
    if not changed.is_empty():
        _pass("inverse_frames",10,[[0,objects.size()/96]])
        _pass("world_transform",8,changed)
    var shadows: bool=parameters.decode_float(144)>.5
    if shadows and shadow_dirty:
        if static_dirty:
            _pass("static_shadow_clear",11,[[0,512*512]])
            _pass("static_shadow",9,static_ranges,1);_static_shadow_key=static_key
            _cache_totals["static_shadow_rebuilds"]+=1
        else:_cache_totals["static_shadow_hits"]+=1
        _pass("shadow_merge",12,[[0,512*512]])
        _pass("dynamic_shadow",9,dynamic_ranges);_combined_shadow_key=combined_key
        _cache_totals["combined_shadow_rebuilds"]+=1
    elif shadows:
        _cache_totals["static_shadow_hits"]+=1;_cache_totals["combined_shadow_hits"]+=1
    if raster_dirty:
        _pass("screen_clear",1,[[0,render_size*render_size]])
        _pass("project_depth",2,[[0,work]])
        _pass("material_accumulate",3,[[0,work]]);_raster_key=raster_key;_cache_totals["raster_rebuilds"]+=1
    else:_cache_totals["raster_hits"]+=1
    _pass("shade",4,[[0,render_size*render_size]])
    _pass("compose",6,[[0,render_size*render_size]])
    _pass("resolve",7,[[0,output_size*output_size]])
    _world_keys=keys;_job_key=next["jobs"].duplicate();_world_globals=globals;_cached_capacity=projection_capacity
    _cache_totals["transformed_samples"]+=transformed;_cache_totals["reused_world_samples"]+=work-transformed
    var cache: Dictionary={"enabled":partial_cache_enabled,"work_samples":work,"transformed_samples_last":transformed,"reused_world_samples_last":work-transformed,"static_shadow_rebuilt_last":shadows and shadow_dirty and static_dirty,"combined_shadow_rebuilt_last":shadows and shadow_dirty,"raster_rebuilt_last":raster_dirty,"submitted_frame":frame_count+1,"totals":_cache_totals.duplicate(true)}
    _mutex.lock();_performance["cache"]=cache;_mutex.unlock()

func _collect_profile() -> void:
    super._collect_profile()
    var frame: int=_rd.get_captured_timestamps_frame()
    if frame==_pass_frame:return
    _pass_frame=frame
    var starts: Dictionary={};var timings: Dictionary={}
    for i in range(_rd.get_captured_timestamps_count()):
        var name: String=_rd.get_captured_timestamp_name(i)
        if not name.begins_with("robot-"):continue
        var ns: int=_rd.get_captured_timestamp_gpu_time(i)
        if name.ends_with("-begin"):starts[name.trim_suffix("-begin")]=ns
        elif name.ends_with("-end"):
            var key: String=name.trim_suffix("-end")
            if starts.has(key) and ns>=starts[key]:timings[key.trim_prefix("robot-")]=(ns-starts[key])/1000000.0
    if timings.is_empty():return
    _pass_profiles.append(timings)
    if _pass_profiles.size()>120:_pass_profiles.pop_front()
    var values: Dictionary={}
    for profile in _pass_profiles:
        for key in profile:
            if not values.has(key):values[key]=[]
            values[key].append(profile[key])
    var recent: Dictionary={}
    for key in values:
        var v: Array=values[key];v.sort();recent[key]={"p50_ms":v[maxi(int(ceil(v.size()*.5))-1,0)],"p95_ms":v[maxi(int(ceil(v.size()*.95))-1,0)],"samples":v.size()}
    _mutex.lock();_performance.merge({"gpu_pass_ms_last":timings,"gpu_pass_recent":recent,"gpu_pass_marker_frame":frame,"gpu_pass_sample_usec":Time.get_ticks_usec()},true);_mutex.unlock()

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
