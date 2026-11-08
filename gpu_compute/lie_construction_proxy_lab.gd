extends "res://lie_construction_mobile_lab.gd"
const Proxy=preload("res://lie_construction_proxy.gd")
const Stats=preload("res://lie_mobile_diagnostics.gd")
const Hierarchy=preload("res://lie_construction_hierarchy.gd")
var proxy_world: Node3D
var _proxy_key: String=""
var _previous_camera:=Vector3.ZERO
var _have_previous_camera: bool=false
var _camera_result: Dictionary={}
var _proxy_status: Label
var _proxy_button: Button
var _visibility_button: Button
var _clusters_button: Button
var _hierarchy: Dictionary={}
var _hierarchy_key: String=""
var _visibility: Dictionary={}
func _init() -> void:
    state.proxy_grouped=true;state.camera_guard=false;state.camera_culling=true;state.cluster_culling=true
func _extra_boolean_controls() -> Array:return ["proxy_grouped","camera_guard","camera_culling","cluster_culling"]
func _cluster_selection_enabled() -> bool:return state.cluster_culling
func _build_ui() -> void:
    super._build_ui()
    var parent: Node=_benchmark_button.get_parent().get_parent()
    var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);parent.add_child(row);parent.move_child(row,2)
    _proxy_button=_button(row,"Probar muros y copiar",run_proxy_comparison);_proxy_button.custom_minimum_size.y=52;_proxy_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    _visibility_button=_button(row,"Probar jerarquía y copiar",func():run_visibility_comparison());_visibility_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    _clusters_button=_button(parent,"Probar núcleo y copiar",func():run_cluster_comparison());parent.move_child(_clusters_button,3)
    var toggles:=HFlowContainer.new();parent.add_child(toggles);parent.move_child(toggles,3)
    for key in ["proxy_grouped","camera_guard","camera_culling","cluster_culling"]:
        var toggle:=CheckBox.new();toggle.text={"proxy_grouped":"Unir volúmenes","camera_guard":"Cámara con colisión","camera_culling":"Selección visible","cluster_culling":"Descartar caras de espaldas"}[key];toggle.button_pressed=state[key];toggle.toggled.connect(func(v: bool):command({"op":"set_values","values":{key:v}}));controls[key]=toggle;toggles.add_child(toggle)
    _proxy_status=_label(parent,"Preparando volúmenes invisibles…",16);parent.move_child(_proxy_status,4);_proxy_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
func _refresh_quick_actions() -> void:
    super._refresh_quick_actions()
    for button in [_proxy_button,_visibility_button,_clusters_button]:
        if button!=null:button.disabled=busy or not metrics.get("configured",false) or effect==null or not effect.gpu_ready
func _before_camera_packet(target: Vector3) -> void:
    if proxy_world==null:proxy_world=Proxy.new();proxy_world.name="InvisibleWallPhysics";add_child(proxy_world)
    var key: String=_geometry_key+":"+str(state.proxy_grouped)
    if key!=_proxy_key:
        var catalogs: Dictionary={}
        for bank in effect.banks:catalogs[bank.name]=bank.catalog
        var graph: Dictionary=Proxy.build(recipe,_geometry.entries,catalogs,state.proxy_grouped)
        if not proxy_world.configure(graph):metrics={"error":"proxy_geometry"};return
        # A new physical assembly has no continuous camera trajectory from the
        # previous scene. Group changes alone retain the old camera position.
        if _proxy_key.get_slice(":",0)!=_geometry_key:_have_previous_camera=false
        _proxy_key=key
    var proposed: Vector3=camera.position
    if state.camera_guard and not _have_previous_camera:_previous_camera=proposed;_have_previous_camera=true
    _camera_result={"blocked":false,"initial_overlap":false,"position":proposed}
    if state.camera_guard and _have_previous_camera:
        _camera_result=Proxy.camera_move(_previous_camera,proposed,proxy_world.graph.volumes)
        camera.position=_camera_result.position
        if camera.position.distance_squared_to(target)>1e-10:camera.look_at(target,Vector3.FORWARD if absf((camera.position-target).normalized().y)>.9999 else Vector3.UP)
    _previous_camera=camera.position;_have_previous_camera=true
    if _proxy_status!=null:
        var p: Dictionary=proxy_world.metrics()
        _proxy_status.text="Física invisible: %d piezas → %d cajas · Cámara: %s" % [p.source_pieces,p.physics_shapes,"recuperada" if _camera_result.get("recovered",false) else "solapamiento" if _camera_result.initial_overlap else "deslizando" if _camera_result.get("slid",false) else "frenada" if _camera_result.blocked else "libre"]
func _camera_selection() -> PackedByteArray:
    if _hierarchy_key!=_geometry_key:
        var leaves: Array=[];var jobs: PackedInt32Array=_geometry.jobs.to_int32_array();var instances: PackedByteArray=_geometry.instances
        for j in range(jobs.size()/4):
            var at: int=jobs[j*4+2]*96;var bank: int=int(instances.decode_float(at+68))
            var page: Dictionary=effect.banks[bank].index.entries[str(jobs[j*4])+":"+str(jobs[j*4+1])]
            var lo:=Vector3(page.low[0],page.low[1],page.low[2]);var hi:=Vector3(page.high[0],page.high[1],page.high[2])
            var basis:=Basis(Vector3(instances.decode_float(at),instances.decode_float(at+4),instances.decode_float(at+8)),Vector3(instances.decode_float(at+16),instances.decode_float(at+20),instances.decode_float(at+24)),Vector3(instances.decode_float(at+32),instances.decode_float(at+36),instances.decode_float(at+40)))
            var origin:=Vector3(instances.decode_float(at+48),instances.decode_float(at+52),instances.decode_float(at+56))
            leaves.append({"id":_geometry.entries[j].id,"bounds":Proxy.world_bounds(Transform3D(basis,origin+basis*(lo+hi)*.5),hi-lo),"guard_m":.0001+.000002*maxf(basis.x.length(),maxf(basis.y.length(),basis.z.length()))})
        _hierarchy=Hierarchy.build(leaves);_hierarchy_key=_geometry_key
    _visibility=Hierarchy.select(_hierarchy,camera.transform,camera.fov,effect.render_size) if state.camera_culling else {"mask":PackedByteArray(),"selected_jobs":_hierarchy.leaves,"total_jobs":_hierarchy.leaves,"visited_nodes":0,"rejected_nodes":0}
    if _proxy_status!=null:_proxy_status.text+=" · Piezas en cámara: %d/%d" % [_visibility.selected_jobs,_visibility.total_jobs]
    return _visibility.mask
func update_scene() -> void:
    super.update_scene()
    if proxy_world!=null:metrics.proxy=proxy_world.metrics();metrics.camera_collision=_camera_result.duplicate();metrics.visibility={"enabled":state.camera_culling,"selected_jobs":_visibility.get("selected_jobs",0),"total_jobs":_visibility.get("total_jobs",0),"visited_nodes":_visibility.get("visited_nodes",0),"rejected_nodes":_visibility.get("rejected_nodes",0),"nodes":_hierarchy.get("nodes",0)}
func _physics_settle() -> void:
    for i in range(4):await get_tree().physics_frame
    await get_tree().process_frame
func _probe_points() -> Dictionary:
    var opening: Array=recipe.opening.center
    var window:=Vector3(opening[0],opening[1],opening[2])
    var solid: Vector3=proxy_world.graph.attachments[0].pose.origin
    return {"window":window,"solid":solid}
func _physical_contract() -> Dictionary:
    var points: Dictionary=_probe_points();var travel:=Vector3(0,0,.4)
    var wall: Dictionary=proxy_world.ray(points.solid+travel,points.solid-travel)
    var window: Dictionary=proxy_world.ray(points.window+travel,points.window-travel)
    var wall_motion: PackedFloat32Array=proxy_world.sphere_motion(points.solid+travel,points.solid-travel)
    var window_motion: PackedFloat32Array=proxy_world.sphere_motion(points.window+travel,points.window-travel)
    var camera_wall: Dictionary=Proxy.camera_sweep(points.solid+travel,points.solid-travel,proxy_world.graph.volumes)
    var camera_window: Dictionary=Proxy.camera_sweep(points.window+travel,points.window-travel,proxy_world.graph.volumes)
    var no_overlap: bool=not camera_wall.initial_overlap and not camera_window.initial_overlap
    return {"wall_blocks_ray":not wall.is_empty(),"window_passes_ray":window.is_empty(),"wall_sphere_motion":Array(wall_motion),"window_sphere_motion":Array(window_motion),"camera_wall_blocked":camera_wall.blocked,"camera_window_clear":not camera_window.blocked,"camera_queries_start_clear":no_overlap,"camera_wall_fraction":camera_wall.fraction,"passed":not wall.is_empty() and window.is_empty() and wall_motion[0]<1. and window_motion[0]==1. and camera_wall.blocked and not camera_window.blocked and no_overlap}
func _query_benchmark(count: int) -> Dictionary:
    var samples: Array=[];var points: Dictionary=_probe_points();var hits: int=0
    var started: int=Time.get_ticks_usec()
    for i in range(count):
        var point: Vector3=points.solid if i%2==0 else points.window
        var t: int=Time.get_ticks_usec();var result: Dictionary=proxy_world.ray(point+Vector3(0,0,.4),point-Vector3(0,0,.4));samples.append(float(Time.get_ticks_usec()-t)/1000.)
        if not result.is_empty():hits+=1
    return {"queries":count,"hits":hits,"elapsed_ms":float(Time.get_ticks_usec()-started)/1000.,"ray_cpu_ms":Stats.percentiles(samples),"scope":"Actual PhysicsDirectSpaceState3D ray calls after physics-frame synchronization; CPU wall time only, not GPU rendering or FPS."}
func run_proxy_comparison(queries: int=512) -> void:
    if busy or not metrics.get("configured",false) or queries<2 or queries>4096:return
    busy=true;cancelled=false;_lock_controls(true);var backup: Dictionary=state.duplicate();var saved_camera: Vector3=camera.position;_latest=_new_report("invisible_wall_proxy_A_B");_latest.physics=[]
    if not _set_values({"mode":"corner","seed":2102,"proxy_grouped":false,"camera_guard":false}):_latest.error="proxy_configuration";_finish(backup);return
    _latest.warm_up.append(await _warm_up())
    var initial: Dictionary=await _sync_metrics()
    for grouped in [false,true]:
        if cancelled:break
        _message="Probando "+("muros unidos" if grouped else "cajas por pieza")
        if not _set_values({"proxy_grouped":grouped}):_latest.error="proxy_switch";break
        await _physics_settle()
        if cancelled:break
        var contract: Dictionary=_physical_contract();var timing: Dictionary=_query_benchmark(queries);var resources: Dictionary=await _sync_metrics()
        _latest.physics.append({"grouped":grouped,"proxy":proxy_world.metrics(),"contract":contract,"timing":timing,"resources":resources})
        if not contract.passed:_latest.error="proxy_physical_contract";break
    var final_resources: Dictionary=await _sync_metrics()
    _latest.appearance_reused=int(initial.get("frames",-1))==int(final_resources.get("frames",-2))
    _latest.field_reused=initial.get("field",{}).get("solve",-1)==final_resources.get("field",{}).get("solve",-2)
    _latest.sample_invocations=final_resources.get("samples",0)
    _latest.scope="Invisible physics/camera experiment. Grouped wall envelopes approximate joints and relief, preserve the declared window, and do not render triangles. Capture banks, light-field ownership, LOD and render sample jobs are unchanged. No GPU image readbacks are requested by this benchmark. No rendering speedup is inferred from fewer colliders."
    _previous_camera=saved_camera;_have_previous_camera=true
    _finish(backup)

func run_visibility_comparison(events: int=24) -> void:
    if busy or not metrics.get("configured",false) or not effect.gpu_ready or events<2 or events>120:return
    busy=true;cancelled=false;_lock_controls(true);var backup: Dictionary=state.duplicate();var saved_camera: Vector3=camera.position;_latest=_new_report("hierarchical_camera_selection_A_B")
    for close_view in [false,true]:
        for enabled_value in [false,true]:
            if cancelled:break
            if not _set_values({"mode":"corner","seed":2102,"camera_guard":false,"camera_culling":enabled_value,"cluster_culling":false,"yaw":0.,"elevation":0.,"zoom":.25 if close_view else 1.,"focus_x":.6 if close_view else 0.,"focus_y":0.,"reverse_banks":false}):_latest.error="visibility_configuration";break
            _latest.warm_up.append(await _warm_up());var before: Dictionary=await _block_start()
            for i in range(events):
                if cancelled:break
                _message="Jerarquía %s · %s · %d/%d" % ["activa" if enabled_value else "referencia","cerca" if close_view else "conjunto",i+1,events]
                var previous: int=effect.frame_count;var started: int=Time.get_ticks_usec()
                if not _set_values({"yaw":sin(float(i+1)*.37)*18.}):_latest.error="visibility_camera";break
                meter.add_command(float(Time.get_ticks_usec()-started)/1000.)
                if not await _wait_image(previous):
                    if not cancelled:_latest.error="image_dispatch_timeout"
                    break
            var block: Dictionary=await _block_end(before,"camera");block.selection_enabled=enabled_value;block.close_view=close_view;block.hierarchy=metrics.visibility.duplicate();_latest.blocks.append(block);_persist_report()
            if not _latest.error.is_empty():break
        if cancelled or not _latest.error.is_empty():break
    _latest.selection_scope="Camera frustum only, over immutable source-page bounds. Full jobs retained for shadow casters and light field. Whole-instance sample jobs are skipped without changing captures, LOD, source ownership or resolution. Paired deterministic camera paths; compare within this device, never infer Android FPS from software Vulkan."
    _previous_camera=saved_camera;_have_previous_camera=true;_finish(backup)

func run_cluster_comparison(events: int=12) -> void:
    if busy or not metrics.get("configured",false) or not effect.gpu_ready or events<2 or events>120:return
    busy=true;cancelled=false;_lock_controls(true);var backup: Dictionary=state.duplicate();var saved_camera: Vector3=camera.position;_latest=_new_report("native_backface_clusters_A_B_B_A")
    for close_view in [false,true]:
        for enabled_value in [false,true,true,false]:
            if cancelled:break
            if not _set_values({"mode":"corner","seed":2102,"camera_guard":false,"camera_culling":true,"cluster_culling":enabled_value,"yaw":0.,"elevation":0.,"zoom":.25 if close_view else 1.,"focus_x":.6 if close_view else 0.,"focus_y":0.,"reverse_banks":false}):_latest.error="cluster_configuration";break
            _latest.warm_up.append(await _warm_up());var before: Dictionary=await _block_start()
            if enabled_value and not before.resources.get("camera_plan",{}).get("enabled",false):_latest.error="native_planner_unavailable";break
            for i in range(events):
                if cancelled:break
                _message="Núcleo %s · %s · %d/%d" % ["activo" if enabled_value else "referencia","cerca" if close_view else "conjunto",i+1,events]
                var previous: int=effect.frame_count;var started: int=Time.get_ticks_usec()
                if not _set_values({"yaw":sin(float(i+1)*.37)*18.}):_latest.error="cluster_camera";break
                meter.add_command(float(Time.get_ticks_usec()-started)/1000.)
                if not await _wait_image(previous):
                    if not cancelled:_latest.error="image_dispatch_timeout"
                    break
            var block: Dictionary=await _block_end(before,"camera");block.clusters_enabled=enabled_value;block.close_view=close_view;_latest.blocks.append(block);_persist_report()
            if not _latest.error.is_empty():break
        if cancelled or not _latest.error.is_empty():break
    _latest.selection_scope="Native CPU geometric backface intervals plus camera frustum. A/B/B/A order, same deterministic paths and quality. Not optical occlusion. Full sources, global owner indices, shadows and light-field owners preserved. Native planning CPU and GPU pass times have separate scopes."
    _previous_camera=saved_camera;_have_previous_camera=true;_finish(backup)
