extends SceneTree
## Same-camera 45-degree quality diagnosis against prior LIE-05 and source GLB.
## Deliberately NO requirement that LIE-06 must always improve: regression is
## reported, not hidden. A poor result is research evidence, not success.
const Lab = preload("res://scenes/lie_06_lab.tscn")

func _initialize() -> void:
    call_deferred("_test")

func _foreground(c: Color) -> bool:
    var bg := Color("#0a1726")
    return absf(c.r-bg.r)+absf(c.g-bg.g)+absf(c.b-bg.b) > 0.35

func _iou(a: Image,b: Image) -> float:
    if a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
        return -1.0
    var shared: int = 0
    var union_count: int = 0
    var cx: int = a.get_width()/2
    var cy: int = a.get_height()/2
    for y in range(cy-185, cy+185, 2):
        for x in range(cx-185, cx+185, 2):
            var first: bool = _foreground(a.get_pixel(x,y))
            var second: bool = _foreground(b.get_pixel(x,y))
            if first or second:
                union_count += 1
            if first and second:
                shared += 1
    if union_count == 0:
        return 0.0
    return float(shared)/float(union_count)

func _test() -> void:
    var scene: Node3D = Lab.instantiate()
    root.add_child(scene)
    scene.set_process(false)
    var camera: Camera3D = scene.get_node("LieCamera")
    var node: Node3D = scene.get_node("LieMultiView")
    node.set_process(false)
    node.set("azimuth_steps", 4)
    node.set("elevations", PackedFloat32Array([-30,0,30]))
    node.set("target_resolution", 128)
    node.set("source_stride", 1)
    node.set("crop_screen_pixels", 320.0)
    node.set("max_sources", 4)
    camera.position = Vector3(6.0*sin(PI/4.0),1.2,6.0*cos(PI/4.0))
    camera.look_at(Vector3.ZERO,Vector3.UP)
    for child in scene.get_children():
        if child is CanvasLayer:
            child.visible = false
    if not bool(node.call("rebuild")) or not bool(node.get("using_real_capture")):
        _fail("Four-view Blender reprojection failed or fell back to synthetic")
        return
    var sources: Array = node.get("last_source_hits")
    if sources.size()!=4:
        _fail("Expected four real captured image inputs")
        return
    var contributed: int = 0
    for hits in sources:
        if int(hits)>0:
            contributed+=1
    if contributed<2:
        _fail("At least two views must contribute nonempty geometry")
        return
    for frame in range(12):
        await process_frame
    var image: Image = root.get_texture().get_image()
    if image.is_empty() or image.save_png("res://lie-06-angle-45.png")!=OK:
        _fail("Could not capture four-view GPU framebuffer")
        return
    var reference: Image = Image.load_from_file("res://lie-05-reference-3d-45.png")
    var baseline: Image = Image.load_from_file("res://lie-05-angle-45.png")
    var new_iou: float = _iou(image,reference)
    var old_iou: float = _iou(baseline,reference)
    if new_iou <= 0.0 or old_iou <= 0.0:
        _fail("Invalid GLB or LIE-05 reference comparison")
        return
    print("LIE-06 QUALITY DIAGNOSTIC same_camera=true sources=%d cpu_ms=%.2f iou_lie05=%.4f iou_lie06=%.4f delta=%.4f hits=%s" %
        [contributed,float(node.get("last_build_time_usec"))/1000.0,old_iou,new_iou,new_iou-old_iou,str(sources)])
    quit(0)

func _fail(msg: String) -> void:
    printerr("LIE-06 QUALITY FAIL ",msg)
    quit(1)
