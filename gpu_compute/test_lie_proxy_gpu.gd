extends "res://test_lie_hq_construction.gd"
func run() -> void:
    var lab=load("res://lie_construction_proxy_lab.tscn").instantiate();lab.output_resolution=256;root.add_child(lab);await settle(20)
    check(lab.metrics.get("configured",false),"proxy lab configures original renderer and field")
    var merged: Dictionary=await capture(lab);var field_solves: int=lab.transport.frame_count;var geometry: int=lab.geometry_builds
    check(lab.proxy_world.graph.body_count==13 and lab._proxy_button.is_visible_in_tree(),"thirteen invisible wall volumes and visible experiment action")
    lab.command({"op":"set_values","values":{"proxy_grouped":false}});var pieces: Dictionary=await capture(lab)
    check(lab.proxy_world.graph.body_count==781,"per-piece physical baseline")
    check(merged.color==pieces.color and merged.depth==pieces.depth and merged.shadow==pieces.shadow,"physics grouping preserves exact appearance, depth and shadow")
    check(lab.geometry_builds==geometry and lab.transport.frame_count==field_solves and pieces.frames==merged.frames,"grouping preserves geometry, field solve and render cache")
    lab.command({"op":"set_values","values":{"reverse_banks":true}});var cold: Dictionary=await capture(lab)
    check(difference(cold.color,merged.color)==0. and cold.depth==merged.depth,"independently rerasterized image is identical")
    var revision: int=lab.revision
    for bad in [{"proxy_grouped":1},{"camera_guard":1},{"proxy_grouped":true,"zoom":false}]:check(not lab.command({"op":"set_values","values":bad}).ok and lab.revision==revision,"invalid proxy transaction is atomic")
    var backup: Dictionary=lab.state.duplicate();var readback: Dictionary=lab.effect.readback()
    await lab.run_proxy_comparison(32)
    check(lab._latest.complete and lab._latest.restored and lab.state==backup,"physical A/B experiment completes and restores controls")
    check(lab._latest.physics.size()==2 and lab._latest.physics[0].contract.passed and lab._latest.physics[1].contract.passed,"both physical contracts measured in actual engine")
    check(lab._latest.appearance_reused and lab._latest.field_reused,"experiment reuses render and lighting")
    check(lab.effect.readback().color==readback.color,"physical benchmark does not read GPU images")
    var copied: Variant=JSON.parse_string(DisplayServer.clipboard_get())
    check(copied is Dictionary and copied.kind=="invisible_wall_proxy_A_B" and copied.complete,"completed proxy report automatically copied")
    lab.command({"op":"set_values","values":{"proxy_grouped":true,"camera_guard":true}})
    var p: Dictionary=lab._probe_points();lab._previous_camera=p.solid+Vector3(0,0,.4);lab._have_previous_camera=true
    # A validated camera command asks for the opposite side; the camera hook
    # must limit the path before publishing parameters to the LIE consumer.
    lab.command({"op":"set_values","values":{"yaw":180.,"elevation":0.,"focus_x":p.solid.x-float(lab.recipe.target[0]),"focus_y":p.solid.y-float(lab.recipe.target[1])}})
    var stopped: Dictionary=await capture(lab)
    check(lab.metrics.camera_collision.blocked and stopped.frames>cold.frames,"validated camera commands feed collision-limited pose to renderer")
    lab.command({"op":"set_values","values":{"camera_guard":false,"yaw":-25.,"elevation":22.,"focus_x":0.,"focus_y":0.,"reverse_banks":false}});await capture(lab)
    await lab._sync_metrics();await settle(12)
    root.get_texture().get_image().save_png("res://construction-proxy-ui.png")
    var file:=FileAccess.open("res://construction-proxy-native.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"report":copied,"rgba_exact":merged.color==pieces.color,"depth_exact":merged.depth==pieces.depth,"physical_android_tested":false},"  "));file.close()
    lab.queue_free();await settle(20);print("PROXY GPU ","FAIL" if failed else "PASS"," ",checks);quit(1 if failed else 0)
