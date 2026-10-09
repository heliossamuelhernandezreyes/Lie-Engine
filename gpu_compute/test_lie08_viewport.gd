extends SceneTree
## CI screenshot-based acceptance of the actual Godot camera compositor.
## Fails if the viewport has no non-background LIE pixels or is invariant to orbit.
func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var lab: Node3D = load("res://lie08_lab.tscn").instantiate() as Node3D
    if lab == null:
        _fail("No LIE-08 scene")
        return
    get_root().add_child(lab)
    for i in range(16):
        await process_frame
    var effect: CompositorEffect = lab.get("effect")
    if not bool(effect.get("gpu_ready")):
        _fail("CompositorEffect never created a global Vulkan pipeline")
        return
    if int(effect.get("frame_count")) < 2:
        _fail("GPU compositor did not render multiple frames")
        return
    var first: Image = get_root().get_texture().get_image()
    if first == null or first.is_empty():
        _fail("No viewport screenshot")
        return
    var center: Color = first.get_pixel(first.get_width()/2,first.get_height()/2)
    var corner: Color = first.get_pixel(8,8)
    if center.b < corner.b + 0.08:
        _fail("No GPU-origin object visible at screen center: "+str(center)+" corner "+str(corner))
        return
    if first.save_png(ProjectSettings.globalize_path("res://lie-08-viewport-0.png")) != OK:
        _fail("Unable to write screenshot 0")
        return
    lab.set("yaw_degrees",35.0)
    lab.call("_move_camera")
    for i in range(20):
        await process_frame
    var second: Image = get_root().get_texture().get_image()
    if second.save_png(ProjectSettings.globalize_path("res://lie-08-viewport-35.png")) != OK:
        _fail("Unable to write screenshot 35")
        return
    var delta := 0.0
    for y in range(60,196,4):
        for x in range(60,196,4):
            var a: Color = first.get_pixel(x,y)
            var b: Color = second.get_pixel(x,y)
            delta += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
    if delta < 3.0:
        _fail("Orbit did not change captured GPU pixels; delta="+str(delta))
        return
    var covered_0: float = _disk_coverage(first,corner)
    var covered_35: float = _disk_coverage(second,second.get_pixel(8,8))
    if covered_0 < 0.80 or covered_35 < 0.80:
        _fail("Large reprojection holes: coverage0=%.3f coverage35=%.3f" % [covered_0,covered_35])
        return
    print("LIE-08 VIEWPORT PASS global_device=true composited=true screenshot=true orbit_changed=true delta=",delta," coverage0=",covered_0," coverage35=",covered_35)
    lab.queue_free()
    for i in range(4):
        await process_frame
    quit(0)

func _fail(reason: String) -> void:
    printerr("LIE-08 VIEWPORT FAIL: ",reason)
    quit(1)

func _disk_coverage(im: Image, background: Color) -> float:
    var present := 0
    var measured := 0
    var cx: int = im.get_width()/2
    var cy: int = im.get_height()/2
    for oy in range(-30,31,2):
        for ox in range(-30,31,2):
            if ox*ox+oy*oy > 900:
                continue
            measured += 1
            var c: Color = im.get_pixel(cx+ox,cy+oy)
            if absf(c.r-background.r)+absf(c.g-background.g)+absf(c.b-background.b) > 0.12:
                present += 1
    return float(present)/float(maxi(measured,1))
