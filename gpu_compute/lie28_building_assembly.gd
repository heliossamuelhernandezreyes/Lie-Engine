extends RefCounted
## Shared construction layout for the workshop and the robot exploration scene.
static func add(list: Array,master: String,origin: Vector3,yaw: float=0,scale: Vector3=Vector3.ONE) -> void:
    list.append({"master":master,"pose":Transform3D(Basis(Vector3.UP,yaw).scaled_local(scale),origin)})
static func build(state: Dictionary,catalog: Dictionary) -> Array:
    var list: Array=[]
    match state["mode"]:
        "master":add(list,state["master"],Vector3.ZERO)
        "fragments":
            for i in range(4):
                var master: String="fragment_%d"%i;var offset: Array=catalog["masters"][master]["origin_offset"];var center:=Vector3(offset[0],offset[1],offset[2])
                var spread:=Vector3(-.075 if i%2==0 else .075,-.085 if i<2 else .085,.015 if i%2==0 else -.015)
                add(list,master,center+spread*state["explode"])
        "wall":
            for row in range(3):
                for col in range(3):
                    var master: String="wall"
                    if col==0:master="door_head" if row==2 else "door_base"
                    elif col==2 and row==1:master="window_wall"
                    add(list,master,Vector3(col-1,row*.8+.4,0))
            for col in range(3):add(list,"slab",Vector3(col-1,-.05,0))
        "house":
            for row in range(3):
                for col in range(4):
                    var master: String="wall"
                    if col==1:master="door_head" if row==2 else "door_base"
                    elif col==3 and row==1:master="window_wall"
                    add(list,master,Vector3(col-1.5,row*.8+.4,1.56));add(list,"window_wall" if col==1 and row==1 else "wall",Vector3(col-1.5,row*.8+.4,-1.56),PI)
                for col in range(3):
                    var master: String="window_wall" if col==1 and row==1 else "wall"
                    add(list,master,Vector3(2.06,row*.8+.4,1-col),PI/2);add(list,master,Vector3(-2.06,row*.8+.4,col-1),-PI/2)
                for corner in [[-2.12,1.62,0],[2.12,1.62,PI/2],[2.12,-1.62,PI],[-2.12,-1.62,-PI/2]]:add(list,"corner",Vector3(corner[0],row*.8+.4,corner[1]),corner[2])
            for x in range(4):
                for z in range(3):
                    add(list,"slab",Vector3(x-1.5,-.05,z-1))
                    if state["roof"]:add(list,"slab",Vector3((x-1.5)*1.06,2.45,(z-1)*1.08),0,Vector3(1.06,1,1.08))
            add(list,"lintel",Vector3(-.5,1.96,1.56))
    return list

