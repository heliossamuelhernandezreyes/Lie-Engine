extends "res://lie12_lab.gd"
const Optics=preload("res://lie13_optics_effect.gd")
var optics: CompositorEffect
var optical_name: String="mixed"
var animate: bool=true
var optical_time: float=0.0
var _anchor_right:=Vector3.RIGHT
var _anchor_up:=Vector3.UP
var _anchor_toward:=Vector3.BACK

func _ready() -> void:
    super._ready()
    if camera==null: return
    _anchor_right=camera.global_basis.x
    _anchor_up=camera.global_basis.y
    _anchor_toward=camera.position.normalized()
    optics=Optics.new()
    optics.set("capture",effect)
    optics.set("lighting",lighting)
    for node in get_children():
        if node is WorldEnvironment: (node as WorldEnvironment).compositor.compositor_effects=[lighting,effect,optics]
    set_optical_scene("mixed")
    _update_label()

func set_scenario(name: String) -> void:
    scenario_name=name
    model=base_model.duplicate(true)
    model["bounces"]=0 if name=="direct" else 3
    model["secondary_radii"]={"radius_max":4.0,"radius_decay":.82,"power_reference":.015}
    match name:
        "absorbing":
            for key in model["materials"]:
                if "bounce red" in str(key): model["materials"][key]["absorption_code"]=980
        "short": model["secondary_radii"]["radius_max"]=.3
        "legacy": model.erase("secondary_radii")
        "cool": model["lights"][0]["power_rgb"]=[7,17.5,35]
        "dark": model["lights"][0]["power_rgb"]=[0,0,0]
        "moved": model["lights"][0]["position"]=[.8,.6,.5]
        "filtered": model["optical_sheets"]=[{"center":[0,0,.4],"right":[1,0,0],"up":[0,1,0],"half_width":1.5,"half_height":1.5,"ior":1.5,"thickness":.1,"sigma":[5,.4,.1]}]
    lighting.call("configure",model)
    _update_label()

func sheet(center: Vector3,right: Vector3,up: Vector3,width: float,height: float,ior: float,thickness: float,sigma: Array,kind: int=0) -> Dictionary:
    return {"center":[center.x,center.y,center.z],"right":[right.x,right.y,right.z],"up":[up.x,up.y,up.z],
        "half_width":width,"half_height":height,"ior":ior,"thickness":thickness,"sigma":sigma,"kind":kind,"wave":.025 if kind==1 else 0.0,"frequency":7.0}

func optical_sprites(name: String) -> Array:
    var r: Vector3=_anchor_right
    var u: Vector3=_anchor_up
    var toward: Vector3=_anchor_toward
    var center: Vector3=toward*1.3
    var glass: Dictionary=sheet(center-r*.48,r,u,.44,.68,1.5,.025,[3.0,.5,.2])
    var water: Dictionary=sheet(center+r*.5,r,u,.44,.68,1.333,.12,[1.8,.3,.08],1)
    match name:
        "none": return []
        "identity":
            var identity: Dictionary=sheet(center,r,u,.85,.8,1,0,[0,0,0])
            return [identity]
        "glass":
            glass["center"]=[center.x,center.y,center.z]
            return [glass]
        "thick":
            glass["center"]=[center.x,center.y,center.z]
            glass["thickness"]=.25
            return [glass]
        "water":
            water["center"]=[center.x,center.y,center.z]
            return [water]
        "layers":
            water["center"]=[center.x,center.y,center.z]
            var far: Vector3=center-toward*.3
            glass["center"]=[far.x,far.y,far.z]
            return [glass,water]
        "rain": return rain_sprites()
    var all: Array=[glass,water]
    all.append_array(rain_sprites())
    return all

func rain_sprites() -> Array:
    var values: Array=[]
    # Twelve deterministic drops share ONE normal/coverage sprite. XYZ, metre
    # size and thickness differ per instance. No fluid solver or collision claim.
    for i in range(12):
        var x: float=-.95+float(i%4)*.63
        var y: float=-.85+fposmod(float(i/4)*.7-optical_time*.65,2.0)
        var p: Vector3=_anchor_toward*(.5+float(i%3)*.6)+_anchor_right*x+_anchor_up*y
        values.append(sheet(p,camera.global_basis.x,camera.global_basis.y,.025,.085,1.333,.005,[.3,.06,.015],2))
    return values

func set_optical_scene(name: String) -> void:
    optical_name=name
    if optics!=null: optics.call("set_sprites",optical_sprites(name))
    _update_label()

func _process(delta: float) -> void:
    super._process(delta)
    if optics==null: return
    if animate: optical_time+=delta
    optics.set("time_value",optical_time)
    if animate and optical_name in ["mixed","rain"]: optics.call("set_sprites",optical_sprites(optical_name))

func _unhandled_key_input(event: InputEvent) -> void:
    super._unhandled_key_input(event)
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_1: set_optical_scene("none")
        KEY_2: set_optical_scene("glass")
        KEY_3: set_optical_scene("water")
        KEY_4: set_optical_scene("rain")
        KEY_5: set_optical_scene("mixed")
        KEY_R: set_scenario("short" if scenario_name!="short" else "bounce")
        KEY_T: set_scenario("filtered" if scenario_name!="filtered" else "bounce")
        KEY_SPACE: animate=not animate

func _update_label() -> void:
    if label!=null: label.text="LIE-13 | Radio de rebote + sprites de vidrio, agua y lluvia\n"+scenario_name+" / "+optical_name+" | 1–5: materiales, R: radio, B: rebotes, X: absorción, espacio: pausa"

func _exit_tree() -> void:
    if optics!=null: optics.call("shutdown")
    super._exit_tree()
