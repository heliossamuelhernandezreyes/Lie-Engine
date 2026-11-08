extends SceneTree
const Lab=preload("res://lie_construction_proxy_lab.gd")
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func write_packet(name: String,data: PackedByteArray) -> String:
    var path: String="native-plan-"+name+".bin";var file:=FileAccess.open("res://"+path,FileAccess.WRITE);file.store_buffer(data);file.close();return path
func run() -> void:
    if not ClassDB.class_exists("LieVisibilityPlanner"):printerr("Native planner missing");quit(1);return
    var native: Object=ClassDB.instantiate("LieVisibilityPlanner")
    var lab=Lab.new();lab.output_resolution=256;root.add_child(lab)
    for i in range(4):await process_frame
    var cases: Array=[]
    for values in [{"mode":"corner","yaw":-25.,"elevation":22.},{"mode":"corner","yaw":155.,"elevation":-10.},{"mode":"door","yaw":15.,"door_angle":75.}]:
        if not lab.command({"op":"set_values","values":values}).ok or not lab.metrics.get("configured",false):failed=true;break
        var pending: Dictionary=lab.effect._pending
        var result: Dictionary=native.select_clusters(pending.cluster_plan,pending.parameters,pending.instances,pending.jobs,PackedByteArray(),pending.cluster_indices)
        if not result.get("ok",false):printerr(result);failed=true;break
        var prefix: String=str(cases.size());var packets: Dictionary={}
        for key in ["cluster_plan","cluster_indices","parameters","instances","jobs"]:packets[key]=write_packet(prefix+"-"+key,pending[key])
        var ranges: Array=[]
        for row in result.banks:ranges.append({"bank":row.bank,"work":row.work,"jobs":row.jobs,"file":write_packet(prefix+"-bank-"+str(row.bank),row.data)})
        result.erase("banks");cases.append({"state":lab.state.duplicate(),"packets":packets,"banks":ranges,"result":result})
    var file:=FileAccess.open("res://native-visibility-planning.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failed":failed,"bank_names":lab.effect.manifest.banks,"cases":cases},"  "));file.close()
    lab.queue_free();for i in range(8):await process_frame
    print("NATIVE VISIBILITY HEADLESS ","FAIL" if failed else "PASS"," ",cases.size());quit(1 if failed else 0)
