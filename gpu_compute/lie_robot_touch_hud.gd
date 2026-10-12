extends Control
## Finger IDs remain independent. Every mutation uses the existing lab command.
var lab: Node3D
var picture: TextureRect
var status: Label
var overlay: Control
var move_finger: int=-1
var look_finger: int=-1
var stick:=Vector2.ZERO
var move_center:=Vector2.ZERO
var radius: float=88
var _mouse_mode: int=0
var _ready_seconds: float=0
var _paused: bool=false

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter=Control.MOUSE_FILTER_IGNORE
    var background:=ColorRect.new();background.color=Color("101924");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
    picture=TextureRect.new();picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(picture)
    var top:=HBoxContainer.new();top.position=Vector2(28,20);top.add_theme_constant_override("separation",12);add_child(top)
    var title:=Label.new();title.text="LIE / R2";title.add_theme_font_size_override("font_size",24);top.add_child(title)
    for action in [["Entrada",_reset],["Ver casa",_view],["Techo",_roof],["Sombras",_shadows],["Pinzas",_grip],["−",_farther],["+",_closer],["Pausa",_pause]]:
        var button:=Button.new();button.text=action[0];button.custom_minimum_size=Vector2(66,48);button.add_theme_font_size_override("font_size",18);button.focus_mode=Control.FOCUS_NONE;button.pressed.connect(action[1]);top.add_child(button)
    status=Label.new();status.position=Vector2(28,80);status.add_theme_font_size_override("font_size",17);status.text="Cargando robot y casa…";status.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(status)
    overlay=Control.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay);overlay.draw.connect(_draw_controls.bind(overlay))
    resized.connect(_layout);_layout()

func _layout() -> void:
    move_center=Vector2(150,size.y-145)
    if overlay!=null:overlay.queue_redraw()

func _draw_controls(canvas: Control) -> void:
    canvas.draw_circle(move_center,radius+6,Color(0,0,0,.4))
    canvas.draw_circle(move_center,radius,Color(.20,.48,.62,.22))
    canvas.draw_arc(move_center,radius,0,TAU,64,Color(.46,.82,.92,.7),2,true)
    canvas.draw_circle(move_center+stick*radius,32,Color(.46,.82,.92,.75))
    var font:=ThemeDB.fallback_font
    canvas.draw_string(font,move_center+Vector2(-83,radius+32),"MOVER / GIRAR",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(.8,.9,.95))
    canvas.draw_string(font,Vector2(size.x-300,size.y-48),"ARRASTRA PARA MIRAR",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(.8,.9,.95))

func _send(values: Dictionary) -> void:
    lab.command({"op":"set_values","values":values})

func _movement(point: Vector2) -> void:
    stick=((point-move_center)/radius).limit_length(1)
    if stick.length()<.12:stick=Vector2.ZERO
    _paused=false
    _send({"move":[0.0,-stick.y],"turn":-stick.x,"playing":true})
    overlay.queue_redraw()

func _orbit(relative: Vector2) -> void:
    _send({"camera_yaw":wrapf(lab.state["camera_yaw"]-relative.x*.25,-180,180),"camera_elevation":clampf(lab.state["camera_elevation"]+relative.y*.18,5,65)})

func touch(index: int,pressed: bool,point: Vector2) -> bool:
    if not pressed:
        if index==move_finger:
            move_finger=-1;stick=Vector2.ZERO;_send({"move":[0,0],"turn":0});overlay.queue_redraw();return true
        if index==look_finger:look_finger=-1;return true
        return false
    if point.y<145:return false # Leave the top buttons to Godot GUI.
    if point.distance_to(move_center)<=radius*1.4 and move_finger<0:
        move_finger=index;_movement(point);return true
    if look_finger<0:look_finger=index;return true
    return false

func drag(index: int,point: Vector2,relative: Vector2) -> bool:
    if index==move_finger:_movement(point);return true
    if index==look_finger:_orbit(relative);return true
    return false

func _input(event: InputEvent) -> void:
    var used: bool=false
    if event is InputEventScreenTouch:used=touch(event.index,event.pressed,event.position)
    elif event is InputEventScreenDrag:used=drag(event.index,event.position,event.relative)
    elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        if event.pressed:_mouse_mode=1 if event.position.x<size.x*.35 else 2
        used=touch(999,event.pressed,event.position)
        if not event.pressed:_mouse_mode=0
    elif event is InputEventMouseMotion and _mouse_mode!=0:used=drag(999,event.position,event.relative)
    if used:get_viewport().set_input_as_handled()

func release_all() -> void:
    move_finger=-1;look_finger=-1;_mouse_mode=0;stick=Vector2.ZERO
    if is_instance_valid(lab):_send({"move":[0,0],"turn":0,"playing":false})
    if overlay!=null:overlay.queue_redraw()

func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:release_all()

func _reset() -> void:
    release_all();lab.command({"op":"reset"});_paused=false
func _view() -> void:_send({"view":"overview" if lab.state["view"]=="third_person" else "third_person"})
func _roof() -> void:_send({"roof":not lab.state["roof"]})
func _shadows() -> void:_send({"shadows":not lab.state["shadows"]})
func _grip() -> void:_send({"grip":1.0 if lab.state["grip"]<.5 else 0.0})
func _farther() -> void:_send({"camera_distance":minf(7,lab.state["camera_distance"]+.4)})
func _closer() -> void:_send({"camera_distance":maxf(1.5,lab.state["camera_distance"]-.4)})
func _pause() -> void:
    release_all();_paused=true

func _process(delta: float) -> void:
    _ready_seconds+=delta
    if not lab.effect.failure.is_empty():status.text="No se pudo iniciar LIE: "+lab.effect.failure
    elif not lab.effect.gpu_ready:status.text="Preparando imagen…" if _ready_seconds<20 else "La GPU aún no responde. Cierra y vuelve a abrir la prueba."
    else:status.text="Pausa · toca el joystick para continuar" if _paused else "%.2f m recorridos · joystick izquierdo + cámara derecha"%lab.state["motion"]["travel"]
