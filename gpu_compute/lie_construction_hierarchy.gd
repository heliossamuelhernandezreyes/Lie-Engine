extends RefCounted
## Camera-only broad phase over source bounds, never collision envelopes.
## A leaf is a complete original job. Indices and ownership remain unchanged.
static func build(attachments: Array) -> Dictionary:
    var root: Dictionary={"id":"house","children":[],"members":PackedInt32Array()};var walls: Dictionary={};var segments: Dictionary={}
    for i in range(attachments.size()):
        var item: Dictionary=attachments[i];var id: String=item.id
        var wall: String="return" if id.contains("/brick/1/") or id.contains("/backfill/1/") or id.contains("/head/1/") or id.contains("/bed/1/") or id.ends_with("/foundation/return") or id.contains("/elbow/") or id.contains("/corner-bed/") else "front"
        var bounds: AABB=item.bounds
        # SourceLimits accepts 2 micrometres in local space. Include scaled
        # tolerance and an extra floating-point guard in the broad phase.
        bounds=bounds.grow(float(item.get("guard_m",.0001)))
        var center: Vector3=bounds.get_center();var along: float=center.z if wall=="return" else center.x
        var segment: String=wall+"/"+str(floori(along/.4))+"/"+str(floori(center.y/.25))
        if not walls.has(wall):walls[wall]={"id":wall,"children":[],"members":PackedInt32Array()};root.children.append(walls[wall])
        if not segments.has(segment):segments[segment]={"id":segment,"children":[],"members":PackedInt32Array()};walls[wall].children.append(segments[segment])
        var leaf: Dictionary={"id":id,"bounds":bounds,"children":[],"members":PackedInt32Array([i])}
        segments[segment].children.append(leaf)
    _aggregate(root)
    return {"root":root,"leaves":attachments.size(),"walls":walls.size(),"segments":segments.size(),"nodes":1+walls.size()+segments.size()+attachments.size()}

static func _aggregate(node: Dictionary) -> void:
    if node.children.is_empty():return
    var first: bool=true
    for child in node.children:
        _aggregate(child)
        node.bounds=child.bounds if first else node.bounds.merge(child.bounds);first=false
        node.members.append_array(child.members)

static func _classify(bounds: AABB,eye: Vector3,right: Vector3,up: Vector3,forward: Vector3,tangent: float) -> int:
    var d: Vector3=bounds.get_center()-eye;var h: Vector3=bounds.size*.5;var contained: bool=true
    # The custom reconstruction uses a square camera, independent of UI size.
    for n in [forward*tangent+right,forward*tangent-right,forward*tangent+up,forward*tangent-up]:
        var center: float=d.dot(n);var radius: float=h.dot(n.abs())
        if center+radius<-.0001:return -1
        if center-radius<.0001:contained=false
    var z: float=d.dot(forward);var extent: float=h.dot(forward.abs())
    if z+extent<.0005 or z-extent>100.:return -1
    return 1 if contained and z-extent>.0005 and z+extent<100. else 0

static func select(tree: Dictionary,pose: Transform3D,fov: float,internal_size: int) -> Dictionary:
    var mask:=PackedByteArray();mask.resize(tree.leaves);mask.fill(1)
    var result: Dictionary={"mask":mask,"visited_nodes":0,"rejected_nodes":0,"accepted_nodes":0,"selected_jobs":tree.leaves,"total_jobs":tree.leaves}
    # One extra pixel plus source-bound guards keeps edge cases conservative.
    var tangent: float=tan(deg_to_rad(fov)*.5)*(1.+2./maxi(1,internal_size))
    _visit(tree.root,pose,tangent,result)
    return result

static func _visit(node: Dictionary,pose: Transform3D,tangent: float,result: Dictionary) -> void:
    result.visited_nodes+=1
    var classification: int=_classify(node.bounds,pose.origin,pose.basis.x,pose.basis.y,-pose.basis.z,tangent)
    if classification<0:
        result.rejected_nodes+=1
        for i in node.members:result.mask[i]=0;result.selected_jobs-=1
        return
    if classification>0:result.accepted_nodes+=1;return
    for child in node.children:_visit(child,pose,tangent,result)
