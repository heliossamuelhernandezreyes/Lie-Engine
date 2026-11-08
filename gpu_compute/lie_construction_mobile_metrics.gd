extends RefCounted
## Bounded, per-block measurements. No GPU reads or inferred idle solve times.
const Stats=preload("res://lie_mobile_diagnostics.gd")
var frames: Array=[]
var commands: Array=[]
var appearance: Array=[]
var lighting: Array=[]
var planning: Array=[]
var seen: Dictionary={}
var floors: Dictionary={}
var dropped: int=0
func begin(appearance_data: Dictionary,light_owner: int,light_data: Dictionary) -> void:
    frames=[];commands=[];appearance=[];lighting=[];planning=[];seen={};dropped=0
    floors={"a:"+str(appearance_data.get("owner",0)):int(appearance_data.get("frames",0)),"l:"+str(light_owner):int(light_data.get("solves",0))}
func add_frame(ms: float) -> void:
    if is_finite(ms) and ms>0:
        if frames.size()<120000:frames.append(ms)
        else:dropped+=1
func add_command(ms: float) -> void:
    if is_finite(ms) and ms>=0:
        if commands.size()<120000:commands.append(ms)
        else:dropped+=1
func collect(a: Dictionary,light_owner: int,l: Dictionary) -> void:
    _collect("a:"+str(a.get("owner",0)),a.get("profile",[]),appearance)
    _collect("l:"+str(light_owner),l.get("profile",[]),lighting)
    var owner: String="a:"+str(a.get("owner",0))
    for row in a.get("camera_plan_profile",[]):
        var serial: int=int(row.get("serial",-1));var us: float=float(row.get("cpu_usec",-1));var key: String="p:"+owner+":"+str(serial)
        if serial<=floors.get(owner,0) or seen.has(key) or not is_finite(us) or us<0:continue
        seen[key]=true
        if planning.size()<120000:planning.append({"serial":serial,"cpu_ms":us/1000.})
        else:dropped+=1
func _collect(owner: String,rows: Array,target: Array) -> void:
    for row in rows:
        var serial: int=int(row.get("serial",-1));var ns: float=float(row.get("gpu_ns",-1));var key: String=owner+":"+str(serial)
        if serial<=floors.get(owner,0) or seen.has(key) or not is_finite(ns) or ns<=0:continue
        seen[key]=true
        if target.size()<120000:target.append({"owner":owner,"serial":serial,"gpu_ns":ns,"passes_ns":row.get("passes_ns",{}).duplicate(),"executed_passes":row.get("executed_passes",[]).duplicate()})
        else:dropped+=1
func result() -> Dictionary:
    var a: Array=[];var l: Array=[];var p: Array=[];var passes: Dictionary={}
    for row in appearance:
        a.append(row.gpu_ns/1e6)
        for name in row.passes_ns:
            var ns: float=float(row.passes_ns[name])
            if not is_finite(ns) or ns<=0:continue
            if not passes.has(name):passes[name]=[]
            passes[name].append(ns/1e6)
    for row in lighting:l.append(row.gpu_ns/1e6)
    for row in planning:p.append(row.cpu_ms)
    var pass_stats: Dictionary={}
    for name in passes:pass_stats[name]=Stats.percentiles(passes[name])
    return {"display_frame_ms":Stats.percentiles(frames),"command_cpu_ms":Stats.percentiles(commands),
        "appearance_gpu_ms":Stats.percentiles(a),"appearance_passes_gpu_ms":pass_stats,"lighting_gpu_ms":Stats.percentiles(l),"visibility_planning_cpu_ms":Stats.percentiles(p),
        "appearance_rows":appearance.duplicate(true),"lighting_rows":lighting.duplicate(true),"visibility_planning_rows":planning.duplicate(true),"dropped_samples":dropped,
        "scope":"Frame intervals include presentation, CPU and waiting. Appearance and transport are separate GPU timestamp intervals; their percentiles must not be added. Cached idle produces no new LIE solve sample. Includes cold events after the explicit warm-up; missing timestamps stay unavailable."}
