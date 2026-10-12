#!/usr/bin/env python3
"""Dimensioned building masters; neutral RGB/roughness captures for Lie.

Blender --background --python tools/lie28_prepare_blender.py -- --materials DIR
Downloaded maps are separate, attributed CC0 resources, never source code.
Coordinates are metres, Y up; all fragment origins record their parent offset.
"""
import argparse
from array import array
import hashlib
import json
import math
import os
from pathlib import Path
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lie22_prepare_blender as base

ROOT = Path(__file__).resolve().parents[1] / 'gpu_compute'
BRICK = (.24, .07, .12)
PITCH = (.25, .08)
MODULE = (1., .8, .12)
# Inner patches of individual bricks in the source photograph, excluding joints.
# UVs use bottom-left origin, while these measured bounds use top-left pixels.
CROPS = [(315, 12, 545, 53), (405, 80, 635, 116),
         (395, 271, 539, 308), (217, 336, 365, 371)]
MAPS = {}
MATERIALS = {}


def atomic(path, data):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(data)
    os.replace(temporary, path)


def box(name, size, zone=5):
    pts, faces, zones, cells = [], [], [], []
    base.append_box(pts, faces, zones, cells, (0, 0, 0), size, zone)
    return base.mesh_object(name, pts, faces, zones, cells)


def bevel(obj, width=.0015):
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new('Small physical edge bevel', 'BEVEL')
    modifier.width = width
    modifier.segments = 2
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for p in obj.data.polygons:
        obj.data.attributes['lie_zone'].data[p.index].value = p.material_index
    return obj


def split_rect(rect, hole):
    """Disjoint rectangles around an opening, including partially cut bricks."""
    x0, x1, y0, y1 = rect
    if hole is None:
        return [rect]
    a, b, c, d = hole
    a, b, c, d = max(x0, a), min(x1, b), max(y0, c), min(y1, d)
    if a >= b or c >= d:
        return [rect]
    return [(x0, a, y0, y1), (b, x1, y0, y1),
            (a, b, y0, c), (a, b, d, y1)]


def wall(name, hole=None):
    pts, faces, zones, cells = [], [], [], []
    # Recessed mortar is split around exactly the same opening as the bricks.
    for x0, x1, y0, y1 in split_rect((-.5, .5, -.4, .4), hole):
        if x1-x0 > 1e-6 and y1-y0 > 1e-6:
            base.append_box(pts, faces, zones, cells,
                            ((x0+x1)/2, (y0+y1)/2, 0), (x1-x0, y1-y0, .108), 4)
    brick_cells = {}
    for row in range(10):
        offset = .125 if row % 2 else 0
        for col in range(-1, 5):
            cx = -.375 + col*.25 + offset
            x0, x1 = max(-.5, cx-.12), min(.5, cx+.12)
            y0, y1 = -.4+row*.08+.005, -.4+(row+1)*.08-.005
            if x1 <= x0:
                continue
            cell = row*6+col+1
            brick_cells[cell] = ((cx, (y0+y1)/2, 0), BRICK)
            for a, b, c, d in split_rect((x0, x1, y0, y1), hole):
                if b-a > 1e-6 and d-c > 1e-6:
                    base.append_box(pts, faces, zones, cells,
                                    ((a+b)/2, (c+d)/2, 0), (b-a, d-c, .12), 3, cell)
    obj = base.mesh_object(name, pts, faces, zones, cells)
    obj['brick_cells'] = json.dumps(brick_cells)
    obj['opening'] = json.dumps(hole)
    obj['grid_size_m'] = list(MODULE)
    return obj


def cinder_block():
    pts, faces, zones, cells = [], [], [], []
    # Two real vertical holes; side rails and three cross webs.
    for z in [-.085, .085]:
        base.append_box(pts, faces, zones, cells, (0, 0, z), (.39, .19, .03), 5)
    for x in [-.18, 0, .18]:
        base.append_box(pts, faces, zones, cells, (x, 0, 0), (.03, .19, .14), 5)
    return base.mesh_object('hollow_block', pts, faces, zones, cells)


def corner():
    pts, faces, zones, cells = [], [], [], []
    # Nonoverlapping L strips. Anchor is at the outside corner, below midheight.
    base.append_box(pts, faces, zones, cells, (.125, 0, -.06), (.25, .8, .12), 5)
    base.append_box(pts, faces, zones, cells, (.06, 0, -.185), (.12, .8, .13), 5)
    return base.mesh_object('corner', pts, faces, zones, cells)


def fracture(parent):
    seeds = [Vector((-.055, -.015, -.014)), Vector((.055, -.017, .008)),
             Vector((-.065, .015, .011)), Vector((.063, .016, -.009))]
    result = []
    for i, seed in enumerate(seeds):
        mesh = parent.data.copy()
        obj = bpy.data.objects.new('fragment_%d' % i, mesh)
        bpy.context.collection.objects.link(obj)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        for other in seeds:
            if other == seed:
                continue
            cut = bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                        plane_co=(other+seed)*.5, plane_no=(other-seed).normalized(),
                        dist=1e-7, clear_outer=True, clear_inner=False)
            border = [e for e in cut['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
            if border:
                for face in bmesh.ops.holes_fill(bm, edges=border, sides=0)['faces']:
                    face.material_index = 6
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        for face in mesh.polygons:
            mesh.attributes['lie_zone'].data[face.index].value = face.material_index
        result.append(obj)
    return result


def load_materials(directory):
    for asset in ['factory_brick', 'concrete']:
        channels = {}
        for kind, suffix in [('Diffuse', 'diff'), ('Rough', 'rough')]:
            path = directory / f'{asset}_{suffix}_1k.jpg'
            image = bpy.data.images.load(str(path))
            image.colorspace_settings.name = 'sRGB' if kind == 'Diffuse' else 'Non-Color'
            pixels = np.empty(len(image.pixels), dtype=np.float32)
            image.pixels.foreach_get(pixels)
            channels[kind] = (image, pixels.reshape(image.size[1], image.size[0], 4))
        MAPS[asset] = channels
    for zone in range(8):
        material = bpy.data.materials.new('Clay' if zone == 3 else 'Fracture core' if zone == 6 else 'Mortar' if zone == 4 else 'Concrete')
        material.use_nodes = True
        principled = material.node_tree.nodes.get('Principled BSDF')
        if zone in (3, 5, 7):
            channels = MAPS['factory_brick' if zone == 3 else 'concrete']
            for kind, socket in [('Diffuse', 'Base Color'), ('Rough', 'Roughness')]:
                node = material.node_tree.nodes.new('ShaderNodeTexImage')
                node.image = channels[kind][0]
                material.node_tree.links.new(node.outputs['Color'], principled.inputs[socket])
        else:
            principled.inputs['Base Color'].default_value = (.31, .12, .055, 1) if zone == 6 else (.24, .23, .21, 1)
            principled.inputs['Roughness'].default_value = .85
        MATERIALS[zone] = material


def uv_for(point, normal, zone, cell, brick_cells):
    p = point.copy()
    if zone == 3:
        center, dimensions = brick_cells.get(str(cell), ((0, 0, 0), BRICK))
        p -= Vector(center)
        axis = max(range(3), key=lambda k: abs(normal[k]))
        a, b = [(2, 1), (0, 2), (0, 1)][axis]
        u, v = p[a]/dimensions[a]+.5, p[b]/dimensions[b]+.5
        crop = CROPS[cell % len(CROPS)]
        x0, y0, x1, y1 = crop
        return ((x0+u*(x1-x0))/1024, 1-(y1-v*(y1-y0))/1024)
    axis = max(range(3), key=lambda k: abs(normal[k]))
    a, b = [(2, 1), (0, 2), (0, 1)][axis]
    return (point[a]/4+.45, point[b]/4+.45)


def prepare_uv(obj):
    mesh = obj.data
    cells = json.loads(obj.get('brick_cells', '{}'))
    uv = mesh.uv_layers.new(name='Source material UV')
    mesh.materials.clear()
    for zone in range(8):
        mesh.materials.append(MATERIALS[zone])
    for face in mesh.polygons:
        zone = mesh.attributes['lie_zone'].data[face.index].value
        cell = mesh.attributes['lie_cell'].data[face.index].value
        face.material_index = zone
        for loop in face.loop_indices:
            uv.data[loop].uv = uv_for(mesh.vertices[mesh.loops[loop].vertex_index].co, face.normal, zone, cell, cells)


def bilinear(pixels, uv):
    h, w = pixels.shape[:2]
    x, y = (uv[0] % 1)*w-.5, (uv[1] % 1)*h-.5
    a, b = math.floor(x), math.floor(y)
    u, v = x-a, y-b
    return pixels[b % h, a % w]*(1-u)*(1-v)+pixels[b % h, (a+1) % w]*u*(1-v)+pixels[(b+1) % h, a % w]*(1-u)*v+pixels[(b+1) % h, (a+1) % w]*u*v


def material_at(zone, uv, p):
    if zone in (3, 5, 7):
        maps = MAPS['factory_brick' if zone == 3 else 'concrete']
        srgb = bilinear(maps['Diffuse'][1], uv)[:3]
        color = np.where(srgb <= .04045, srgb/12.92, ((srgb+.055)/1.055)**2.4)
        rough = float(bilinear(maps['Rough'][1], uv)[0])
        return tuple(float(v) for v in color), min(max(rough, .2), .98)
    grain = .96+.04*math.sin(p.x*810+p.z*471)*math.sin(p.y*905)
    return tuple(v*grain for v in ((.31, .12, .055) if zone == 6 else (.24, .23, .21))), .85


def capture(obj, resolution, out):
    points, faces, zones, cells, center, size = base.geometry(obj)
    mesh = obj.data
    triangles = list(mesh.loop_triangles)
    supports = []
    for tri in triangles:
        face = mesh.polygons[tri.polygon_index]
        axis = max(range(3), key=lambda k: abs(face.normal[k]))
        a_axis, b_axis = [(2, 1), (0, 2), (0, 1)][axis]
        face_points = [mesh.vertices[k].co-center for k in face.vertices]
        supports.append((min(q[a_axis] for q in face_points), min(q[b_axis] for q in face_points),
                         max(q[a_axis] for q in face_points), max(q[b_axis] for q in face_points)))
    bvh = BVHTree.FromPolygons(points, faces, all_triangles=True)
    # Small child masters share the parent's sampling density, rather than
    # receiving four times its density merely because their bounds shrank.
    span = max(max(size), max(BRICK) if obj.name.startswith('fragment') or obj.name == 'half_brick' else 0)*1.12
    spacing, voxel = span/resolution, span/resolution*.7
    unique, views = {}, []
    for elevation in [-55, 0, 55]:
        el = math.radians(elevation)
        for azimuth in range(0, 360, 30):
            az = math.radians(azimuth)
            direction = Vector((math.sin(az)*math.cos(el), math.sin(el), math.cos(az)*math.cos(el)))
            right = Vector((math.cos(az), 0, -math.sin(az)))
            up = direction.cross(right).normalized()
            origin = direction*span*2
            rgba = bytearray(resolution*resolution*4)
            valid = 0
            for y in range(resolution):
                for x in range(resolution):
                    ro = origin+right*((x+.5)/resolution-.5)*span+up*(.5-(y+.5)/resolution)*span
                    hit, n, index, _ = bvh.ray_cast(ro, -direction, span*4)
                    if hit is None or n.dot(direction) <= .08:
                        continue
                    tri = triangles[index]
                    a, b, c = (points[k] for k in faces[index])
                    v0, v1, v2 = b-a, c-a, hit-a
                    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
                    denom = d00*d11-d01*d01
                    if abs(denom) < 1e-15:
                        continue
                    u = (d11*v2.dot(v0)-d01*v2.dot(v1))/denom
                    v = (d00*v2.dot(v1)-d01*v2.dot(v0))/denom
                    uvs = [mesh.uv_layers.active.data[k].uv for k in tri.loops]
                    uv = uvs[0]*(1-u-v)+uvs[1]*u+uvs[2]*v
                    zone, cell = zones[index], cells[index]
                    color, rough = material_at(zone, uv, hit+center)
                    srgb = [q*12.92 if q <= .0031308 else 1.055*q**(1/2.4)-.055 for q in color]
                    offset = (y*resolution+x)*4
                    rgba[offset:offset+4] = bytes([min(255, max(0, round(q*255))) for q in srgb]+[255])
                    key = tuple(round(hit[k]/voxel) for k in range(3))+(zone, cell)
                    bounds = supports[index]
                    sample = tuple(hit)+(spacing*.85,)+tuple(n)+(1.,float(zone),float(cell),rough,0.)+tuple(color)+(1.,)+bounds
                    front = n.dot(direction)
                    if key not in unique or front > unique[key][0]:
                        unique[key] = (front, sample)
                    valid += 1
            views.append(dict(azimuth=azimuth, elevation=elevation, valid_pixels=valid))
            if elevation == 0 and azimuth in (0, 60, 180):
                base.png(out/f'{obj.name}-az{azimuth:03d}-albedo.png', rgba, resolution)
    fine = [v[1] for v in unique.values()]
    coarse = {}
    for s in fine:
        key = tuple(round(s[k]/(voxel*3.0)) for k in range(3))+(int(s[8]), int(s[9]))
        coarse.setdefault(key, s[:3]+(s[3]*3.0,)+s[4:])
    return fine, list(coarse.values()), dict(capture_views=views, bounds_size=list(size), origin_offset=list(center),
                collision_vertices=[list(p) for p in points], triangle_count=len(faces), grid_size_m=list(obj.get('grid_size_m', size)),
                opening=json.loads(obj.get('opening', 'null')))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--materials', required=True, type=Path)
    parser.add_argument('--resolution', default=128, type=int)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not 64 <= args.resolution <= 192:
        raise ValueError('Resolution outside authoring contract')
    assets, out = ROOT/'assets/lie28', ROOT/'captures/building28'
    assets.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((args.materials/'provenance.json').read_text())
    for item in provenance:
        if hashlib.sha256((args.materials/item['file']).read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Material hash mismatch')
    load_materials(args.materials)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    brick = bevel(box('brick', BRICK, 3))
    objects = [brick, bevel(box('half_brick', (.115, .07, .12), 3)), cinder_block(),
        box('concrete_panel', (1, .8, .12)), box('slab', (1, .10, 1)),
        box('lintel', (1, .08, .16)), corner(), wall('wall'),
        wall('window_wall', (-.25, .25, -.24, .24)),
        wall('door_base', (-.375, .375, -.4, .4)),
        wall('door_head', (-.375, .375, -.4, -.08))]+fracture(brick)
    for obj in objects:
        prepare_uv(obj)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        # Raw coordinates already satisfy GLTF Y-up; do not convert them again.
        bpy.ops.export_scene.gltf(filepath=str(assets/(obj.name+'.glb')), use_selection=True, export_format='GLB', export_yup=False)
    for image in bpy.data.images:
        if image.source == 'FILE':
            image.pack()
    for obj in objects:
        obj.asset_mark()
        obj.asset_data.author = 'Lie Engine'
        obj.asset_data.description = 'Building master in metres / Y up. Shared parent origin for fragments. Source maps: CC0 Rob Tuytel / Poly Haven.'
        obj.hide_set(obj.name != 'brick')
        obj.hide_render = obj.name != 'brick'
    bpy.ops.wm.save_as_mainfile(filepath=str(assets/'building-masters.blend'))
    catalog = dict(schema=1, stride=80, capture_resolution=args.resolution, original_mesh_drawn=False,
        source='Original dimensioned Blender meshes; source maps CC0 / Rob Tuytel / Poly Haven',
        materials=provenance, brick_size=list(BRICK), pitch=list(PITCH), module_size=list(MODULE),
        sample_layout=['position_radius', 'geometric_normal_unused', 'zone_cell_roughness_unused', 'linear_albedo_unused', 'face_support_bounds'],
        masters={})
    data, oracles = array('f'), {}
    for obj in objects:
        fine, coarse, metadata = capture(obj, args.resolution, out)
        metadata['levels'] = []
        for samples in (fine, coarse):
            metadata['levels'].append(dict(start=len(data)//20, count=len(samples)))
            for s in samples:
                data.extend(s)
        catalog['masters'][obj.name] = metadata
        pts, faces, zones, cells, center, size = base.geometry(obj)
        oracles[obj.name] = dict(vertices=[list(p) for p in pts], triangles=faces, zones=zones, cells=cells, origin_offset=list(center),
                triangle_uvs=[[list(obj.data.uv_layers.active.data[k].uv) for k in tri.loops] for tri in obj.data.loop_triangles])
        print('LIE28 CAPTURE', obj.name, len(fine), len(coarse), flush=True)
    raw = data.tobytes()
    if len(raw) > 64*1024*1024:
        raise ValueError('Capture library exceeds renderer budget; lower resolution')
    catalog.update(sample_count=len(data)//20, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    atomic(out/'library.bin', raw)
    atomic(out/'catalog.json', (json.dumps(catalog, indent=2)+'\n').encode())
    atomic(assets/'source-surfaces.json', (json.dumps(oracles)+'\n').encode())
    atomic(assets/'provenance.json', (json.dumps(provenance, indent=2)+'\n').encode())
    print('LIE28 LIBRARY', catalog['sample_count'], len(raw), 'bytes', flush=True)


if __name__ == '__main__':
    main()
