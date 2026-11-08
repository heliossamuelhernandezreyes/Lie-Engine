extends RefCounted
## Scene adapter only. The common quality field owns transport/scattering.
const Model=preload("res://lie11_model.gd")
static func transpose_csr(gather: PackedByteArray) -> PackedByteArray:
    # This is an index transpose of the SAME edge weights. Reusing the dense
    # source-factor encoder here incorrectly applies its row-energy test to
    # transposed rows; unequal patch areas can make those sums exceed one.
    # The common transport validates exact transpose ownership and handles its
    # own source/area budgets. Never renormalize or silently remove an edge.
    if gather.size()<20:return PackedByteArray()
    var n: int=gather.decode_u32(0);var m: int=gather.decode_u32(4)
    if n<1 or n>512 or gather.size()!=4*(n+5)+8*m:return PackedByteArray()
    var rows: Array=[]
    for i in range(n):rows.append(PackedByteArray())
    var begin: int=4*(n+5)
    for receiver in range(n):
        for edge in range(gather.decode_u32(16+receiver*4),gather.decode_u32(20+receiver*4)):
            var at: int=begin+edge*8;var source: int=gather.decode_u32(at)
            if source>=n:return PackedByteArray()
            rows[source].append_array(PackedInt32Array([receiver]).to_byte_array());rows[source].append_array(gather.slice(at+4,at+8))
    var result:=PackedInt32Array([n,m,4,n+5]).to_byte_array();var prefix: int=0;result.append_array(PackedInt32Array([0]).to_byte_array())
    for row in rows:prefix+=row.size()/8;result.append_array(PackedInt32Array([prefix]).to_byte_array())
    for row in rows:result.append_array(row)
    return result
static func verified_bytes(path: String,spec: Dictionary) -> PackedByteArray:
    var name: String=spec.get("file","")
    if name.get_file()!=name or name.is_empty() or FileAccess.get_sha256(path+name)!=spec.get("sha256"):return PackedByteArray()
    var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path+name)
    return bytes if bytes.size()==int(spec.get("bytes",-1)) else PackedByteArray()
static func load_corner(root: String,recipe_path: String,identity: String) -> Dictionary:
    var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"field.json"))
    if not proof is Dictionary or proof.get("schema")!="lie-construction-field/1" or proof.get("scene_identity")!=identity or FileAccess.get_sha256(recipe_path)!=proof.get("recipe_sha256"):return {}
    if FileAccess.get_sha256(root+"model.json")!=proof.get("model_sha256") or FileAccess.get_sha256(root+"mapping.bin")!=proof.get("mapping_sha256"):return {}
    var model: Variant=JSON.parse_string(FileAccess.get_file_as_string(root+"model.json"))
    if not model is Dictionary or not Model.valid(model):return {}
    var sources: Dictionary={}
    for key in ["factors","outgoing","optics","boxes","planes","owners"]:
        var bytes: PackedByteArray=verified_bytes(root,proof.get("sources",{}).get(key,{}))
        if bytes.is_empty():return {}
        sources[key]=bytes
    return {"model":model,"sources":sources,"mapping":FileAccess.get_file_as_bytes(root+"mapping.bin"),"proof":proof}
static func small_scene(entries: Array,materials: Dictionary) -> Dictionary:
    var patches: Array=[];var owners:=PackedInt32Array();var groups:=PackedInt32Array();var spans:=PackedInt32Array();var boxes: Array=[];var optical:=PackedFloat32Array()
    for owner in range(entries.size()):
        var e: Dictionary=entries[owner];var key: String=e.bank+"/"+e.master
        if not materials.has(key):return {}
        var source: Dictionary=materials[key];var low: Vector3=Model.vector(source.bounds_low);var high: Vector3=Model.vector(source.bounds_high);var center: Vector3=(low+high)/2;var extent: Vector3=high-low;var columns: Array=e.basis_columns;var basis:=Basis(Model.vector(columns[0]),Model.vector(columns[1]),Model.vector(columns[2])).scaled_local(Model.vector(e.scale));var normal_basis: Basis=basis.inverse().transposed();var origin: Vector3=Model.vector(e.origin);var wc: Vector3=basis*center+origin;var half: Vector3=(basis.x.abs()*extent.x+basis.y.abs()*extent.y+basis.z.abs()*extent.z)*.5;boxes.append([[wc.x-half.x,wc.y-half.y,wc.z-half.z],[wc.x+half.x,wc.y+half.y,wc.z+half.z]])
        for face in range(6):
            var axis: int=face/2;var sign_value: float=1. if face%2==0 else -1.;var other: Array=[]
            for k in range(3):
                if k!=axis:other.append(k)
            var u: int=other[0];var v: int=other[1];var nu: int=clampi(ceili(extent[u]*e.scale[u]/.35),1,8);var nv: int=clampi(ceili(extent[v]*e.scale[v]/.35),1,8);var first: int=patches.size();var count: int=nu*nv;var normal: Vector3=(normal_basis[axis]*sign_value).normalized();var area: float=extent[u]*e.scale[u]*extent[v]*e.scale[v]/count;var mat: Dictionary=source.faces[face];var rgb: Vector3=Model.vector(mat.albedo)*Model.vector(e.tint);var rough: float=clampf(mat.roughness+e.roughness_delta,.2,.95);spans.append_array(PackedInt32Array([first,count]))
            for row in range(nv):
                for col in range(nu):
                    var point: Vector3=center;point[axis]=high[axis] if sign_value>0 else low[axis];point[u]=low[u]+(col+.5)*extent[u]/nu;point[v]=low[v]+(row+.5)*extent[v]/nv;point=basis*point+origin+normal*.0003
                    patches.append({"position":[point.x,point.y,point.z],"normal":[normal.x,normal.y,normal.z],"area":area,"gray_mean":1.,"material":"opaque"});owners.append(owner);groups.append_array(PackedInt32Array([first,count]));optical.append_array(PackedFloat32Array([clampf(rgb.x,0,1),clampf(rgb.y,0,1),clampf(rgb.z,0,1),rough,0,0,1.5,0,0,0,0,0,normal.x,normal.y,normal.z,0]))
    var n: int=patches.size()
    if n<1 or n>512:return {}
    var visibility: Array=[];visibility.resize(n*n);visibility.fill(0)
    for i in range(n):
        for j in range(i+1,n):
            if owners[i]==owners[j]:continue
            var a: Vector3=Model.vector(patches[i].position);var b: Vector3=Model.vector(patches[j].position);var d: Vector3=b-a
            if Model.vector(patches[i].normal).dot(d)<=0 or Model.vector(patches[j].normal).dot(-d)<=0:continue
            var clear: bool=true
            for k in range(boxes.size()):
                if k!=owners[i] and k!=owners[j] and Model.blocked(a,b,[boxes[k]]):clear=false;break
            if clear:visibility[i*n+j]=1;visibility[j*n+i]=1
    var model: Dictionary={"schema":1,"patches":patches,"materials":{"opaque":{"tint_linear":[1.,1.,1.],"absorption_code":0,"radius_scale":1.}},"lights":[{"position":[0.,2.,2.],"power_rgb":[40.,32.,24.],"radius":12.}],"bounces":2,"blockers":[],"mesh_visibility":visibility,"factor_normalization":"symmetric_local","field_quality":{"angular_sectors":6,"area_budget":true,"reference_area":1.,"roughness_split":.5}}
    var dense: PackedByteArray=Model.factor_bytes(model);var gather: PackedByteArray=Model.sparse_factor_bytes(dense,n);var outgoing: PackedByteArray=transpose_csr(gather)
    if gather.is_empty() or outgoing.is_empty():return {}
    var box_packet:=PackedInt32Array([boxes.size(),0,0,0]).to_byte_array();var planes:=PackedFloat32Array()
    for box in boxes:box_packet.append_array(PackedFloat32Array([box[0][0],box[0][1],box[0][2],0,box[1][0],box[1][1],box[1][2],0]).to_byte_array());planes.append_array(PackedFloat32Array([0,0,1,1000000.]))
    var optics:=PackedInt32Array([1,n,1,1]).to_byte_array();optics.append_array(optical.to_byte_array());var mapping:=PackedInt32Array([entries.size(),n,1,0]).to_byte_array();mapping.append_array(spans.to_byte_array());mapping.append_array(groups.to_byte_array())
    return {"model":model,"sources":{"factors":gather,"outgoing":outgoing,"optics":optics,"owners":owners.to_byte_array(),"planes":planes.to_byte_array(),"boxes":box_packet},"mapping":mapping,"proof":{"nodes":n,"visibility":"conservative profile AABBs; geometry edits create a new immutable field"}}
