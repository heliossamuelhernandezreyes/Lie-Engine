extends RefCounted
## Pure corroboration/formatting; never fabricates hardware or GPU timing.
static func corroborate(sample: Dictionary,gpu: Dictionary,expected: int) -> Dictionary:
    var complete: int=0;var milliseconds: float=0.
    for group in gpu.get("groups",[]):
        complete+=group["serials"].size()
        # Sum actual per-event totals from the disjoint rows supplied by caller.
    milliseconds=float(gpu.get("instrumented_gpu_ms",0.))
    var result: Dictionary={"valid":false,"completed_gpu_events":complete,"expected_gpu_events":expected,"instrumented_gpu_ms":milliseconds,"scope":"same serials, independent Godot timestamp evidence; clock domains uncalibrated"}
    if not sample.get("available",false):result["reason"]="hardware_sample_failed";return result
    if complete!=expected:result["reason"]="gpu_timestamps_incomplete";return result
    var activity: Dictionary=sample.get("counters",{}).get("GPU active cycles",{})
    if not activity.get("available",false):result["reason"]="activity_counter_unavailable";return result
    var raw: Variant=activity.get("value",null)
    if not (raw is String and raw.is_valid_int()) and not (raw is int or raw is float):result["reason"]="activity_counter_invalid";return result
    if float(raw)==0. and milliseconds>0.:result["reason"]="empty_hardware_interval_despite_gpu_work";return result
    result["valid"]=true;result["reason"]="corroborated" if milliseconds>0. else "idle_interval";return result
static func telemetry(data: Dictionary) -> Dictionary:
    var result: Dictionary={"host_monotonic_ns":data.get("host_monotonic_ns","")}
    for key in ["gpu_frequency","gpu_temperature","thermal_status"]:
        var source: Dictionary=data.get(key,{})
        if not source.get("available",false):result[key]=null
        elif key=="gpu_temperature":
            var sensors: Array=[]
            for sensor in source.get("sensors",[]):sensors.append({"sensor_type":sensor["sensor_type"],"value":sensor["value"]})
            result[key]=sensors
        else:result[key]=source.get("value",null)
    return result
static func compact(profile: Dictionary) -> Dictionary:
    var result: Dictionary=profile.duplicate(true);var ids: Dictionary={}
    for counter in result.get("status",{}).get("supported",[]):ids[counter["name"]]=str(counter["id"])
    # Keep names, units, unavailable reasons and paths once in status/telemetry.
    result["counter_encoding"]="counter_values keys reference status.supported.id; decimal strings preserve uint64; null telemetry means unavailable, see initial telemetry reasons/units"
    result["telemetry_units"]={"gpu_frequency":"Hz","gpu_temperature":"millidegrees Celsius","thermal_status":"Android device thermal policy code, not GPU temperature"}
    for block in result.get("blocks",[]):
        var serials: Array=[]
        for event in block.get("events",[]):serials.append(event.get("serial",-1))
        block["serials"]=serials;block.erase("events")
        if block.has("gpu_evidence"):
            var evidence: Dictionary=block["gpu_evidence"]
            block["gpu_evidence"]={"instrumented_gpu_ms":evidence.get("instrumented_gpu_ms",0.),"complete_events":block.get("sample",{}).get("validity",{}).get("completed_gpu_events",0)}
        for key in ["telemetry_before","telemetry_after"]:block[key]=telemetry(block.get(key,{}))
        var sample: Dictionary=block.get("sample",{});var values: Dictionary={};var errors: Dictionary={}
        for name in sample.get("counters",{}):
            var row: Dictionary=sample["counters"][name];var id: String=ids.get(name,name)
            if row.get("available",false):values[id]=row["value"]
            else:errors[id]=row.get("reason","unavailable")
        sample["counter_values"]=values
        if not errors.is_empty():sample["counter_errors"]=errors
        sample.erase("counters");sample.erase("scope")
    return result
