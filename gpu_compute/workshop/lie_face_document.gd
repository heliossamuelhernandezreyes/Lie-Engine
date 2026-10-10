extends RefCounted
## The human inspector and agents use the same atomic, bounded commands.
const LIMITS: Dictionary={"head_yaw":[-25,25],"blink":[0,1],"gaze_yaw":[-30,30],"gaze_pitch":[-20,20],"pupil_radius":[.0008,.0032],"sss":[0,1],"roughness":[.5,1.5],"exposure":[.5,3],
    "camera_yaw":[-90,90],"camera_elevation":[-25,25],"distance":[.75,1.5],"light_azimuth":[-120,120],"light_power":[.1,12]}
var state: Dictionary={"head_yaw":0.0,"blink":0.0,"gaze_yaw":0.0,"gaze_pitch":0.0,"pupil_radius":.0017,"sss":1.0,"roughness":1.0,"exposure":1.4,
    "camera_yaw":8.0,"camera_elevation":0.0,"distance":1.0,"light_azimuth":-35.0,"light_power":5.0,"shadows":true,"framing":"face",
    "skin_tint":[1.0,1.0,1.0],"iris_color":[.22,.57,.76],"light_color":[1.0,.87,.74],"playing":false,"time":0.0}
var revision: int=0
var history: Array=[]
var future: Array=[]

func snapshot() -> Dictionary:
    return {"schema":1,"revision":revision,"document":state.duplicate(true),"undo_count":history.size(),"redo_count":future.size(),"master":"lie-open-face23"}

func validate(candidate: Variant) -> String:
    if not candidate is Dictionary or candidate.keys().size()!=state.keys().size(): return "document_shape"
    for key in LIMITS:
        var value: Variant=candidate.get(key)
        if not (value is int or value is float) or not is_finite(float(value)) or float(value)<LIMITS[key][0] or float(value)>LIMITS[key][1]: return "range_"+str(key)
    for key in ["shadows","playing"]:
        if not candidate.get(key) is bool: return "boolean_"+key
    var time: Variant=candidate.get("time")
    if not (time is int or time is float) or not is_finite(float(time)) or float(time)<0 or float(time)>4: return "range_time"
    if candidate.get("framing") not in ["bust","face","eyes"]:return "framing"
    for key in ["light_color","skin_tint","iris_color"]:
        var color: Variant=candidate.get(key)
        if not color is Array or color.size()!=3:return key
        for v in color:
            if not (v is int or v is float) or not is_finite(float(v)) or float(v)<0 or float(v)>1:return key
    return ""

func dispatch(request: Variant) -> Dictionary:
    if not request is Dictionary: return {"ok":false,"error":"request_object","revision":revision}
    if request.has("expected_revision"):
        var expected: Variant=request["expected_revision"]
        if not (expected is int or expected is float) or not is_finite(float(expected)) or expected!=revision: return {"ok":false,"error":"revision_conflict","revision":revision}
    var op: String=str(request.get("op",""))
    if op=="snapshot": return {"ok":true,"snapshot":snapshot(),"revision":revision}
    if op=="save_document":
        DirAccess.make_dir_recursive_absolute("user://face23")
        var file:=FileAccess.open("user://face23/document.json.tmp",FileAccess.WRITE)
        if file==null: return {"ok":false,"error":"save_failed","revision":revision}
        file.store_string(JSON.stringify({"schema":1,"master":"lie-open-face23","state":state},"  ",true,true));file.close()
        var err: Error=DirAccess.rename_absolute("user://face23/document.json.tmp","user://face23/document.json")
        return {"ok":err==OK,"error":"" if err==OK else "save_failed","revision":revision}
    if op in ["undo","redo"]:
        var source: Array=history if op=="undo" else future
        var target: Array=future if op=="undo" else history
        if source.is_empty(): return {"ok":false,"error":"history_empty","revision":revision}
        target.append(state.duplicate(true));state=source.pop_back();revision+=1
        return {"ok":true,"revision":revision}
    var next: Dictionary=state.duplicate(true)
    if op=="set_values":
        var values: Variant=request.get("values")
        if not values is Dictionary or values.is_empty(): return {"ok":false,"error":"values_object","revision":revision}
        for key in values:
            if not LIMITS.has(key) and key not in ["shadows","light_color","skin_tint","iris_color","framing"]: return {"ok":false,"error":"unknown_field","revision":revision}
            next[key]=values[key]
    elif op=="set_playing": next["playing"]=request.get("value")
    elif op=="set_time": next["time"]=request.get("value")
    elif op=="load_document":
        var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://face23/document.json")) if FileAccess.file_exists("user://face23/document.json") else null
        if not parsed is Dictionary or parsed.get("schema")!=1 or parsed.get("master")!="lie-open-face23": return {"ok":false,"error":"load_contract","revision":revision}
        if not parsed.get("state") is Dictionary: return {"ok":false,"error":"document_shape","revision":revision}
        next=parsed["state"].duplicate(true)
    else: return {"ok":false,"error":"unknown_operation","revision":revision}
    var error: String=validate(next)
    if error!="": return {"ok":false,"error":error,"revision":revision}
    # JSON numbers load as floats. Canonical numeric types preserve equality,
    # save/load behavior and undo independently of the command's origin.
    for key in LIMITS: next[key]=float(next[key])
    next["time"]=float(next["time"])
    for key in ["light_color","skin_tint","iris_color"]:next[key]=next[key].map(func(value: Variant):return float(value))
    if next!=state:
        history.append(state.duplicate(true));future.clear()
        if history.size()>64: history.pop_front()
        state=next;revision+=1
    return {"ok":true,"revision":revision}

func evaluated() -> Dictionary:
    var result: Dictionary=state.duplicate(true)
    if state["playing"]:
        var phase: float=float(state["time"])*TAU/4
        result["head_yaw"]=sin(phase)*12
        result["gaze_yaw"]=sin(phase+1)*20
        var t: float=float(state["time"])
        result["blink"]=maxf(float(state["blink"]),sin((t-1.7)/.35*PI) if t>1.7 and t<2.05 else 0)
    return result
