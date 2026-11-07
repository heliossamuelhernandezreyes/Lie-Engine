extends "res://test_lie_scanned_masonry.gd"
func alpha_at(lab: Node,data: Dictionary,point: Vector3) -> float:
    var delta: Vector3=point-lab.camera.position;var depth: float=delta.dot(-lab.camera.basis.z);var tangent: float=tan(deg_to_rad(lab.camera.fov)*.5)
    var p: Vector2=Vector2((delta.dot(lab.camera.basis.x)/(depth*tangent)+1)*.5,(1-delta.dot(lab.camera.basis.y)/(depth*tangent))*.5)*data.output_size
    if p.x<0 or p.y<0 or p.x>=data.output_size or p.y>=data.output_size:return 0
    return data.color[(int(p.y)*data.output_size+int(p.x))*4+3]
func construction_checks(lab: Node) -> void:
    await super.construction_checks(lab)
    check(lab.effect.catalog.masters.size()==13,"thirteen resident masters")
    var assets: Array=["mortar_bed","mortar_head","mortar_corner","concrete_lintel","concrete_sill","plaster_panel","timber_beam","ceramic_tile"]
    for name in assets:
        check(lab.command({"op":"set_values","values":{"mode":"asset_"+name,"zoom":.85,"focus_x":0.,"focus_y":0.,"yaw":30.,"elevation":24.}}).ok,"asset source command")
        var data: Dictionary=await capture(lab);save(data,"kit-source-"+name);var covered: int=0;var finite: bool=true
        for i in range(0,data.color.size(),4):
            if data.color[i+3]>.01:covered+=1
            for c in range(4):finite=finite and is_finite(data.color[i+c])
        check(covered>500 and finite,"new source renders finite nonempty actual capture")
        check(data.asset_uploads==1,"kit reuses immutable shared bank")
        if name in ["concrete_lintel","timber_beam","plaster_panel"]:
            var dim: Array=lab.effect.catalog.masters[name].bounds_size;var opaque: int=0;var total: int=0
            for ix in range(16):
                for iy in range(3):
                    var point:=Vector3((float(ix)/15.-.5)*float(dim[0])*.75,float(dim[1])*.5+(float(iy)-1)*float(dim[1])*.18,float(dim[2])*.5)
                    total+=1
                    if alpha_at(lab,data,point)>.95:opaque+=1
            check(float(opaque)/total>=.98,"opaque source interiors have no sparse-coverage holes")
        rows["asset_"+name]={"coverage":covered,"samples":data.sample_invocations,"device":data.device}
    for mode in ["kit","frame","roof"]:
        check(lab.command({"op":"set_values","values":{"mode":mode,"zoom":1.0}}).ok,"hierarchical set command")
        var data: Dictionary=await capture(lab);save(data,"kit-set-"+mode);check(data.instances>1 and data.asset_uploads==1,"multiple referenced masters without extra bank upload")
    lab.command({"op":"set_values","values":{"mode":"wall","style":"varied","zoom":.45,"focus_x":-.75,"focus_y":0.,"yaw":10.,"elevation":10.}})
    var detail: Dictionary=await capture(lab);save(detail,"kit-joint-detail")
    var heads: int=0;var beds: int=0;var lintels: int=0;var sills: int=0
    for e in lab.recipe.instances:
        if e.master=="mortar_head":heads+=1
        if e.master=="mortar_bed":beds+=1
        if e.master=="concrete_lintel":lintels+=1
        if e.master=="concrete_sill":sills+=1
    check(heads>0 and beds>0 and lintels>0 and sills>0,"actual joints and opening sets integrated into masonry")
    lab.command({"op":"set_values","values":{"zoom":1.,"focus_x":0.,"yaw":0.,"elevation":0.}})
    var opening: Dictionary=await capture(lab);var hole: Dictionary=lab.recipe.openings[0];var size: Array=lab.recipe.brick_bounds_m;var px: float=float(size[0])+lab.recipe.joint_m;var py: float=float(size[1])+lab.recipe.joint_m;var clear: bool=true
    for ix in range(9):
        for iy in range(7):
            var point:=Vector3((hole.column+.10+float(ix)/8.*(hole.columns-.20))*px-float(lab.recipe.bounds_m[0])*.5,(hole.row+.30+float(iy)/6.*(hole.rows-.60))*py,0)
            clear=clear and alpha_at(lab,opening,point)<.01
    check(clear,"lintel and sill supports never spill into opening interior")
    var revision: int=lab.revision
    check(not lab.command({"op":"set_values","values":{"zoom":true}}).ok and lab.revision==revision,"bool zoom rejected")
    check(not lab.command({"op":"set_values","values":{"mode":"asset_glass"}}).ok and lab.revision==revision,"unavailable asset rejected")
    lab.command({"op":"set_values","values":{"mode":"house","zoom":1.,"focus_x":0.,"focus_y":0.,"yaw":30.,"elevation":24.}})
