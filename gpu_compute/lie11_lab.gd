extends Node3D
## Grayscale sprites, XYZ nodes, material codes and real Vulkan light bounces.
const Model=preload("res://lie11_model.gd")
const Effect=preload("res://lie11_light_effect.gd")
const SurfaceShader: Shader=preload("res://shaders/lie11_gray_sprite.gdshader")
var effect: CompositorEffect
var base_model: Dictionary
var model: Dictionary
var camera: Camera3D
var light_texture:=Texture2DRD.new()
var gray_texture: ImageTexture
var sprites: Array[Sprite3D]=[]
var materials: Array[ShaderMaterial]=[]
var label: Label
var blocker_sprite: Sprite3D
var scenario_name: String="bounce"
var yaw_degrees: float=0.0
var distance_scale: float=1.0
var ready_for_capture: bool=false

func _ready() -> void:
    get_window().size=Vector2i(1280,720)
    base_model=Model.load_room()
    if base_model.is_empty(): return
    model=Model.scenario(base_model,scenario_name)
    effect=Effect.new()
    if not effect.call("configure",model): return
    var compositor:=Compositor.new()
    compositor.compositor_effects=[effect]
    var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color(0.015,0.018,0.024)
    var world:=WorldEnvironment.new()
    world.environment=environment
    world.compositor=compositor
    add_child(world)
    camera=Camera3D.new()
    camera.fov=50.0
    add_child(camera)
    camera.current=true
    move_camera()
    var gray:=Image.create(128,128,false,Image.FORMAT_RGBA8)
    for y in range(128):
        for x in range(128):
            var value: float=184.0/255.0 if (x/16+y/16)%2==0 else 224.0/255.0
            gray.set_pixel(x,y,Color(value,value,value,1.0))
    gray_texture=ImageTexture.create_from_image(gray)
    var layer:=CanvasLayer.new()
    label=Label.new()
    label.position=Vector2(20,16)
    label.add_theme_font_size_override("font_size",20)
    label.add_theme_color_override("font_color",Color.WHITE)
    layer.add_child(label)
    add_child(layer)
    _update_label()

func _process(delta: float) -> void:
    if effect==null: return
    if not ready_for_capture and bool(effect.get("gpu_ready")):
        # Publish the RD wrapper ONCE on the main thread before materials exist.
        # Changing a published wrapper RID in a render callback can invalidate sets.
        light_texture.texture_rd_rid=effect.get("output_rid")
        _make_sprites()
        ready_for_capture=true
    if Input.is_action_pressed("ui_left"): yaw_degrees-=delta*35.0
    if Input.is_action_pressed("ui_right"): yaw_degrees+=delta*35.0
    if camera!=null: move_camera()
    var movement:=Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_W): movement.z-=delta
    if Input.is_physical_key_pressed(KEY_S): movement.z+=delta
    if Input.is_physical_key_pressed(KEY_A): movement.x-=delta
    if Input.is_physical_key_pressed(KEY_D): movement.x+=delta
    if movement.length_squared()>0.0 and ready_for_capture:
        var current: Vector3=Model.vector(model["lights"][0]["position"])
        current+=movement
        current.x=clampf(current.x,-0.9,0.9)
        current.z=clampf(current.z,-0.9,0.9)
        model["lights"][0]["position"]=[current.x,current.y,current.z]
        effect.call("set_light_codes",model)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_B: set_scenario("direct" if scenario_name!="direct" else "bounce")
        KEY_X: set_scenario("absorbing" if scenario_name!="absorbing" else "bounce")
        KEY_O: set_scenario("blocked" if scenario_name!="blocked" else "bounce")
        KEY_C: set_scenario("cool" if scenario_name!="cool" else "bounce")

func move_camera() -> void:
    var angle: float=deg_to_rad(yaw_degrees)
    var target:=Vector3(0,0.55,0)
    camera.position=target+Vector3(4.0*sin(angle),2.05,4.0*cos(angle))*distance_scale
    camera.look_at(target)

func _make_sprites() -> void:
    for i in range((model["patches"] as Array).size()):
        var patch: Dictionary=model["patches"][i]
        var sprite:=Sprite3D.new()
        sprite.texture=gray_texture
        sprite.pixel_size=1.0/128.0
        sprite.position=Model.vector(patch["position"])
        var normal: Vector3=Model.vector(patch["normal"])
        if normal==Vector3.UP: sprite.rotation_degrees.x=-90.0
        elif normal==Vector3.RIGHT: sprite.rotation_degrees.y=90.0
        elif normal==Vector3.LEFT: sprite.rotation_degrees.y=-90.0
        sprite.scale=Vector3(float(patch["size"][0]),float(patch["size"][1]),1.0)
        var material:=ShaderMaterial.new()
        material.shader=SurfaceShader
        material.set_shader_parameter("gray_map",gray_texture)
        material.set_shader_parameter("light_codes",light_texture)
        material.set_shader_parameter("patch_index",i)
        material.set_shader_parameter("patch_count",(model["patches"] as Array).size())
        sprite.material_override=material
        add_child(sprite)
        sprites.append(sprite)
        materials.append(material)
    # The blocking proxy has a corresponding grayscale visual, also a sprite.
    blocker_sprite=Sprite3D.new()
    blocker_sprite.texture=gray_texture
    blocker_sprite.pixel_size=1.0/128.0
    blocker_sprite.position=Vector3(-0.6,0.75,0)
    blocker_sprite.rotation_degrees.y=90
    blocker_sprite.scale=Vector3(2,1.5,1)
    blocker_sprite.modulate=Color(0.03,0.03,0.03)
    blocker_sprite.shaded=false
    add_child(blocker_sprite)
    _update_materials()

func _update_materials() -> void:
    for i in range(materials.size()):
        var patch: Dictionary=model["patches"][i]
        var code: Dictionary=model["materials"][patch["material"]]
        materials[i].set_shader_parameter("material_filter",Model.vector(code["tint_linear"]))
        materials[i].set_shader_parameter("absorption",float(code["absorption_code"])/1000.0)
    if blocker_sprite!=null: blocker_sprite.visible=scenario_name=="blocked"

func set_scenario(name: String) -> void:
    scenario_name=name
    model=Model.scenario(base_model,name)
    effect.call("configure",model)
    _update_materials()
    _update_label()

func set_code_texture(texture: Texture2D) -> void:
    for material in materials: material.set_shader_parameter("light_codes",texture)

func _update_label() -> void:
    if label==null: return
    var titles: Dictionary={"direct":"Direct light / no bounces","bounce":"Direct + two coded diffuse bounces",
        "absorbing":"Red material absorption: 98%","blocked":"Opaque blocker / visibility test",
        "moved":"Same sprites / light moved","cool":"Same sprites / blue light code"}
    label.text="LIE-11 | "+str(titles.get(scenario_name,scenario_name))+"\n64 grayscale sprites | XYZ + material codes | Vulkan\nArrows: camera   WASD: light   B: bounces   X: absorption   O: blocker   C: color"

func _exit_tree() -> void:
    if effect!=null:
        # Detach consumers before freeing the shared RD texture.
        for material in materials: material.set_shader_parameter("light_codes",null)
        light_texture.texture_rd_rid=RID()
        effect.call("shutdown")
