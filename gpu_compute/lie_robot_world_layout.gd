extends RefCounted
## One declared layout owns captured instances and their exact collision surfaces.
const Building=preload("res://lie28_building_assembly.gd")
const Rig=preload("res://lie26_rig.gd")
const HOUSE_SCALE=1.2
static func instances(roof: bool) -> Array:
    var parts: Array=[]
    for p in Building.build({"mode":"house","roof":roof},{}):
        var pose: Transform3D=p["pose"]
        parts.append({"master":"house_"+p["master"],"pose":Transform3D(pose.basis.scaled(Vector3.ONE*HOUSE_SCALE),pose.origin*HOUSE_SCALE),"bone":-1,"curve":-1,"radius_scale":1.0,"emission":0.0})
    for x in [-3.0,3.0]:
        for z in [-3.0,3.0]:parts.append({"master":"ground","pose":Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,2)),Vector3(x,-.02,z)),"bone":-1,"curve":-1,"radius_scale":1.0,"emission":0.0})
    return parts
static func collisions(parent: Node,parts: Array,catalog: Dictionary) -> Node3D:
    var root:=Node3D.new();root.name="AuthoredSurfaceCollisions";parent.add_child(root)
    var meta: Dictionary=catalog["collision"];var file: String="res://captures/robot_world/"+meta["file"]
    var raw: PackedByteArray=FileAccess.get_file_as_bytes(file)
    if raw.size()!=meta["bytes"] or FileAccess.get_sha256(file)!=meta["sha256"]:push_error("World collision source integrity");return root
    var data: PackedFloat32Array=raw.to_float32_array();var cache: Dictionary={}
    for p in parts:
        var pose: Transform3D=p["pose"];var scale: Vector3=pose.basis.get_scale();var key: String=p["master"]+str(scale)
        if not cache.has(key):
            var span: Dictionary=meta["faces"][p["master"]];var vertices:=PackedVector3Array()
            for i in range(span["start"],span["start"]+span["count"]):vertices.append(Vector3(data[i*3],data[i*3+1],data[i*3+2])*scale)
            var shape:=ConcavePolygonShape3D.new();shape.backface_collision=true;shape.set_faces(vertices);cache[key]=shape
        var body:=StaticBody3D.new();body.name=p["master"];body.collision_layer=1;body.collision_mask=2;body.transform=Transform3D(pose.basis.orthonormalized(),pose.origin)
        var collider:=CollisionShape3D.new();collider.shape=cache[key];body.add_child(collider);root.add_child(body)
    # Bounded laboratory courtyard; these four guards have no material capture.
    for side in [Vector3(-5.75,2,0),Vector3(5.75,2,0),Vector3(0,2,-5.75),Vector3(0,2,5.75)]:
        var body:=StaticBody3D.new();body.name="CourtyardLimit";body.position=side;body.collision_layer=4;body.collision_mask=2
        var shape:=BoxShape3D.new();shape.size=Vector3(.10,4,12) if side.x!=0 else Vector3(12,4,.10)
        var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);root.add_child(body)
    return root
