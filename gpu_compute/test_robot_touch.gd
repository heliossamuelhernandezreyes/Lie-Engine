extends SceneTree
## Actual two-finger input, shared command validation and collision locomotion.
const Lab=preload("res://lie_robot_world_lab.gd")
var lab: Node3D
var hud: Control
var checks: int=0
var failed: bool=false
var gpu: bool=false

func _initialize() -> void:call_deferred("run")
func expect(value: bool,label: String) -> void:
    checks+=1
    if not value:failed=true;push_error("R2 TOUCH: "+label)
func finger(index: int,down: bool,point: Vector2) -> void:
    var event:=InputEventScreenTouch.new();event.index=index;event.pressed=down;event.position=point;root.push_input(event,true)
func drag(index: int,point: Vector2,relative: Vector2) -> void:
    var event:=InputEventScreenDrag.new();event.index=index;event.position=point;event.relative=relative;root.push_input(event,true)

func gui_tap(text: String,index: int) -> void:
    for node in hud.get_children():
        if node is HBoxContainer:
            for button in node.get_children():
                if button is Button and button.text==text:
                    var point: Vector2=button.get_global_rect().get_center()
                    finger(index,true,point);finger(index,false,point);return
    expect(false,"GUI button exists: "+text)

func run() -> void:
    gpu="--gpu" in OS.get_cmdline_user_args()
    root.size=Vector2i(1280,720)
    lab=Lab.new();lab.touch_mode=true;root.add_child(lab)
    for i in range(3):await physics_frame
    hud=lab.picture.get_parent()
    expect(lab.effect.capture_loaded,"Complete attributed bank restored")
    expect(lab.effect.output_size==512,"Touch scene uses 512 output / 1024 reconstruction")
    expect(hud.size.x>=1280 and hud.size.y>=720,"Viewport fills landscape HUD")
    var initial: Vector3=Lab.Rig.vector(lab.state["motion"]["position"])
    var center: Vector2=hud.move_center
    finger(2,true,center+Vector2(0,-hud.radius))
    expect(hud.move_finger==2 and lab.state["move"][1]==1 and lab.state["playing"],"Left finger reaches existing command path")
    var yaw: float=lab.state["camera_yaw"]
    finger(7,true,Vector2(1000,350));drag(7,Vector2(1060,370),Vector2(60,20))
    expect(hud.look_finger==7 and lab.state["camera_yaw"]!=yaw and lab.state["move"][1]==1,"Independent right finger orbits during locomotion")
    gui_tap("Techo",9)
    expect(lab.state["roof"] and hud.move_finger==2 and hud.look_finger==7,"Native GUI touch button works with two fingers held, without mouse emulation")
    gui_tap("Techo",9)
    for i in range(70):await physics_frame
    expect(Lab.Rig.vector(lab.state["motion"]["position"]).distance_to(initial)>.5,"Touch joystick causes real CharacterBody movement")
    finger(7,false,Vector2(1060,370))
    expect(hud.look_finger==-1 and hud.move_finger==2 and lab.state["move"][1]==1,"Camera release preserves held joystick")
    finger(2,false,center)
    expect(hud.move_finger==-1 and lab.state["move"]==[0,0] and lab.state["turn"]==0,"Joystick release stops movement input")
    for i in range(20):await physics_frame
    expect(lab.state["motion"]["speed"]<.005,"Acceleration settles to standstill")
    finger(3,true,center+Vector2(hud.radius,0));var heading: float=lab.state["motion"]["heading"]
    for i in range(15):await physics_frame
    expect(lab.state["motion"]["heading"]!=heading,"Joystick horizontal movement turns the robot")
    hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    expect(hud.move_finger==-1 and hud.look_finger==-1 and not lab.state["playing"] and lab.state["move"]==[0,0],"Losing focus clears touch and pauses")
    finger(8,true,Vector2(40,45));expect(hud.move_finger==-1 and hud.look_finger==-1,"Top controls remain available to GUI");finger(8,false,Vector2(40,45))
    gui_tap("Techo",4);expect(lab.state["roof"] and lab._environment.size()==83,"Roof button updates collision and renderer")
    gui_tap("Techo",4);gui_tap("Pinzas",4);expect(lab.state["grip"]==1,"Pincher button uses semantic controls")
    hud._view();expect(lab.state["view"]=="overview","House inspection view")
    hud._view();hud._reset();expect(Lab.Rig.vector(lab.state["motion"]["position"]).is_equal_approx(initial),"Entrance reset restores real actor")
    var device: String="not tested"
    if gpu:
        for i in range(90):
            await process_frame
            if lab.effect.gpu_ready and lab._connected and lab.effect.frame_count>0:break
        expect(lab.effect.gpu_ready and lab._connected and lab.effect.frame_count>0,"Actual Mobile Vulkan compositor draws the touch scene")
        var paired: Array=[]
        for i in range(10):
            lab.command({"op":"set_values","values":{"camera_yaw":lab.state["camera_yaw"]+.05}})
            await process_frame
            var perf: Dictionary=lab.effect.performance_snapshot()
            var viewport_ms: float=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
            if perf.has("lie_gpu_ns") and viewport_ms>0:paired.append({"lie_gpu_ms":perf["lie_gpu_ns"]/1000000.0,"viewport_gpu_ms":viewport_ms})
        expect(not paired.is_empty(),"Real Vulkan timestamp and whole-viewport GPU metrics available")
        hud.diagnostics.sample(lab.effect,root)
        var measured: Dictionary=hud.diagnostics.latest
        expect(measured["gpu_lie_samples"]>0 and measured["gpu_lie_ms_last"]>0 and measured["gpu_frame_ms"]>0,"Measured GPU durations; no CPU substitution")
        expect(measured["gpu_rd_memory_bytes"]>=measured["gpu_lie_reserved_bytes"] and measured["gpu_lie_reserved_bytes"]>0,"Global GPU allocator covers tracked LIE buffers/images")
        expect(measured["rss_bytes"]>0 and measured["cpu_process_total_capacity_percent"]>=0,"Real process memory and CPU counters")
        expect(measured["gpu_total_utilization_percent"]==null,"Unavailable hardware utilization explicitly null")
        var panel_visible: bool=hud.metrics_panel.visible
        gui_tap("Datos",10);expect(hud.metrics_panel.visible!=panel_visible,"Metrics panel toggle uses native touch GUI");gui_tap("Datos",10)
        var copy_point: Vector2=hud.metrics_buttons[0].get_global_rect().get_center()
        finger(10,true,copy_point);finger(10,false,copy_point)
        var copied: Variant=JSON.parse_string(DisplayServer.clipboard_get())
        expect(copied is Dictionary and copied.get("app_version")=="0.1.2-r2-android-metrics" and copied.get("scopes") is Dictionary,"Native touch copies actual JSON report to clipboard")
        var metrics_file:=FileAccess.open("res://robot-touch-performance.json",FileAccess.WRITE);metrics_file.store_string(JSON.stringify({"live":measured,"concurrent_gpu_readouts":paired,"timing_scope":"Asynchronously collected LIE and viewport markers, potentially adjacent frames; same units, not frame-identical pairing."},"  "));metrics_file.close()
        lab.effect.request_readback()
        for i in range(8):await process_frame
        var read: Dictionary=lab.effect.readback()
        expect(not read.is_empty(),"Actual compute readback")
        if not read.is_empty():
            device=read["device"]
            var values: PackedFloat32Array=read["color"];var opaque: int=0;var varied: int=0
            for i in range(0,values.size(),4):
                expect(is_finite(values[i]) and is_finite(values[i+1]) and is_finite(values[i+2]),"Finite shaded output")
                if values[i+3]>.9:opaque+=1
                if values[i]>.12 or values[i+1]>.12 or values[i+2]>.12:varied+=1
            expect(opaque>200000 and varied>10000,"Visible robot/architecture pixels")
            expect(read["asset_uploads"]==1,"Combined bank uploaded once")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://robot-touch-preview.png")
    var result: Dictionary={"checks":checks,"failed":failed,"mobile_vulkan":gpu,"device":device,"physical_android_tested":false,"output_size":512,"bank_sha256":lab.effect.catalog["sha256"],"simultaneous_move_and_look":not failed,"allocation_bytes":lab.effect.allocation_bytes}
    var file:=FileAccess.open("res://robot-touch-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close();print("R2 TOUCH ",JSON.stringify(result))
    root.remove_child(lab);lab.free();await process_frame;quit(1 if failed else 0)
