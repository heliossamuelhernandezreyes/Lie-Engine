extends SceneTree
## godot --headless --path gpu_compute --script res://workshop/lie_agent_cli.gd -- input.json output.json
const Doc=preload("res://workshop/lie_document.gd")
const Collision=preload("res://workshop/lie_collision.gd")
func _initialize() -> void:
    var args: PackedStringArray=OS.get_cmdline_user_args()
    if args.size()!=2: push_error("Expected input.json output.json"); quit(2); return
    var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
    if not parsed is Dictionary: push_error("Invalid request JSON"); quit(2); return
    var doc:=Doc.new()
    if parsed.has("document"):
        var loaded: Dictionary=doc.replace(parsed["document"])
        if not loaded["ok"]: push_error(JSON.stringify(loaded)); quit(2); return
    var results: Array=[]
    for command in parsed.get("commands",[]): results.append(doc.dispatch(command))
    var response: Dictionary={"results":results,"snapshot":doc.snapshot(),"collisions":Collision.diagnostics(doc.state,Doc.evaluate(doc.state))}
    var file:=FileAccess.open(args[1],FileAccess.WRITE)
    if file==null: push_error("Cannot write response"); quit(2); return
    file.store_string(JSON.stringify(response,"  ",true,true))
    print("LIE_AGENT_RESPONSE ",JSON.stringify({"results":results.map(func(r: Dictionary): return {"ok":r.get("ok",false),"error":r.get("error",""),"revision":r.get("revision",doc.revision)}),"piece_count":doc.state["pieces"].size(),"collision_warnings":response["collisions"].size()})); quit(0)
