extends Control
# Diagnostic lines only. No sphere mesh contributes pixels to the Lie image.
var lab: Node3D
func _draw() -> void:
    if lab==null or not lab.state["show_regions"] or lab.evaluated.is_empty():return
    var zones: Array=lab.effect.get("master")["joint_regions"].duplicate(true)
    zones.append_array(lab.effect.get("master")["facial_regions"])
    for eye in lab.effect.get("master")["eyes"]:zones.append({"center":eye,"radii":[.0172,.0172,.0172],"bone":2,"kind":"eyelid"})
    for zone in zones:
        var bone: int=int(zone.get("parent",zone["bone"])) if zone["kind"]=="joint" else 2
        var t: Transform3D=lab.evaluated["skins"][bone]
        var center:=Vector3(zone["center"][0],zone["center"][1],zone["center"][2])
        var radius:=Vector3(zone["radii"][0],zone["radii"][1],zone["radii"][2])
        var color:=Color(.20,.85,1,.55) if zone["kind"]=="joint" else Color(1,.70,.18,.7)
        for plane in range(3):
            var points:=PackedVector2Array();var visible: bool=true
            for i in range(49):
                var angle: float=i*TAU/48;var v:=Vector3.ZERO
                if plane==0:v=Vector3(cos(angle)*radius.x,sin(angle)*radius.y,0)
                elif plane==1:v=Vector3(cos(angle)*radius.x,0,sin(angle)*radius.z)
                else:v=Vector3(0,cos(angle)*radius.y,sin(angle)*radius.z)
                var p: Vector3=t*(center+v)-lab.camera.position;var z: float=p.dot(-lab.camera.basis.z)
                if z<=.01:visible=false;break
                var tangent: float=tan(deg_to_rad(lab.camera.fov)*.5)
                var uv:=Vector2((p.dot(lab.camera.basis.x)/z/tangent+1)*.5,(1-p.dot(lab.camera.basis.y)/z/tangent)*.5)
                points.append(lab.picture.position+uv*lab.picture.size)
            if visible:draw_polyline(points,color,1.2,true)
