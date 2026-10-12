"""Connected orbital patches and a globe-following blink corrective.

The source boundary is reused, including its UVs and skinning weights. The
closed scan is an authoring reference, not a second overlapping visible layer.
"""
from collections import Counter, defaultdict
import math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from lie20_prepare_blender import barycentric, blender


def author_lids(original, rig, rest, weights, uvs):
    original.data.calc_loop_triangles()
    source_faces = [tuple(t.vertices) for t in original.data.loop_triangles]
    bvh = BVHTree.FromPolygons(rest, source_faces, all_triangles=True)
    # glTF duplicates vertices at UV seams. Weld geometry while preserving
    # the original UVs per face corner in the authoring mesh.
    representative, canonical = {}, []
    for i,p in enumerate(rest):
        canonical.append(representative.setdefault(tuple(p),i))
    old_faces = [tuple(canonical[k] for k in tri) for tri in source_faces]
    source_uvs = {tri: [Vector(uvs[k]) for k in source]
                  for tri,source in zip(old_faces,source_faces)}
    anchors = []
    for x in [-.037, .034]:
        hit, _, _, _ = bvh.ray_cast(Vector((x, .301, .4)), Vector((0, 0, -1)), 1)
        if hit is None:
            raise ValueError('Missing orbital landmark')
        # Recess the eye behind the scanned closed lid instead of inflating
        # the surrounding skin to accommodate a protruding sphere.
        anchors.append(Vector((x, .301, hit.z - .0152)))
    removed, kept = [], []
    for tri in old_faces:
        center = sum((rest[k] for k in tri), Vector()) / 3
        cut = any(((center.x-a.x)/.0205)**2 + ((center.y-a.y)/.013)**2 < 1
                  and center.z > .035 for a in anchors)
        (removed if cut else kept).append(tri)
    # The scan folds back inside its closed sockets. The projected cut can
    # strand small pieces of that old lid; retain only the connected bust.
    graph = defaultdict(set)
    for tri in kept:
        for k in tri:
            graph[k].update(tri)
    unused, components = set(graph), []
    while unused:
        start=min(unused); pending=[start]; component={start}
        while pending:
            for k in graph[pending.pop()]-component:
                component.add(k); pending.append(k)
        unused.difference_update(component); components.append(component)
    body = max(components,key=len)
    removed.extend(tri for tri in kept if tri[0] not in body)
    kept = [tri for tri in kept if tri[0] in body]
    # A centroid cut can touch itself at a source vertex. Include the whole
    # incident fan there so each orbital boundary remains a simple loop.
    for _ in range(30):
        edges = Counter(tuple(sorted((tri[i], tri[(i+1)%3])))
                        for tri in removed for i in range(3))
        boundary = [edge for edge, count in edges.items() if count == 1]
        neighbors = defaultdict(list)
        for i, j in boundary:
            neighbors[i].append(j); neighbors[j].append(i)
        pinched = {k for k,n in neighbors.items() if len(n) != 2}
        if not pinched:
            break
        additions = [tri for tri in kept if any(k in pinched for k in tri)]
        removed.extend(additions)
        kept = [tri for tri in kept if not any(k in pinched for k in tri)]
    if any(len(n) != 2 for n in neighbors.values()):
        raise ValueError('Orbital cut must have simple connected boundaries')
    loops, unused = [], set(neighbors)
    while unused:
        start = min(unused); loop = [start]; previous = None; current = start
        while True:
            following = next(k for k in neighbors[current] if k != previous)
            if following == start:
                break
            loop.append(following); previous, current = current, following
        unused.difference_update(loop)
        area = sum(rest[loop[i]].x*rest[loop[(i+1)%len(loop)]].y
                   - rest[loop[(i+1)%len(loop)]].x*rest[loop[i]].y for i in range(len(loop)))
        loops.append(loop if area > 0 else loop[::-1])
    if len(loops) != 2:
        raise ValueError('Expected exactly two orbital boundaries')
    loops.sort(key=lambda loop: sum(rest[k].x for k in loop)/len(loop))
    closed = [Vector() for _ in rest]
    corrective = [Vector() for _ in rest]
    regions = [0]*len(rest)

    def append(p, uv, weight=1., region=0, end=None, middle=None):
        index = len(rest); rest.append(p); uvs.append(tuple(uv)); weights.append(weight)
        closed.append(Vector() if end is None else end-p)
        corrective.append(Vector() if middle is None else middle-(p+end)*.5)
        regions.append(region)
        return index

    # Subdivide the shared boundary edges and retriangulate their source
    # neighbors. Both sides then use identical vertex IDs; no overlapping ring.
    split, dense_loops = {}, []
    for loop in loops:
        dense = []
        for i, first in enumerate(loop):
            last = loop[(i+1)%len(loop)]; chain = [first]
            steps = max(1, math.ceil((rest[last]-rest[first]).length/.00085))
            for j in range(1, steps):
                t = j/steps
                chain.append(append(rest[first].lerp(rest[last],t),
                                    Vector(uvs[first]).lerp(Vector(uvs[last]),t),
                                    weights[first]*(1-t)+weights[last]*t))
            split[(first,last)] = chain+[last]
            split[(last,first)] = (chain+[last])[::-1]
            dense.extend(chain)
        dense_loops.append(dense)
    faces, face_uvs = [], []
    for tri in kept:
        polygon, polygon_uvs = [], []
        corner_uvs = source_uvs[tri]
        for i, first in enumerate(tri):
            chain = split.get((first,tri[(i+1)%3]),[first,tri[(i+1)%3]])
            polygon.extend(chain[:-1])
            polygon_uvs.extend(corner_uvs[i].lerp(corner_uvs[(i+1)%3],j/(len(chain)-1))
                               for j in range(len(chain)-1))
        if len(polygon) == 3:
            faces.append(tri)
            face_uvs.append(corner_uvs)
        else:
            uv_center = sum(corner_uvs,Vector((0,0)))/3
            center = append(sum((rest[k] for k in tri),Vector())/3,
                            uv_center,
                            sum(weights[k] for k in tri)/3)
            faces.extend((center,polygon[i],polygon[(i+1)%len(polygon)]) for i in range(len(polygon)))
            face_uvs.extend((uv_center,polygon_uvs[i],polygon_uvs[(i+1)%len(polygon)])
                            for i in range(len(polygon)))

    def scan(x,y):
        hit, _, ti, _ = bvh.ray_cast(Vector((x,y,.4)),Vector((0,0,-1)),1)
        if hit is None:
            raise ValueError('Missing orbital surface')
        bary = barycentric(hit,*(rest[k] for k in source_faces[ti]))
        uv = sum((Vector(uvs[k])*w for k,w in zip(source_faces[ti],bary)),Vector((0,0)))
        return hit, uv

    rows = 18
    for side, (a, boundary_loop) in enumerate(zip(anchors,dense_loops)):
        rings = []
        for row in range(rows):
            t = row/rows; ring = []
            for outer_id in boundary_loop:
                outer = rest[outer_id]
                phi = math.atan2((outer.y-a.y)/.013,(outer.x-a.x)/.0205)
                cs, sn = math.cos(phi), math.sin(phi)
                x = .0114*cs; shape = abs(sn)**1.3
                seam_y = .0006*cs - .0009*(1-cs*cs)
                open_y = .0006*cs + (.0046 if sn >= 0 else -.0036)*shape
                # A submillimeter contact band accommodates distinct upper
                # and lower corner tessellations, including their canthi.
                shut_y = seam_y + (-.00015 if sn >= 0 else .00015)*max(shape,.12)
                rho = math.sqrt(.01235**2-x*x)
                start_angle = math.asin(open_y/rho); end_angle = math.asin(shut_y/rho)

                def position(blink):
                    angle = start_angle*(1-blink)+end_angle*blink
                    rim = a+Vector((x,rho*math.sin(angle),rho*math.cos(angle)))
                    p = rim.lerp(outer,t)
                    reference, _ = scan(p.x,p.y)
                    # Recover the scanned skin surface at full closure. The
                    # moving rim peels back toward the globe while opening;
                    # its spherical offset must not survive as a closed bulge.
                    p.z = reference.z+(rim.z-reference.z)*(1-t)**3*(1-blink)
                    # A modest upper crease unfolds as the lid closes.
                    if sn > 0:
                        p.z -= .00035*shape*math.exp(-((t-.28)/.07)**2)*(1-blink)
                    sphere = .0121**2-(p.x-a.x)**2-(p.y-a.y)**2
                    if sphere > 0:
                        p.z = max(p.z,a.z+math.sqrt(sphere))
                    return p

                p, middle, end = (position(b) for b in [0,.5,1])
                # UVs follow the material's closed reference, so the original
                # closed-eye crease is not projected onto the open lower lid.
                _, uv = scan(end.x,end.y)
                region = side+1
                ring.append(append(p,uv,region=region,end=end,middle=middle))
            rings.append(ring)
        rings.append(boundary_loop)
        for inner, outer in zip(rings,rings[1:]):
            for i in range(len(inner)):
                j = (i+1)%len(inner)
                new_faces = [(inner[i],outer[j],inner[j]),(inner[i],outer[i],outer[j])]
                faces.extend(new_faces)
                face_uvs.extend([uvs[k] for k in tri] for tri in new_faces)

    mesh = bpy.data.meshes.new('LieConnectedOrbitalSurface')
    mesh.from_pydata([blender(p) for p in rest],[],faces); mesh.update()
    face = bpy.data.objects.new('LieHumanOpenEyes',mesh)
    bpy.context.collection.objects.link(face)
    layer = mesh.uv_layers.new(name='CaptureUV')
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop,uv in zip(poly.loop_indices,face_uvs[poly.index]):
            layer.data[loop].uv = uv
    for material in original.data.materials:
        mesh.materials.append(material)
    lid_material = original.data.materials[0].copy()
    lid_material.name = 'LieLidSkinWithoutProjectedScanNormal'
    bsdf = lid_material.node_tree.nodes.get('Principled BSDF')
    for link in list(bsdf.inputs['Normal'].links):
        lid_material.node_tree.links.remove(link)
    mesh.materials.append(lid_material)
    for poly in mesh.polygons:
        if any(regions[k]>0 for k in poly.vertices):
            poly.material_index = 1
    face.shape_key_add(name='Basis')
    end_key = face.shape_key_add(name='blink')
    arc_key = face.shape_key_add(name='blink_arc')
    for i,p in enumerate(rest):
        end_key.data[i].co = blender(p+closed[i])
        arc_key.data[i].co = blender(p+corrective[i])
    for name, head in [('Neck',False),('Head',True)]:
        group = face.vertex_groups.new(name=name)
        for i,w in enumerate(weights):
            group.add([i],w if head else 1-w,'REPLACE')
    face.modifiers.new('LieInvisibleSkinning','ARMATURE').object = rig
    original.hide_render=True; original.hide_set(True)
    face['orbital_boundary_vertices'] = [k for loop in dense_loops for k in loop]
    face['orbital_boundary_count'] = sum(map(len,dense_loops))
    return face,anchors,closed,corrective,regions,len(removed)


def set_blink(face,value):
    keys = face.data.shape_keys.key_blocks
    keys['blink'].value = value
    keys['blink_arc'].value = 4*value*(1-value)
    bpy.context.view_layer.update()
