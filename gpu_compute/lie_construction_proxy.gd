extends Node3D
## Invisible physics only. Capture banks, light ownership and render jobs stay intact.
var graph: Dictionary={}
var bodies: Array[StaticBody3D]=[]
var generation: int=0
const LAYER: int=1<<19

static func world_bounds(pose: Transform3D,size: Vector3) -> AABB:
    var half: Vector3=(pose.basis.x.abs()*size.x+pose.basis.y.abs()*size.y+pose.basis.z.abs()*size.z)*.5
    return AABB(pose.origin-half,half*2.)

static func build(recipe: Dictionary,entries: Array,catalogs: Dictionary,grouped: bool) -> Dictionary:
    var pieces: Array=[];var attachments: Array=[]
    for e in entries:
        if not catalogs.has(e.bank) or not catalogs[e.bank].masters.has(e.master):return {}
        var master: Dictionary=catalogs[e.bank].masters[e.master]
        var a: Array=e.basis_columns;var basis:=Basis(Vector3(a[0][0],a[0][1],a[0][2]),Vector3(a[1][0],a[1][1],a[1][2]),Vector3(a[2][0],a[2][1],a[2][2]))
        var scale:=Vector3(e.scale[0],e.scale[1],e.scale[2]);var center: Array=master.get("bounds_center",[0,0,0]);var dim: Array=master.bounds_size
        var pose:=Transform3D(basis,Vector3(e.origin[0],e.origin[1],e.origin[2])+basis*(Vector3(center[0],center[1],center[2])*scale))
        var size:=Vector3(dim[0],dim[1],dim[2])*scale
        if not size.is_finite() or minf(size.x,minf(size.y,size.z))<=0. or not basis.is_finite() or not basis.is_equal_approx(basis.orthonormalized()) or basis.determinant()<.9999:return {}
        var row: Dictionary={"id":e.id,"pose":pose,"size":size,"bounds":world_bounds(pose,size),"members":[attachments.size()]}
        pieces.append(row);attachments.append({"id":e.id,"owner_id":e.get("owner_id",""),"bank":e.bank,"master":e.master,"pose":pose,"size":size,"lod":e.lod})
    if pieces.is_empty():return {}
    var volumes: Array=pieces
    var approximation: String="one oriented source-bounds box per piece; geometric relief is visual only"
    if grouped and recipe.mode=="corner":
        var front: AABB;var side: AABB;var have_front: bool=false;var have_side: bool=false;var fm: Array=[];var sm: Array=[]
        for i in range(pieces.size()):
            var id: String=entries[i].id;var is_side: bool=int(entries[i].get("section",-1))==1 or id.contains("/backfill/1/") or id.contains("/head/1/") or id.contains("/bed/1/") or id.ends_with("/foundation/return") or id.contains("/elbow/") or id.contains("/corner-bed/")
            var box: AABB=pieces[i].bounds
            if is_side:
                side=side.merge(box) if have_side else box;have_side=true;sm.append(i)
            else:
                front=front.merge(box) if have_front else box;have_front=true;fm.append(i)
        if not have_front or not have_side:return {}
        var c: Array=recipe.opening.center;var s: Array=recipe.opening.clear_size
        var x0: float=c[0]-s[0]*.5;var x1: float=c[0]+s[0]*.5;var y0: float=c[1]-s[1]*.5;var y1: float=c[1]+s[1]*.5
        if x0<=front.position.x or x1>=front.end.x or y0<=front.position.y or y1>=front.end.y:return {}
        volumes=[]
        for spec in [["front/left",Vector3(front.position.x,front.position.y,front.position.z),Vector3(x0,front.end.y,front.end.z)],
                     ["front/right",Vector3(x1,front.position.y,front.position.z),front.end],
                     ["front/below",Vector3(x0,front.position.y,front.position.z),Vector3(x1,y0,front.end.z)],
                     ["front/above",Vector3(x0,y1,front.position.z),Vector3(x1,front.end.y,front.end.z)]]:
            volumes.append({"id":spec[0],"pose":Transform3D(Basis.IDENTITY,(spec[1]+spec[2])*.5),"size":spec[2]-spec[1],"bounds":AABB(spec[1],spec[2]-spec[1]),"members":fm})
        volumes.append({"id":"return","pose":Transform3D(Basis.IDENTITY,side.get_center()),"size":side.size,"bounds":side,"members":sm})
        approximation="authored wall envelope: fills small joints and relief; preserves declared clear window; not an exact union or visual occluder"
    return {"schema":"lie-invisible-wall-proxy/1","mode":recipe.mode,"grouped":grouped,"attachments":attachments,"volumes":volumes,"source_piece_count":pieces.size(),"body_count":volumes.size(),"equivalent_box_triangles":volumes.size()*12,"rendered_proxy_triangles":0,"approximation":approximation,"bank_bindings":recipe.bank_bindings.duplicate(true)}

func configure(next: Dictionary) -> bool:
    if next.is_empty():return false
    for body in bodies:body.collision_layer=0;body.collision_mask=0;body.queue_free()
    bodies.clear();graph=next;generation+=1
    for volume in graph.volumes:
        var body:=StaticBody3D.new();body.collision_layer=LAYER;body.collision_mask=0;body.transform=volume.pose;body.set_meta("proxy_id",volume.id)
        var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=volume.size;shape.margin=.0001;collider.shape=shape;body.add_child(collider);add_child(body);bodies.append(body)
    return true

static func camera_sweep(start: Vector3,finish: Vector3,volumes: Array,radius: float=.025) -> Dictionary:
    # Conservative swept sphere: expanded local boxes. Rounded corners may stop
    # slightly early; this routine never cuts through a box to shorten a path.
    var fraction: float=1.;var owner: String="";var overlap: bool=false
    for box in volumes:
        var inverse_pose: Transform3D=box.pose.affine_inverse();var a: Vector3=inverse_pose*start;var d: Vector3=inverse_pose*finish-a;var half: Vector3=box.size*.5+Vector3.ONE*radius
        var lo: float=0.;var hi: float=1.;var inside: bool=absf(a.x)<half.x and absf(a.y)<half.y and absf(a.z)<half.z
        var hit: bool=true
        for axis in range(3):
            if absf(d[axis])<1e-12:
                if a[axis]<-half[axis] or a[axis]>half[axis]:hit=false;break
            else:
                var t0: float=(-half[axis]-a[axis])/d[axis];var t1: float=(half[axis]-a[axis])/d[axis]
                lo=maxf(lo,minf(t0,t1));hi=minf(hi,maxf(t0,t1))
                if lo>hi:hit=false;break
        if hit and lo<fraction: fraction=lo;owner=box.id;overlap=inside
    var distance: float=start.distance_to(finish);var safe: float=maxf(0.,fraction-.002/maxf(distance,.000001)) if fraction<1. else 1.
    return {"blocked":fraction<1.,"fraction":safe,"position":start.lerp(finish,safe),"initial_overlap":overlap,"proxy":owner,"tested_volumes":volumes.size(),"radius_m":radius}

func ray(from: Vector3,to: Vector3) -> Dictionary:
    var query:=PhysicsRayQueryParameters3D.create(from,to,LAYER);return get_world_3d().direct_space_state.intersect_ray(query)

func sphere_motion(from: Vector3,to: Vector3,radius: float=.025) -> PackedFloat32Array:
    var query:=PhysicsShapeQueryParameters3D.new();var shape:=SphereShape3D.new();shape.radius=radius;query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from;query.collision_mask=LAYER;query.margin=.0001
    return get_world_3d().direct_space_state.cast_motion(query)

func metrics() -> Dictionary:
    return {"generation":generation,"grouped":graph.get("grouped",false),"source_pieces":graph.get("source_piece_count",0),"physics_bodies":bodies.size(),"physics_shapes":bodies.size(),"rendered_proxy_triangles":0,"equivalent_box_triangles":bodies.size()*12,"approximation":graph.get("approximation","")}
