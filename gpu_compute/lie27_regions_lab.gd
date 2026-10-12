extends Node3D
const Rig=preload("res://lie27_rig.gd")
const Effect=preload("res://lie27_regions_effect.gd")
var effect: CompositorEffect
var camera: Camera3D
var texture: Texture2DRD
var picture: TextureRect
var status: Label
var state: Dictionary={"mask":15,"camera_yaw":0.0,"object_yaw":0.0,"light_azimuth":-35.0,"light_power":70.0,"distance":3.5,"unlit":false,"shadows":false,
    "palette":[[.52,.29,.18],[.32,.045,.028],[.72,.64,.47],[.29,.12,.15]],"light_color":[1.0,.88,.76],"pose":{},"targets":{},"mode":"manual","playing":false,"time":0.0,"speed":1.0,"focus":"body","show_regions":false,"face_playing":false,"eyes":{"sclera":[.82,.84,.78],"iris":[.16,.06,.015],"pupil":[.002,.002,.003],"roughness":.18},"face":{"blink_left":0.0,"blink_right":0.0,"smile":0.0,"frown":0.0,"brow_up":0.0,"brow_down":0.0,"jaw_open":0.0}}
var skeleton: Skeleton3D
var evaluated: Dictionary={}
var bodies: Array[AnimatableBody3D]=[]
var motion_accumulator: float=0
var revision: int=0
var controls: Dictionary={}
var connected: bool=false
var joint_spheres: Array[AnimatableBody3D]=[]
var overlay: Control
const FACE_KEYS=["blink_left","blink_right","smile","frown","brow_up","brow_down","jaw_open"]
const LIMITS={"camera_yaw":[-180,180],"object_yaw":[-90,90],"light_azimuth":[-180,180],"light_power":[0,200],"distance":[.18,5],"time":[0,60],"speed":[.1,2.0]}

func _ready() -> void:
    get_window().size=Vector2i(1280,800)
    effect=Effect.new(512,2)
    var world:=WorldEnvironment.new();var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.018,.023,.03);world.environment=environment
    var compositor:=Compositor.new();compositor.compositor_effects=[effect];world.compositor=compositor;add_child(world)
    camera=Camera3D.new();camera.current=true;camera.fov=35;camera.near=.01;camera.far=10;add_child(camera)
    var ui:=CanvasLayer.new();add_child(ui)
    var title:=Label.new();title.text="LIE-27  ·  Articulaciones y rostro";title.position=Vector2(24,18);title.add_theme_font_size_override("font_size",26);ui.add_child(title)
    picture=TextureRect.new();picture.position=Vector2(330,70);picture.size=Vector2(684,684);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ui.add_child(picture)
    var scroll:=ScrollContainer.new();scroll.position=Vector2(24,72);scroll.size=Vector2(290,684);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;ui.add_child(scroll)
    var box:=VBoxContainer.new();box.custom_minimum_size.x=276;box.add_theme_constant_override("separation",9);scroll.add_child(box)
    var credit:=Label.new();credit.text="3DAnatomyman · Always3D / DBCLS\nCC BY-SA 2.1 JP\n45 huesos · capturas por segmento";credit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;credit.custom_minimum_size.x=276;box.add_child(credit)
    for id in range(4):
        var row:=HBoxContainer.new();box.add_child(row)
        var toggle:=CheckBox.new();toggle.text=["Piel","Músculos","Huesos","Interiores"][id];toggle.button_pressed=true;toggle.custom_minimum_size.x=170;row.add_child(toggle)
        toggle.toggled.connect(func(on: bool):command({"op":"set_values","values":{"mask":int(state["mask"])|(1<<id) if on else int(state["mask"])&~(1<<id)}}))
        controls["layer%d"%id]=toggle
        var picker:=ColorPickerButton.new();var c: Array=state["palette"][id];picker.color=Color(c[0],c[1],c[2]).linear_to_srgb();picker.custom_minimum_size=Vector2(65,32);row.add_child(picker);controls["color%d"%id]=picker
        picker.color_changed.connect(func(color: Color):
            var palette: Array=state["palette"].duplicate(true);var linear:=color.srgb_to_linear();palette[id]=[linear.r,linear.g,linear.b]
            command({"op":"set_values","values":{"palette":palette}}))
    var focus_row:=HBoxContainer.new();box.add_child(focus_row)
    for focus_name in ["body","face","hand"]:
        var focus_button:=Button.new();focus_button.text={"body":"Cuerpo","face":"Rostro","hand":"Mano"}[focus_name];focus_row.add_child(focus_button)
        focus_button.pressed.connect(func():command({"op":"set_values","values":{"focus":focus_name,"distance":3.5 if focus_name=="body" else .35}}))
    var regions_toggle:=CheckBox.new();regions_toggle.text="Mostrar zonas esféricas";box.add_child(regions_toggle)
    regions_toggle.toggled.connect(func(v: bool):command({"op":"set_values","values":{"show_regions":v}}))
    var face_title:=Label.new();face_title.text="PÁRPADOS Y EXPRESIONES";box.add_child(face_title)
    var face_presets:=HBoxContainer.new();box.add_child(face_presets)
    for expression in ["Neutral","Sonrisa","Ceño","Sorpresa"]:
        var button:=Button.new();button.text=expression;face_presets.add_child(button)
        button.pressed.connect(func():
            var values: Dictionary={}
            for key in FACE_KEYS:values[key]=0.0
            if expression=="Sonrisa":values["smile"]=1.0
            elif expression=="Ceño":values["frown"]=1.0;values["brow_down"]=1.0
            elif expression=="Sorpresa":values["brow_up"]=1.0;values["jaw_open"]=1.0
            command({"op":"set_values","values":{"face":values,"focus":"face","distance":.35,"face_playing":false}}))
    for key in FACE_KEYS:
        var label:=Label.new();label.text={"blink_left":"Párpado izquierdo","blink_right":"Párpado derecho","smile":"Comisuras arriba","frown":"Comisuras abajo","brow_up":"Cejas arriba","brow_down":"Cejas abajo","jaw_open":"Mandíbula"}[key];box.add_child(label)
        var slider:=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=.01;box.add_child(slider);controls["face_"+key]=slider
        slider.value_changed.connect(func(v: float):
            var values: Dictionary=state["face"].duplicate(true);values[key]=v
            command({"op":"set_values","values":{"face":values,"face_playing":false}}))
    var blink_button:=Button.new();blink_button.text="Parpadeo automático";box.add_child(blink_button)
    blink_button.pressed.connect(func():command({"op":"set_values","values":{"face_playing":not state["face_playing"]}}))
    for key in ["sclera","iris","pupil"]:
        var row:=HBoxContainer.new();box.add_child(row)
        var label:=Label.new();label.text={"sclera":"Blanco del ojo","iris":"Color del iris","pupil":"Color de pupila"}[key];label.custom_minimum_size.x=170;row.add_child(label)
        var picker:=ColorPickerButton.new();var rgb: Array=state["eyes"][key];picker.color=Color(rgb[0],rgb[1],rgb[2]).linear_to_srgb();picker.custom_minimum_size=Vector2(65,32);row.add_child(picker);controls["eye_"+key]=picker
        picker.color_changed.connect(func(value: Color):
            var eyes: Dictionary=state["eyes"].duplicate(true);var linear: Color=value.srgb_to_linear();eyes[key]=[linear.r,linear.g,linear.b]
            command({"op":"set_values","values":{"eyes":eyes}}))
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
    var limit:=Label.new();limit.text="Expresiones aproximadas.\nMandíbula y dedos pendientes de afinación.\nModelo anatómico sin ropa.";limit.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(limit)
    var back:=Button.new();back.text="Volver al taller";back.pressed.connect(func():get_tree().change_scene_to_file("res://lie18_workshop.tscn"));box.add_child(back)
    _build_rig()
    overlay=preload("res://lie27_region_overlay.gd").new();overlay.set("lab",self);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(overlay)
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
        elif key=="face":
            if not value is Dictionary or value.size()!=FACE_KEYS.size():return {"ok":false,"error":"face fields"}
            for field in value:
                var amount: Variant=value[field]
                if field not in FACE_KEYS or not (amount is int or amount is float) or not is_finite(float(amount)) or amount<0 or amount>1:return {"ok":false,"error":"face range"}
        elif key=="eyes":
            if not value is Dictionary or value.size()!=4 or not value.has("roughness"):return {"ok":false,"error":"eye fields"}
            for field in ["sclera","iris","pupil"]:
                if not value.get(field) is Array or value[field].size()!=3:return {"ok":false,"error":"eye color"}
                for component in value[field]:
                    if not (component is int or component is float) or not is_finite(float(component)) or component<0 or component>1:return {"ok":false,"error":"eye color"}
            if not (value["roughness"] is int or value["roughness"] is float) or not is_finite(float(value["roughness"])) or value["roughness"]<.08 or value["roughness"]>.6:return {"ok":false,"error":"eye roughness"}
        elif key=="focus":
            if value not in ["body","face","hand"]:return {"ok":false,"error":"focus"}
        elif key in ["unlit","shadows","playing","show_regions","face_playing"]:
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
    for key in FACE_KEYS:
        if controls.has("face_"+key):controls["face_"+key].set_value_no_signal(float(state["face"][key]))
    for key in ["sclera","iris","pupil"]:
        if controls.has("eye_"+key):
            var rgb: Array=state["eyes"][key];controls["eye_"+key].color=Color(rgb[0],rgb[1],rgb[2]).linear_to_srgb()
    return {"ok":true,"revision":revision}

func _apply() -> void:
    if camera==null or not effect.get("capture_loaded"):return
    var yaw: float=deg_to_rad(float(state["camera_yaw"]));var target: Vector3=Vector3(0,.82,.09) if state["focus"]=="body" else Vector3(0,1.525,.16) if state["focus"]=="face" else Vector3(-.27,.745,.15);camera.position=target+Vector3(sin(yaw),0,cos(yaw))*float(state["distance"]);camera.look_at(target)
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
    var face_values:=PackedFloat32Array()
    for key in FACE_KEYS:face_values.append(float(state["face"][key]))
    face_values.append(0)
    var eye_values:=PackedFloat32Array()
    for key in ["sclera","iris","pupil"]:
        var rgb: Array=state["eyes"][key];eye_values.append_array(PackedFloat32Array([rgb[0],rgb[1],rgb[2],state["eyes"]["roughness"] if key=="sclera" else 0]))
    if not effect.call("configure",bytes,Rig.packet(evaluated),face_values.to_byte_array(),eye_values.to_byte_array()):status.text="Paquete rechazado"
    if overlay!=null:overlay.queue_redraw()

func _process(delta: float) -> void:
    if state["playing"] or state["face_playing"]:
        motion_accumulator+=delta
        if motion_accumulator>=1.0/30:
            state["time"]=fmod(float(state["time"])+motion_accumulator*float(state["speed"]),60);motion_accumulator=0
            if state["face_playing"]:
                var phase: float=fmod(float(state["time"]),3.0);var blink: float=pow(maxf(1-absf(phase-.3)/.16,0),2)
                state["face"]["blink_left"]=blink;state["face"]["blink_right"]=blink
            _apply()
            controls["time"].set_value_no_signal(state["time"])
    if effect.get("gpu_ready") and not connected:
        texture=Texture2DRD.new();texture.texture_rd_rid=effect.get("output_rid");picture.texture=texture;connected=true
    status.text=effect.get("failure") if not str(effect.get("failure")).is_empty() else "%s muestras · %.1f MiB Lie\n45 huesos · FK + IK\nGPU/Android físico pendiente"%[str(int(effect.get("master").get("sample_count",0))),float(effect.get("allocation_bytes"))/1048576]

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
    for zone in effect.get("master")["joint_regions"]:
        var body:=AnimatableBody3D.new();body.name="Joint_"+str(zone["name"]);body.sync_to_physics=false;body.collision_layer=2;body.collision_mask=0;add_child(body);joint_spheres.append(body)
        var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=zone["radii"][0];shape.shape=sphere;body.add_child(shape)
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
    for i in range(joint_spheres.size()):
        var zone: Dictionary=effect.get("master")["joint_regions"][i];var t: Transform3D=evaluated["skins"][int(zone["parent"])]
        joint_spheres[i].transform=Transform3D(t.basis,t*Rig.vector(zone["center"]))

func _exit_tree() -> void:
    if texture!=null:texture.texture_rd_rid=RID()
    if effect!=null:effect.call("shutdown")
