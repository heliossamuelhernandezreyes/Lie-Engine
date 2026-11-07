extends RefCounted
## Bounded, per-block measurements. No GPU reads or inferred idle solve times.
const Stats=preload("res://lie_mobile_diagnostics.gd")
var frames: Array=[]
var commands: Array=[]
var appearance: Array=[]
var lighting: Array=[]
var seen: Dictionary={}
var floors: Dictionary={}
var dropped: int=0
func begin(appearance_data: Dictionary,light_owner: int,light_data: Dictionary) -> void:
    frames=[];commands=[];appearance=[];lighting=[];seen={};dropped=0
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
func _collect(owner: String,rows: Array,target: Array) -> void:
    for row in rows:
        var serial: int=int(row.get("serial",-1));var ns: float=float(row.get("gpu_ns",-1));var key: String=owner+":"+str(serial)
        if serial<=floors.get(owner,0) or seen.has(key) or not is_finite(ns) or ns<=0:continue
        seen[key]=true
        if target.size()<120000:target.append({"owner":owner,"serial":serial,"gpu_ns":ns})
        else:dropped+=1
func result() -> Dictionary:
    var a: Array=[];var l: Array=[]
    for row in appearance:a.append(row.gpu_ns/1e6)
    for row in lighting:l.append(row.gpu_ns/1e6)
    return {"display_frame_ms":Stats.percentiles(frames),"command_cpu_ms":Stats.percentiles(commands),
        "appearance_gpu_ms":Stats.percentiles(a),"lighting_gpu_ms":Stats.percentiles(l),
        "appearance_rows":appearance.duplicate(true),"lighting_rows":lighting.duplicate(true),"dropped_samples":dropped,
        "scope":"Frame intervals include presentation, CPU and waiting. Appearance and transport are separate GPU timestamp intervals; their percentiles must not be added. Cached idle produces no new LIE solve sample. Includes cold events after the explicit warm-up; missing timestamps stay unavailable."}
