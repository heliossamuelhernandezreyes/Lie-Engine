extends Node3D
const Rig=preload("res://lie26_rig.gd")
const Effect=preload("res://lie26_motion_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var texture: Texture2DRD
var picture: TextureRect
var status: Label
var state: Dictionary={"mask":15,"camera_yaw":0.0,"object_yaw":0.0,"light_azimuth":-35.0,"light_power":70.0,"distance":3.5,"unlit":false,"shadows":false,
    "palette":[[.52,.29,.18],[.32,.045,.028],[.72,.64,.47],[.29,.12,.15]],"light_color":[1.0,.88,.76],"pose":{},"targets":{},"mode":"manual","playing":false,"time":0.0,"speed":1.0}
var skeleton: Skeleton3D
var evaluated: Dictionary={}
var bodies: Array[AnimatableBody3D]=[]
var motion_accumulator: float=0
var revision: int=0
var controls: Dictionary={}
var connected: bool=false
const LIMITS={"camera_yaw":[-180,180],"object_yaw":[-90,90],"light_azimuth":[-180,180],"light_power":[0,200],"distance":[1.4,5],"time":[0,60],"speed":[.1,2.0]}

func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    effect=Effect.new(512,2)
    var world:=WorldEnvironment.new();var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.018,.023,.03);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.fov=35;camera.near=.01;camera.far=10;add_child(camera)
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.text="LIE  ·  Movimiento anatómico";title.position=Vector2(24,18);title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(330,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var scroll:=ScrollContainer.new();scroll.position=Vector2(24,72);scroll.size=Vector2(290,684);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;ui.add_child(scroll)
    var box:=VBoxContainer.new();box.custom_minimum_size.x=276;box.add_theme_constant_override("separation",9);scroll.add_child(box)
    var credit:=Label.new();credit.text="3DAnatomyman · Always3D / DBCLS\nCC BY-SA 2.1 JP\n15 huesos · capturas por segmento";credit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;credit.custom_minimum_size.x=276;box.add_child(credit)
    for id in range(4):
        var row:=HBoxContainer.new();box.add_child(row)
        var toggle:=CheckBox.new();toggle.text=["Piel","Músculos","Huesos","Interiores"][id];toggle.button_pressed=true;toggle.custom_minimum_size.x=170;row.add_child(toggle)
        toggle.toggled.connect(func(on: bool):command({"op":"set_values","values":{"mask":int(state["mask"])|(1<<id) if on else int(state["mask"])&~(1<<id)}}))
        controls["layer%d"%id]=toggle
        var picker:=ColorPickerButton.new();var c: Array=state["palette"][id];picker.color=Color(c[0],c[1],c[2]).linear_to_srgb();picker.custom_minimum_size=Vector2(65,32);row.add_child(picker);controls["color%d"%id]=picker
        picker.color_changed.connect(func(color: Color):
            var palette: Array=state["palette"].duplicate(true);var linear:=color.srgb_to_linear();palette[id]=[linear.r,linear.g,linear.b]
            command({"op":"set_values","values":{"palette":palette}}))
    var presets:=HBoxContainer.new();box.add_child(presets)
    for preset_name in ["Reposo","Codos","Alcanzar"]:
        var button:=Button.new();button.text=preset_name;presets.add_child(button)
        button.pressed.connect(func():
            var pose: Dictionary={} if preset_name=="Reposo" else {"right_elbow":110,"left_elbow":75} if preset_name=="Codos" else {"right_shoulder":50,"right_elbow":60,"left_abduction":60,"left_elbow":80,"torso_bend":12}
            command({"op":"set_values","values":{"pose":pose,"targets":{},"mode":"manual","playing":false}}))
    var play:=Button.new();play.text="Caminar / pausar";box.add_child(play);controls["play"]=play
    play.pressed.connect(func():command({"op":"set_values","values":{"mode":"walk","playing":not state["playing"]}}))
    for key in LIMITS:
        var label:=Label.new();label.text={"camera_yaw":"Órbita","object_yaw":"Orientación del cuerpo","light_azimuth":"Dirección de luz","light_power":"Potencia","distance":"Distancia","time":"Tiempo (s)","speed":"Velocidad"}[key];box.add_child(label)
        var slider:=HSlider.new();slider.min_value=LIMITS[key][0];slider.max_value=LIMITS[key][1];slider.step=.01;slider.value=state[key];box.add_child(slider)
        slider.value_changed.connect(func(value: float):command({"op":"set_values","values":{key:value}}));controls[key]=slider
    var joints:=Label.new();joints.text="ARTICULACIONES · grados";box.add_child(joints)
    for key in Rig.LIMITS:
        if key=="root_yaw":continue
        var label:=Label.new();label.text=key.replace("right_","D · ").replace("left_","I · ");box.add_child(label)
        var slider:=HSlider.new();slider.min_value=Rig.LIMITS[key][0];slider.max_value=Rig.LIMITS[key][1];slider.step=.1;box.add_child(slider);controls["pose_"+key]=slider
        slider.value_changed.connect(func(v: float):command({"op":"set_pose","values":{key:v}}))
    var ik_label:=Label.new();ik_label.text="IK · objetivo de mano derecha";box.add_child(ik_label)
    var ik_toggle:=CheckBox.new();ik_toggle.text="Dirigir mano con objetivo";box.add_child(ik_toggle);controls["ik_toggle"]=ik_toggle
    ik_toggle.toggled.connect(func(on: bool):
        var targets: Dictionary=state["targets"].duplicate(true)
        if on:targets["right_hand"]={"position":[-.25,1.2,.36],"pole":[-.5,.8,.5]}
        else:targets.erase("right_hand")
        command({"op":"set_values","values":{"targets":targets,"mode":"manual","playing":false}}))
    for axis in range(3):
        var label:=Label.new();label.text=["Objetivo X","Objetivo Y","Objetivo Z"][axis];box.add_child(label)
        var slider:=HSlider.new();slider.min_value=-1 if axis!=1 else .2;slider.max_value=1 if axis!=1 else 2;slider.step=.005;slider.value=[-.25,1.2,.36][axis];box.add_child(slider);controls["ik%d"%axis]=slider
        slider.value_changed.connect(func(v: float):
            var targets: Dictionary=state["targets"].duplicate(true);var target: Dictionary=targets.get("right_hand",{"position":[-.25,1.2,.36],"pole":[-.5,.8,.5]});target["position"][axis]=v;targets["right_hand"]=target
            command({"op":"set_values","values":{"targets":targets,"mode":"manual","playing":false}}))
    status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=276;box.add_child(status)
    var limit:=Label.new();limit.text="Rig de juego; sin contracción muscular.\nDedos como una pieza; sin ropa ni ragdoll.\nSombras desde muestras capturadas.";limit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(limit)
    var back:=Button.new();back.text="Volver al taller";back.pressed.connect(func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"));box.add_child(back)
    _build_rig()
    _apply()

func command(request: Variant) -> Dictionary:
    if not request is Dictionary:return {"ok":false,"error":"request"}
    if request.get("op")=="snapshot":return {"ok":true,"revision":revision,"state":state.duplicate(true)}
    if request.get("op")=="set_pose" and request.get("values") is Dictionary:
        var merged: Dictionary=state["pose"].duplicate(true);merged.merge(request["values"],true)
        var next_request: Dictionary={"op":"set_values","values":{"pose":merged,"mode":"manual","playing":false}}
        if request.has("expected_revision"):next_request["expected_revision"]=request["expected_revision"]
        return command(next_request)
    if request.get("op")!="set_values" or not request.get("values") is Dictionary:return {"ok":false,"error":"operation"}
    if request.has("expected_revision") and request["expected_revision"]!=revision:return {"ok":false,"error":"stale revision"}
    var next: Dictionary=state.duplicate(true)
    for key in request["values"]:
        var value: Variant=request["values"][key]
        if key in LIMITS:
            if not (value is int or value is float) or not is_finite(float(value)) or value<LIMITS[key][0] or value>LIMITS[key][1]:return {"ok":false,"error":"range"}
        elif key=="mask":
            if not (value is int or value is float) or not is_finite(float(value)) or value!=floorf(value) or value<0 or value>15:return {"ok":false,"error":"mask"}
        elif key=="pose":
            if not Rig.validate_pose(value):return {"ok":false,"error":"pose limits"}
        elif key=="targets":
            if not Rig.validate_targets(value):return {"ok":false,"error":"IK target"}
        elif key=="mode":
            if value not in ["manual","walk"]:return {"ok":false,"error":"mode"}
        elif key in ["unlit","shadows","playing"]:
            if not value is bool:return {"ok":false,"error":"boolean"}
        elif key in ["palette","light_color"]:
            var colors: Array=value if key=="palette" and value is Array else [value]
            if key=="palette" and colors.size()!=4:return {"ok":false,"error":"palette"}
            for color in colors:
                if not color is Array or color.size()!=3:return {"ok":false,"error":"color"}
                for component in color:
                    if not (component is int or component is float) or not is_finite(float(component)) or component<0 or component>1:return {"ok":false,"error":"color"}
        else:return {"ok":false,"error":"unknown field"}
        next[key]=value.duplicate(true) if value is Dictionary or value is Array else value
    state=next;revision+=1;_apply()
    for key in LIMITS:
        if controls.has(key):controls[key].set_value_no_signal(float(state[key]))
    for id in range(4):
        if controls.has("layer%d"%id):controls["layer%d"%id].set_pressed_no_signal(int(state["mask"])&(1<<id)!=0)
        if controls.has("color%d"%id):
            var pigment: Array=state["palette"][id];controls["color%d"%id].color=Color(pigment[0],pigment[1],pigment[2]).linear_to_srgb()
    for key in Rig.LIMITS:
        if controls.has("pose_"+key):controls["pose_"+key].set_value_no_signal(float(state["pose"].get(key,0)))
    if controls.has("ik_toggle"):controls["ik_toggle"].set_pressed_no_signal(state["targets"].has("right_hand"))
    if state["targets"].has("right_hand"):
        for axis in range(3):controls["ik%d"%axis].set_value_no_signal(state["targets"]["right_hand"]["position"][axis])
    return {"ok":true,"revision":revision}

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var yaw: float=deg_to_rad(float(state["camera_yaw"]));var target:=Vector3(0,.82,.09);camera.position=target+Vector3(sin(yaw),0,cos(yaw))*float(state["distance"]);camera.look_at(target)
    var angle: float=deg_to_rad(float(state["light_azimuth"]));var light:=Vector3(sin(angle)*1.5,1.8,cos(angle)*1.5+.09)
    var shadow:=Transform3D(Basis.IDENTITY,light).looking_at(Vector3(0,.82,.09),Vector3.UP)
    var floats:=PackedFloat32Array()
    for v in [camera.position,camera.basis.x,camera.basis.y,-camera.basis.z]:floats.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    floats.append_array(PackedFloat32Array([tan(deg_to_rad(camera.fov)*.5),1,.01,10,0,0,0,0]))
    var bytes: PackedByteArray=floats.to_byte_array();var master: Dictionary=effect.get("master");var count: int=int(master["sample_count"])
    bytes.append_array(PackedInt32Array([count,int(master["vertex_count"]),effect.get("render_size"),effect.get("render_size")]).to_byte_array())
    floats=PackedFloat32Array([deg_to_rad(float(state["object_yaw"])),0,state["mask"],0,light.x,light.y,light.z,state["light_power"]])
    var c: Array=state["light_color"];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0,.12,.14,.17,1,1 if state["shadows"] else 0,1,1 if state["unlit"] else 0,0]))
    for v in [shadow.basis.x,shadow.basis.y,-shadow.basis.z]:floats.append_array(PackedFloat32Array([v.x,v.y,v.z,0]))
    c=state["palette"][0];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0,0,0,count,0]))
    for id in range(1,4):
        c=state["palette"][id];floats.append_array(PackedFloat32Array([c[0],c[1],c[2],0]))
    bytes.append_array(floats.to_byte_array())
    var pose: Dictionary=state["pose"].duplicate(true);var targets: Dictionary=state["targets"].duplicate(true)
    if state["mode"]=="walk":
        var walking: Dictionary=Rig.walk(float(state["time"]));pose=walking["pose"];targets=walking["targets"]
    pose["root_yaw"]=clampf(float(pose.get("root_yaw",0))+float(state["object_yaw"]),-180,180)
    evaluated=Rig.evaluate(master["bones"],pose,targets)
    _update_rig()
    if not effect.call("configure",bytes,Rig.packet(evaluated)):status.text="Paquete rechazado"

func _process(delta: float) -> void:
    if state["playing"]:
        motion_accumulator+=delta
        if motion_accumulator>=1.0/30:
            state["time"]=fmod(float(state["time"])+motion_accumulator*float(state["speed"]),60);motion_accumulator=0;_apply()
            controls["time"].set_value_no_signal(state["time"])
    if effect.get("gpu_ready") and not connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;connected=true
    status.text=effect.get("failure") if not str(effect.get("failure")).is_empty() else "%s muestras · %.1f MiB Lie\n15 huesos · FK + IK\nGPU/Android físico pendiente"%[str(int(effect.get("master").get("sample_count",0))),float(effect.get("allocation_bytes"))/1048576]

func _build_rig() -> void:
    if not effect.get("capture_loaded"):return
    skeleton=Skeleton3D.new();add_child(skeleton)
    var bones: Array=effect.get("master")["bones"]
    for b in bones:
        var id: int=int(b["id"]);skeleton.add_bone(b["name"])
        var parent: int=int(b["parent"]);skeleton.set_bone_parent(id,parent)
        var pivot: Vector3=Rig.vector(b["pivot"])
        skeleton.set_bone_rest(id,Transform3D(Basis.IDENTITY,pivot if parent<0 else pivot-Rig.vector(bones[parent]["pivot"])))
        var body:=AnimatableBody3D.new();body.name="Proxy_"+str(b["name"]);body.sync_to_physics=false;body.collision_layer=2;body.collision_mask=0;add_child(body);bodies.append(body)
        var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();var length: float=pivot.distance_to(Rig.vector(b["end"]))
        capsule.radius=minf(.045,length*.24);capsule.height=maxf(length,capsule.radius*2);shape.shape=capsule;body.add_child(shape)
    var floor:=StaticBody3D.new();floor.name="InvisibleGround";floor.collision_layer=1;floor.collision_mask=0;floor.position=Vector3(0,-.04,0);add_child(floor)
    var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(6,.02,6);shape.shape=box;floor.add_child(shape)

func _update_rig() -> void:
    if skeleton==null or evaluated.is_empty():return
    var bones: Array=effect.get("master")["bones"]
    for i in range(bones.size()):
        skeleton.set_bone_pose_rotation(i,evaluated["locals"][i])
        skeleton.set_bone_pose_position(i,evaluated["origins"][i] if i==0 else Rig.vector(bones[i]["pivot"])-Rig.vector(bones[int(bones[i]["parent"])]["pivot"]))
        var pivot: Vector3=Rig.vector(bones[i]["pivot"]);var end: Vector3=Rig.vector(bones[i]["end"])
        var t: Transform3D=evaluated["skins"][i];var orientation:=Basis(Quaternion(Vector3.UP,(end-pivot).normalized()))
        bodies[i].transform=Transform3D(t.basis*orientation,t*((pivot+end)*.5))

func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
