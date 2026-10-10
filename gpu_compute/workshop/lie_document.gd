extends RefCounted
## The same validated commands are used by the workshop UI and agent CLI.
## Joint frames do not inherit piece scale. IDs/slots are stable during playback.
const Legacy=preload("res://lie15_model.gd")
const LIMIT: int=30
const SCHEMA: int=1
const COMMANDS: Array=["add_piece","duplicate_piece","update_piece","remove_piece","set_track","set_key","set_light","set_material","set_camera","set_settings","set_time","set_playing","undo","redo","snapshot","batch"]
var state: Dictionary
var revision: int=0
var _undo: Array[Dictionary]=[]
var _redo: Array[Dictionary]=[]

func _init() -> void:
    state=default_state()

static func vec(value: Array) -> Vector3:
    return Vector3(float(value[0]),float(value[1]),float(value[2]))
static func arr(value: Vector3) -> Array:
    return [value.x,value.y,value.z]
static func numeric(value: Variant) -> bool:
    return (value is float or value is int) and is_finite(float(value))
static func vector_ok(value: Variant,lo: float=-100,hi: float=100) -> bool:
    if not value is Array or value.size()!=3: return false
    for n in value:
        if not numeric(n) or float(n)<lo or float(n)>hi: return false
    return true
static func valid_id(value: Variant) -> bool:
    if not value is String or value.length()<1 or value.length()>48: return false
    for c in value:
        if not (c.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-" ): return false
    return true

static func piece(id: String,slot: int) -> Dictionary:
    return {"id":id,"slot":slot,"master":"box","parent":"","position":[0,0,0],"rotation_deg":[0,0,0],"offset":[0,0,0],"scale":[.3,.3,.3],"axis":[1,0,0],"limits_deg":[-90,90],"angle_deg":0,"material":"steel"}

static func default_state() -> Dictionary:
    var initial: Array[Transform3D]=Legacy.skeleton(0)
    var parents: Array=[-1,0,0,0,3,0,5,2,7,8,2,10,11,1,1]
    var names: Array=["torso","head","hip","arm_l","forearm_l","arm_r","forearm_r","thigh_l","shin_l","foot_l","thigh_r","shin_r","foot_r","eye_l","eye_r"]
    var pieces: Array=[]
    var frames: Array[Transform3D]=[]
    for i in range(initial.size()):
        var rotation: Basis=initial[i].basis.orthonormalized()
        var scale: Vector3=initial[i].basis.get_scale()
        var pivot: Vector3=initial[i].origin
        if i in [3,4,5,6,7,8,10,11]: pivot+=rotation*Vector3(0,scale.y*.5,0)
        elif i in [9,12]: pivot-=rotation*Vector3(0,-.01,.1)
        elif i>=13: pivot=initial[1].origin
        var frame:=Transform3D(rotation,pivot)
        var local: Transform3D=frame if parents[i]<0 else frames[parents[i]].affine_inverse()*frame
        var p: Dictionary=piece(names[i],i)
        p["parent"]="" if parents[i]<0 else names[parents[i]]
        p["position"]=arr(local.origin)
        p["rotation_deg"]=arr(local.basis.get_euler()*180/PI)
        p["offset"]=arr(frame.affine_inverse()*initial[i].origin)
        p["scale"]=arr(scale)
        p["material"]=Legacy.material_name(i)
        p["master"]="cylinder" if i in [3,4,5,6,7,8,10,11] else "box"
        p["axis"]=[1,0,0]
        pieces.append(p); frames.append(frame)
    # Give the mechanical assembly clearance from torso and floor at rest.
    pieces[0]["position"][1]=float(pieces[0]["position"][1])+.12
    for i in [3,5]:
        pieces[i]["position"][0]=float(pieces[i]["position"][0])*1.16
        pieces[i]["rotation_deg"][2]=-float(pieces[i]["rotation_deg"][2])
    var tracks: Dictionary={}
    for id in ["arm_l","arm_r","thigh_l","thigh_r"]:
        var sign_value: float=-1 if id.ends_with("_l") else 1
        tracks[id]=[[0,0],[.5,sign_value*24],[1,0],[1.5,-sign_value*24],[2,0]]
    return {"schema":SCHEMA,"name":"Robot de piezas","pieces":pieces,"materials":Legacy.materials("bounce"),
        "lights":[{"position":[-1.7,2.3,1.8],"power_rgb":[130,115,95],"radius":7},{"position":[1.5,.8,-.5],"power_rgb":[24,40,65],"radius":5}],
        "camera":{"yaw_deg":24,"elevation_deg":10,"distance":4.1},"tracks":tracks,"duration":2.0,"time":0.0,"playing":false,
        "settings":{"bounces":2,"fluid":"off","wave_amplitude":.012,"rain_count":16,"adaptive":true,"temporal":true,"edges":true}}

static func validate(candidate: Variant) -> String:
    if not candidate is Dictionary or candidate.get("schema")!=SCHEMA: return "schema"
    if not candidate.get("name") is String or candidate["name"].length()>128: return "name"
    if not candidate.get("pieces") is Array or candidate["pieces"].is_empty() or candidate["pieces"].size()>LIMIT: return "piece_count"
    var ids: Dictionary={}; var slots: Dictionary={}
    for p in candidate["pieces"]:
        if not p is Dictionary or not valid_id(p.get("id")): return "piece_id"
        if ids.has(p["id"]): return "duplicate_id"
        if not numeric(p.get("slot")) or float(p["slot"])!=floorf(float(p["slot"])) or int(p["slot"])<0 or int(p["slot"])>=LIMIT or slots.has(int(p["slot"])): return "slot"
        ids[p["id"]]=p; slots[int(p["slot"])]=true
        if p.get("master") not in ["box","cylinder"]: return "master"
        if not p.get("parent") is String: return "parent"
        if p["parent"]==p["id"]: return "cycle"
        for field in ["position","offset","rotation_deg"]:
            if not vector_ok(p.get(field),-360 if field=="rotation_deg" else -10,360 if field=="rotation_deg" else 10): return field
        if not vector_ok(p.get("scale"),.02,5): return "scale"
        if not vector_ok(p.get("axis"),-1,1) or absf(vec(p["axis"]).length_squared()-1)>.00001: return "axis"
        if not p.get("limits_deg") is Array or p["limits_deg"].size()!=2: return "limits"
        for n in p["limits_deg"]:
            if not numeric(n) or absf(float(n))>180: return "limits"
        if p["limits_deg"][0]>p["limits_deg"][1] or not numeric(p.get("angle_deg")) or p["angle_deg"]<p["limits_deg"][0] or p["angle_deg"]>p["limits_deg"][1]: return "joint_limit"
        if not candidate.get("materials") is Dictionary or not candidate["materials"].has("room") or not candidate["materials"].has(p.get("material")): return "material"
    for p in candidate["pieces"]:
        var seen: Dictionary={}; var parent: String=p["id"]
        while parent!="":
            if not ids.has(parent): return "missing_parent"
            if seen.has(parent): return "cycle"
            seen[parent]=true; parent=ids[parent]["parent"]
    for m in candidate["materials"].values():
        if not m is Dictionary or not vector_ok(m.get("tint_linear"),0,1): return "tint"
        for field in ["roughness","metallic","emission","absorption_code"]:
            if not numeric(m.get(field)): return "material_"+field
            if float(m[field])<0 or float(m[field])>(1000 if field=="absorption_code" else 1): return "material_"+field
        if float(m["absorption_code"])!=floorf(float(m["absorption_code"])): return "absorption_code"
    if not candidate.get("lights") is Array: return "lights"
    for light in candidate["lights"]:
        if not light is Dictionary or not vector_ok(light.get("position"),-100,100) or not vector_ok(light.get("power_rgb"),0,1000000) or not numeric(light.get("radius")): return "light_values"
    if not Legacy.Model.valid_light_codes(candidate["lights"]): return "lights"
    if not numeric(candidate.get("duration")) or float(candidate["duration"])<.01 or float(candidate["duration"])>600: return "duration"
    if not numeric(candidate.get("time")) or float(candidate["time"])<0 or float(candidate["time"])>600: return "time"
    if not candidate.get("playing") is bool or not candidate.get("tracks") is Dictionary: return "tracks"
    for id in candidate["tracks"]:
        if not ids.has(id) or not candidate["tracks"][id] is Array or candidate["tracks"][id].size()>256: return "track_id"
        var last: float=-1
        for key in candidate["tracks"][id]:
            if not key is Array or key.size()!=2 or not numeric(key[0]) or not numeric(key[1]): return "keyframe"
            if float(key[0])<0 or float(key[0])<=last or float(key[0])>float(candidate["duration"]) or float(key[1])<ids[id]["limits_deg"][0] or float(key[1])>ids[id]["limits_deg"][1]: return "keyframe_range"
            last=float(key[0])
    var camera: Variant=candidate.get("camera")
    if not camera is Dictionary: return "camera"
    for field in ["yaw_deg","elevation_deg","distance"]:
        if not numeric(camera.get(field)): return "camera_"+field
    if absf(float(camera["yaw_deg"]))>360 or float(camera["elevation_deg"])< -65 or float(camera["elevation_deg"])>75 or float(camera["distance"])<2.5 or float(camera["distance"])>7: return "camera_range"
    var settings: Variant=candidate.get("settings")
    if not settings is Dictionary or settings.get("fluid") not in ["off","water","rain"]: return "fluid"
    for field in ["bounces","rain_count"]:
        if not numeric(settings.get(field)) or float(settings[field])!=floorf(float(settings[field])): return field
    if int(settings["bounces"])<0 or int(settings["bounces"])>4 or int(settings["rain_count"])<0 or int(settings["rain_count"])>24: return "settings_budget"
    if not numeric(settings.get("wave_amplitude")) or float(settings["wave_amplitude"])<0 or float(settings["wave_amplitude"])>.05: return "wave_amplitude"
    for field in ["adaptive","temporal","edges"]:
        if not settings.get(field) is bool: return field
    return ""

func snapshot() -> Dictionary:
    return {"revision":revision,"document":state.duplicate(true),"commands":COMMANDS,"maximum_pieces":LIMIT,"captures_per_animation":0}

func dispatch(request: Variant) -> Dictionary:
    if not request is Dictionary or not request.get("op") is String: return {"ok":false,"error":"request"}
    if request.has("expected_revision") and request["expected_revision"]!=revision: return {"ok":false,"error":"revision_conflict","revision":revision}
    var op: String=request["op"]
    if op=="snapshot": return {"ok":true,"snapshot":snapshot()}
    if op in ["undo","redo"]:
        var source: Array[Dictionary]=_undo if op=="undo" else _redo
        var target: Array[Dictionary]=_redo if op=="undo" else _undo
        if source.is_empty(): return {"ok":false,"error":"empty_history"}
        target.append(state.duplicate(true)); state=source.pop_back(); revision+=1
        return {"ok":true,"revision":revision}
    var next: Dictionary=state.duplicate(true)
    var commands: Variant=request.get("commands",[]) if op=="batch" else [request]
    if not commands is Array: return {"ok":false,"error":"batch"}
    var requests: Array=commands
    if requests.is_empty() or requests.size()>128: return {"ok":false,"error":"batch_size"}
    for command in requests:
        var error: String=_apply(next,command)
        if error!="": return {"ok":false,"error":error,"revision":revision}
    var error: String=validate(next)
    if error!="": return {"ok":false,"error":error,"revision":revision}
    _undo.append(state.duplicate(true)); if _undo.size()>64: _undo.pop_front()
    _redo.clear(); state=next; revision+=1
    return {"ok":true,"revision":revision}

static func index_of(candidate: Dictionary,id: String) -> int:
    for i in range(candidate["pieces"].size()):
        if candidate["pieces"][i]["id"]==id: return i
    return -1

static func _apply(next: Dictionary,command: Variant) -> String:
    if not command is Dictionary: return "command"
    var op: String=str(command.get("op",""))
    var id: String=str(command.get("id",""))
    var index: int=index_of(next,id)
    match op:
        "add_piece","duplicate_piece":
            if not valid_id(id) or index>=0: return "piece_id"
            var used: Dictionary={}
            for p in next["pieces"]: used[int(p["slot"])]=true
            var slot: int=-1
            for i in range(LIMIT):
                if not used.has(i): slot=i; break
            if slot<0: return "piece_budget"
            var p: Dictionary=piece(id,slot)
            if op=="duplicate_piece":
                var original: int=index_of(next,str(command.get("source","")))
                if original<0: return "source"
                p=next["pieces"][original].duplicate(true); p["id"]=id; p["slot"]=slot
            var values: Variant=command.get("values",{})
            if not values is Dictionary: return "values"
            for field in values:
                if not p.has(field) or field in ["id","slot"]: return "piece_field"
                p[field]=values[field]
            next["pieces"].append(p)
        "update_piece":
            if index<0 or not command.get("values") is Dictionary: return "piece"
            for field in command["values"]:
                if not next["pieces"][index].has(field) or field in ["id","slot"]: return "piece_field"
                next["pieces"][index][field]=command["values"][field]
        "remove_piece":
            if index<0: return "piece"
            var removed: Dictionary={id:true}
            for pass_index in range(LIMIT):
                for p in next["pieces"]:
                    if removed.has(p["parent"]): removed[p["id"]]=true
            var retained: Array=[]
            for p in next["pieces"]:
                if not removed.has(p["id"]): retained.append(p)
            next["pieces"]=retained
            for old_id in removed: next["tracks"].erase(old_id)
        "set_key":
            if index<0 or not numeric(command.get("time")) or not numeric(command.get("angle_deg")): return "keyframe"
            var keys: Array=next["tracks"].get(id,[]).duplicate(true)
            var time_value: float=float(command["time"])
            for i in range(keys.size()-1,-1,-1):
                if absf(float(keys[i][0])-time_value)<.00000001: keys.remove_at(i)
            keys.append([time_value,float(command["angle_deg"])]); keys.sort_custom(func(a: Array,b: Array): return a[0]<b[0])
            next["tracks"][id]=keys
        "set_track":
            if index<0 or not command.get("keys") is Array: return "track"
            next["tracks"][id]=command["keys"]
        "set_light":
            if not numeric(command.get("index")) or float(command["index"])!=floorf(float(command["index"])) or int(command["index"])<0 or int(command["index"])>=next["lights"].size() or not command.get("values") is Dictionary: return "light"
            for field in command["values"]:
                if field not in ["position","power_rgb","radius"]: return "light_field"
                next["lights"][int(command["index"])][field]=command["values"][field]
        "set_material":
            var name: String=str(command.get("name",""))
            if not next["materials"].has(name) or not command.get("values") is Dictionary: return "material"
            for field in command["values"]:
                if field not in ["tint_linear","roughness","metallic","emission","absorption_code"]: return "material_field"
                next["materials"][name][field]=command["values"][field]
        "set_camera":
            if not command.get("values") is Dictionary: return "camera"
            for field in command["values"]:
                if not next["camera"].has(field): return "camera_field"
                next["camera"][field]=command["values"][field]
        "set_settings":
            if not command.get("values") is Dictionary: return "settings"
            for field in command["values"]:
                if not next["settings"].has(field): return "settings_field"
                next["settings"][field]=command["values"][field]
        "set_time": next["time"]=command.get("value"); next["playing"]=false
        "set_playing": next["playing"]=command.get("value")
        _: return "unknown_command"
    return ""

func replace(candidate: Variant) -> Dictionary:
    var error: String=validate(candidate)
    if error!="": return {"ok":false,"error":error}
    _undo.append(state.duplicate(true)); if _undo.size()>64: _undo.pop_front()
    _redo.clear()
    state=candidate.duplicate(true); revision+=1
    return {"ok":true,"revision":revision}

static func track_angle(keys: Array,time_value: float,fallback: float) -> float:
    if keys.is_empty(): return fallback
    if time_value<=float(keys[0][0]): return float(keys[0][1])
    for i in range(1,keys.size()):
        if time_value<=float(keys[i][0]):
            var t: float=(time_value-float(keys[i-1][0]))/(float(keys[i][0])-float(keys[i-1][0]))
            return lerpf(float(keys[i-1][1]),float(keys[i][1]),smoothstep(0,1,t))
    return float(keys[-1][1])

static func evaluate(candidate: Dictionary,time_value: float=-1) -> Dictionary:
    var time_now: float=fposmod(float(candidate["time"]) if time_value<0 else time_value,float(candidate["duration"]))
    var remaining: Array=candidate["pieces"].duplicate()
    var joints: Dictionary={}; var poses: Dictionary={}
    for pass_index in range(LIMIT):
        for index in range(remaining.size()-1,-1,-1):
            var p: Dictionary=remaining[index]
            if p["parent"]!="" and not joints.has(p["parent"]): continue
            var angle: float=track_angle(candidate["tracks"].get(p["id"],[]),time_now,float(p["angle_deg"]))
            var basis: Basis=Basis.from_euler(vec(p["rotation_deg"])*PI/180)*Basis(vec(p["axis"]),deg_to_rad(angle))
            var local:=Transform3D(basis,vec(p["position"]))
            var joint: Transform3D=local if p["parent"]=="" else joints[p["parent"]]*local
            joints[p["id"]]=joint
            poses[p["id"]]=joint*Transform3D(Basis.IDENTITY.scaled_local(vec(p["scale"])),vec(p["offset"]))
            remaining.remove_at(index)
        if remaining.is_empty(): break
    return {"joints":joints,"poses":poses,"time":time_now}

func save_document(path: String="user://workshop/robot.lie.json") -> Dictionary:
    if not path.begins_with("user://workshop/") or ".." in path or not path.ends_with(".lie.json"): return {"ok":false,"error":"save_path"}
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
    if file==null: return {"ok":false,"error":"write"}
    file.store_string(JSON.stringify(state,"  ",true,true)); file.close()
    var error: int=DirAccess.rename_absolute(path+".tmp",path)
    return {"ok":error==OK,"path":path,"error":error}

func load_document(path: String="user://workshop/robot.lie.json") -> Dictionary:
    if not path.begins_with("user://workshop/") or ".." in path or not path.ends_with(".lie.json"): return {"ok":false,"error":"load_path"}
    if not FileAccess.file_exists(path): return {"ok":false,"error":"missing_file"}
    return replace(JSON.parse_string(FileAccess.get_file_as_string(path)))
