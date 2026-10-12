extends Node
## One local file protocol survives laboratory navigation. No code evaluation.
const LABS={"workshop":"res://lie18_workshop.tscn","lie20":"res://lie20_human_lab.tscn","lie21":"res://lie21_human_lab.tscn","lie22":"res://lie22_modular_lab.tscn","lie23":"res://lie23_face_lab.tscn","lie24":"res://lie24_modular_face_lab.tscn","lie25":"res://lie25_anatomy_lab.tscn","lie26":"res://lie26_motion_lab.tscn","lie27":"res://lie27_regions_lab.tscn","lie28":"res://lie28_building_lab.tscn"}
var directory: String=""
var session_id: String=""
var target_override: Node
var lab_override: String=""
var busy: bool=false
var elapsed: float=0
var last_lab: String=""

func _ready() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args();var requested: String=""
    for i in range(args.size()-1):
        if args[i]=="--lie-agent-directory":requested=args[i+1]
    if DisplayServer.get_name()=="headless" and requested.is_empty():return
    initialize(requested if not requested.is_empty() else OS.get_user_data_dir()+"/agent/sessions/"+str(OS.get_process_id()))

func initialize(path: String) -> Dictionary:
    if not path.is_absolute_path():return {"ok":false,"error":"absolute_directory_required"}
    directory=path.simplify_path()
    if DirAccess.make_dir_recursive_absolute(directory)!=OK:directory="";return {"ok":false,"error":"directory_failed"}
    var existing: Variant=_read_json(directory+"/session.json")
    if existing is Dictionary and existing.get("pid")!=OS.get_process_id() and OS.is_process_running(int(existing.get("pid",-1))):
        directory="";return {"ok":false,"error":"directory_in_use"}
    session_id=str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
    publish_session();return {"ok":true,"directory":directory,"session_id":session_id}

func target() -> Node:
    return target_override if is_instance_valid(target_override) else get_tree().current_scene

func lab_id() -> String:
    if not lab_override.is_empty():return lab_override
    var lab: Node=target()
    if lab!=null:
        for id in LABS:
            if lab.scene_file_path==LABS[id]:return id
    return "unknown"

func current_revision() -> int:
    var lab: Node=target()
    if lab==null:return -1
    var revision: Variant=lab.get("revision")
    if revision is int:return revision
    var document: Variant=lab.get("document")
    return int(document.get("revision")) if document!=null else -1

func snapshot() -> Dictionary:
    var lab: Node=target();var data: Dictionary={}
    if lab!=null and lab.has_method("agent_snapshot"):data=lab.call("agent_snapshot").duplicate(true)
    elif lab!=null and lab.get("state") is Dictionary:data={"state":lab.get("state").duplicate(true),"revision":current_revision()}
    data.merge({"protocol":"lie-agent-session-v1","session_id":session_id,"lab":lab_id(),"directory":directory,"revision":current_revision(),"capabilities":capabilities()},true)
    var effect: Variant=lab.get("effect") if lab!=null else null
    data["runtime"]={"capture_loaded":bool(effect.get("capture_loaded")) if effect!=null else false,"gpu_ready":bool(effect.get("gpu_ready")) if effect!=null else false,"failure":str(effect.get("failure")) if effect!=null else "no renderer"}
    if effect!=null:
        data["runtime"]["allocation_bytes"]=effect.get("allocation_bytes")
        data["runtime"]["asset_uploads"]=effect.get("asset_uploads")
    return data

func capabilities() -> Dictionary:
    var lab: Node=target();var result: Dictionary={"operations":["snapshot","describe","open_lab","capture"],"laboratories":LABS.duplicate(),"shared_command_validation":lab!=null and lab.has_method("command"),"captures":["compositor","window"]}
    if lab!=null:
        var constants: Dictionary=lab.get_script().get_script_constant_map()
        result["limits"]=constants.get("LIMITS",{})
        result["face_keys"]=constants.get("FACE_KEYS",[])
        if constants.has("Rig"):result["pose_limits"]=constants["Rig"].get_script_constant_map().get("LIMITS",{})
        if lab_id()=="lie28":result["control_contract"]=lab.call("agent_snapshot").get("control_contract",{})
        if lab_id()=="lie27":
            result["control_contract"]={"booleans":["unlit","shadows","playing","show_regions","face_playing","brows"],"mask":{"integer":true,"range":[0,15],"layers":["skin","muscle","skeleton","internal"]},"face":{"keys":constants.get("FACE_KEYS",[]),"range":[0,1],"complete_dictionary":true},"eyes":{"rgb_keys":["sclera","iris","pupil"],"rgb_range":[0,1],"roughness_range":[.08,.6],"complete_dictionary":true},"enums":{"focus":["body","face","hand"],"mode":["manual","walk"]},"palette":{"shape":[4,3],"range":[0,1],"space":"linear"},"light_color":{"shape":[3],"range":[0,1]},"ik_chains":constants["Rig"].get_script_constant_map().get("CHAINS",{}).keys(),"ik_target":{"fields":["position","pole","enabled"],"position_shape":[3],"pole_shape":[3],"enabled":"optional boolean"}}
        if lab.get("state") is Dictionary:
            result["fields"]=lab.get("state").keys();result["operations"].append_array(["set_values","save_state","load_state"])
            if lab.get("state").has("pose"):result["operations"].append("set_pose")
        elif lab.has_method("agent_snapshot"):result["native_commands"]=lab.call("agent_snapshot").get("commands",[])
    return result

func _read_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):return null
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1024*1024:return null
    return JSON.parse_string(file.get_as_text())

func _write_json(path: String,value: Dictionary) -> bool:
    var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
    if file==null:return false
    file.store_string(JSON.stringify(value,"  ",true,true));file.close()
    return DirAccess.rename_absolute(path+".tmp",path)==OK

func publish_session() -> void:
    if directory.is_empty():return
    _write_json(directory+"/session.json",{"protocol":"lie-agent-session-v1","pid":OS.get_process_id(),"session_id":session_id,"directory":directory,"project":ProjectSettings.globalize_path("res://"),"lab":lab_id(),"capabilities":capabilities()})

func _filename(request: Dictionary,suffix: String,default_name: String) -> String:
    var name: Variant=request.get("filename",default_name)
    if not name is String or name.is_empty() or name!=name.get_file() or name.contains("..") or not name.ends_with(suffix):return ""
    return directory+"/"+name

func dispatch(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request_object"}
    if request.has("expected_session") and request["expected_session"]!=session_id:return {"ok":false,"error":"session_conflict"}
    if request.has("expected_lab") and request["expected_lab"]!=lab_id():return {"ok":false,"error":"lab_conflict"}
    if request.has("expected_revision") and request["expected_revision"]!=current_revision():return {"ok":false,"error":"revision_conflict","revision":current_revision()}
    var lab: Node=target();var op: String=str(request.get("op",""))
    if op in ["snapshot","describe"]:return {"ok":true,"revision":current_revision(),"snapshot":snapshot()}
    if op=="open_lab":
        var id: Variant=request.get("lab")
        if not id is String or not LABS.has(id):return {"ok":false,"error":"unknown_lab"}
        target_override=null;lab_override=""
        var error: Error=get_tree().change_scene_to_file(LABS[id])
        if error!=OK:return {"ok":false,"error":"scene_failed"}
        await get_tree().process_frame;await get_tree().process_frame
        session_id=str(OS.get_process_id())+"-"+str(Time.get_ticks_usec());publish_session()
        return {"ok":true,"lab":id,"revision":current_revision()}
    if lab==null or not lab.has_method("command"):return {"ok":false,"error":"lab_has_no_command_api"}
    if op in ["save_state","load_state"]:
        if directory.is_empty() or not lab.get("state") is Dictionary:return {"ok":false,"error":"state_storage_unavailable"}
        var path: String=_filename(request,".lie.json","state.lie.json")
        if path.is_empty():return {"ok":false,"error":"filename"}
        if op=="save_state":return {"ok":_write_json(path,{"schema":1,"lab":lab_id(),"state":lab.get("state").duplicate(true)}),"path":path,"revision":current_revision()}
        var loaded: Variant=_read_json(path)
        if not loaded is Dictionary or loaded.get("schema")!=1 or loaded.get("lab")!=lab_id() or not loaded.get("state") is Dictionary or loaded["state"].size()!=lab.get("state").size():return {"ok":false,"error":"state_contract"}
        var values: Dictionary=loaded["state"]
        for key in lab.get("state"):
            if not values.has(key):return {"ok":false,"error":"state_contract"}
        return lab.call("command",{"op":"set_values","values":values,"expected_revision":current_revision()})
    if op=="capture":
        var path: String=_filename(request,".png","capture.png")
        if path.is_empty():return {"ok":false,"error":"filename"}
        var effect: Variant=lab.get("effect")
        if effect==null or not effect.get("gpu_ready"):return {"ok":false,"error":"gpu_not_ready"}
        var kind: Variant=request.get("kind","compositor")
        if kind not in ["window","compositor"]:return {"ok":false,"error":"capture_kind"}
        for i in range(4):await get_tree().process_frame
        var image: Image
        if kind=="window":
            await RenderingServer.frame_post_draw;image=get_tree().root.get_texture().get_image()
        else:
            if not effect.has_method("request_readback"):return {"ok":false,"error":"readback_unavailable"}
            effect.call("request_readback")
            var data: Dictionary={}
            for i in range(100):
                await get_tree().process_frame;data=effect.call("readback")
                if not data.is_empty():break
            if data.is_empty() or not data.has("color"):return {"ok":false,"error":"readback_timeout"}
            var values: PackedFloat32Array=data["color"];var bytes:=PackedByteArray();bytes.resize(values.size())
            for i in range(values.size()):bytes[i]=clampi(roundi(values[i]*255),0,255)
            var size: int=int(data.get("output_size",effect.get("output_size")))
            image=Image.create_from_data(size,size,false,Image.FORMAT_RGBA8,bytes)
        # Publish only a complete PNG. Readers must not observe bytes while
        # the encoder is still writing or workspace synchronization is active.
        var error: Error=image.save_png(path+".tmp")
        if error==OK:error=DirAccess.rename_absolute(path+".tmp",path)
        return {"ok":error==OK,"path":path,"kind":kind,"revision":current_revision(),"width":image.get_width(),"height":image.get_height()}
    # Runtime and native document commands use the same path as desktop UI.
    return lab.call("command",request)

func _process(delta: float) -> void:
    if directory.is_empty() or busy:return
    elapsed+=delta
    if elapsed<.2:return
    elapsed=0
    if last_lab!=lab_id():last_lab=lab_id();publish_session()
    var path: String=directory+"/inbox.json"
    if not FileAccess.file_exists(path):return
    var envelope: Variant=_read_json(path);DirAccess.remove_absolute(path)
    var id: Variant=envelope.get("request_id") if envelope is Dictionary else null
    var request: Variant=envelope.get("request") if envelope is Dictionary else null
    busy=true;var result: Dictionary=await dispatch(request)
    _write_json(directory+"/outbox.json",{"request_id":id,"result":result,"snapshot":snapshot()});busy=false
