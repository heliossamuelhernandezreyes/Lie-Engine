extends RefCounted
## User controls and agent JSON share the same atomic state and validation.
const COLS=6
const ROWS=8
const COUNT=COLS*ROWS
const LIMITS={"pupil_radius":[.0008,.0032],"gaze_yaw":[-35,35],"gaze_pitch":[-25,25],"camera_yaw":[-80,80],"camera_elevation":[-10,35],"distance_factor":[.65,1.8],"variation":[0,.6],"light_azimuth":[-100,100],"light_power":[.25,3],"exposure":[.5,3]}
var state: Dictionary={"mode":"eye","iris_color":[.22,.57,.76],"wall_color":[.92,.58,.38],"pupil_radius":.0017,"gaze_yaw":0.0,"gaze_pitch":0.0,
    "camera_yaw":0.0,"camera_elevation":10.0,"distance_factor":1.0,"variation":.28,"seed":1203,"coating":true,"grouped":true,"simulate":true,
    "light_azimuth":-35.0,"light_power":1.0,"exposure":1.4,"damage":[]}
var revision: int=0
var history: Array=[]
var future: Array=[]
func _init() -> void:
    state["damage"].resize(COUNT);state["damage"].fill(0.0)
func snapshot() -> Dictionary:return {"schema":1,"revision":revision,"document":state.duplicate(true),"undo_count":history.size(),"redo_count":future.size()}
func validate(value: Variant) -> String:
    if not value is Dictionary or value.keys().size()!=state.keys().size():return "document_shape"
    for key in state:
        if not value.has(key):return "missing_"+key
    if value["mode"] not in ["eye","wall"]:return "mode"
    for key in LIMITS:
        var v: Variant=value[key]
        if not (v is int or v is float) or not is_finite(float(v)) or float(v)<LIMITS[key][0] or float(v)>LIMITS[key][1]:return "range_"+key
    for key in ["coating","grouped","simulate"]:
        if not value[key] is bool:return "boolean_"+key
    for key in ["iris_color","wall_color"]:
        if not value[key] is Array or value[key].size()!=3:return "color_"+key
        for c in value[key]:
            if not (c is int or c is float) or not is_finite(float(c)) or c<0 or c>1:return "color_"+key
    var seed: Variant=value["seed"]
    if not (seed is int or seed is float) or not is_finite(float(seed)) or seed!=floor(float(seed)) or seed<0 or seed>1000000:return "seed"
    if not value["damage"] is Array or value["damage"].size()!=COUNT:return "damage_shape"
    for health in value["damage"]:
        if not (health is int or health is float) or not is_finite(float(health)) or health<0 or health>100:return "damage_range"
    return ""
func _edit(next: Dictionary,request: Dictionary) -> String:
    var op: String=str(request.get("op",""))
    if op=="set_values":
        var values: Variant=request.get("values")
        if not values is Dictionary or values.is_empty():return "values_object"
        for key in values:
            if not next.has(key) or key=="damage":return "unknown_field"
            next[key]=values[key]
    elif op=="strike":
        var cell: Variant=request.get("cell");var energy: Variant=request.get("energy",100.0)
        if not (cell is int or cell is float) or not is_finite(float(cell)) or cell!=floor(float(cell)) or cell<0 or cell>=COUNT:return "cell"
        if not (energy is int or energy is float) or not is_finite(float(energy)) or energy<=0 or energy>1000:return "energy"
        next["damage"][int(cell)]=minf(100,float(next["damage"][int(cell)])+float(energy))
    elif op=="reset_wall":next["damage"].fill(0.0)
    else:return "unknown_operation"
    return validate(next)
func dispatch(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request_object","revision":revision}
    if request.has("expected_revision"):
        var expected: Variant=request["expected_revision"]
        if not (expected is int or expected is float) or not is_finite(float(expected)) or expected!=revision:return {"ok":false,"error":"revision_conflict","revision":revision}
    var op: String=str(request.get("op",""))
    if op=="snapshot":return {"ok":true,"snapshot":snapshot(),"revision":revision}
    if op in ["undo","redo"]:
        var source: Array=history if op=="undo" else future
        var target: Array=future if op=="undo" else history
        if source.is_empty():return {"ok":false,"error":"history_empty","revision":revision}
        target.append(state.duplicate(true));state=source.pop_back();revision+=1;return {"ok":true,"revision":revision}
    if op=="save_document":
        DirAccess.make_dir_recursive_absolute("user://modular22")
        var file:=FileAccess.open("user://modular22/document.json.tmp",FileAccess.WRITE)
        if file==null:return {"ok":false,"error":"save_failed"}
        file.store_string(JSON.stringify({"schema":1,"state":state},"  ",true,true));file.close()
        var err: Error=DirAccess.rename_absolute("user://modular22/document.json.tmp","user://modular22/document.json")
        return {"ok":err==OK,"revision":revision}
    var next: Dictionary=state.duplicate(true);var error: String=""
    if op=="load_document":
        var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("user://modular22/document.json"))
        if not parsed is Dictionary or parsed.get("schema")!=1:return {"ok":false,"error":"load_contract","revision":revision}
        error=validate(parsed.get("state"))
        if error=="":next=parsed["state"].duplicate(true)
    elif op=="batch":
        var commands: Variant=request.get("commands")
        if not commands is Array or commands.is_empty() or commands.size()>64:return {"ok":false,"error":"batch_shape","revision":revision}
        for sub in commands:
            if not sub is Dictionary:error="request_object";break
            error=_edit(next,sub)
            if error!="":break
    else:error=_edit(next,request)
    if error!="":return {"ok":false,"error":error,"revision":revision}
    for key in LIMITS:next[key]=float(next[key])
    next["seed"]=int(next["seed"]);next["damage"]=next["damage"].map(func(v: Variant):return float(v))
    for key in ["iris_color","wall_color"]:next[key]=next[key].map(func(v: Variant):return float(v))
    if next!=state:
        history.append(state.duplicate(true));future.clear()
        if history.size()>64:history.pop_front()
        state=next;revision+=1
    return {"ok":true,"revision":revision}
static func connectivity(value: Dictionary) -> Dictionary:
    var removed: Array=[];var supported: Dictionary={};var queue: Array=[]
    for cell in range(COUNT):
        if float(value["damage"][cell])>=100:removed.append(cell)
        elif cell<COLS:supported[cell]=true;queue.append(cell)
    var index: int=0
    while index<queue.size():
        var cell: int=queue[index];index+=1;var col: int=cell%COLS
        var neighbors: Array=[cell-COLS,cell+COLS]
        if col>0:neighbors.append(cell-1)
        if col<COLS-1:neighbors.append(cell+1)
        for n in neighbors:
            if n>=0 and n<COUNT and not supported.has(n) and float(value["damage"][n])<100:supported[n]=true;queue.append(n)
    var unsupported: Array=[]
    for cell in range(COUNT):
        if float(value["damage"][cell])<100 and not supported.has(cell):unsupported.append(cell)
    return {"removed":removed,"supported":supported,"unsupported":unsupported}
