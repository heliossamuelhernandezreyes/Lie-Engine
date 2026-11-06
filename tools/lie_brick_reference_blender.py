"""Blender CPU/Cycles reference and neutral captures of the SAME LIE-28 master.

blender -b -t 4 --python tools/lie_brick_reference_blender.py -- --output DIR
No LIE solver is imported to render the independent reference. Source meshes
are saved for inspection; only captured surface records enter the LIE camera.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lie28_prepare_blender as building
from lie_asset_contract import inspect_bank
from lie_brick_reference_math import split_triangle, triangle_area, camera_frame

COLORS = {'brick': [.56, .16, .055], 'floor': [.55, .55, .55],
          'wall': [.65, .65, .65], 'blocker': [.15, .15, .15]}
SIZES = {'brick': building.BRICK, 'floor': (.6, .008, .5),
         'wall': (.6, .34, .008), 'blocker': (.055, .14, .055), 'opening_wall': (.6, .34, .008)}
COLORS['opening_wall'] = COLORS['wall']
EYE, TARGET = [.48, .34, .57], [0., .075, -.035]


def dump(path, data):
    path.write_text(json.dumps(data, indent=2)+'\n')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def material(name):
    m = bpy.data.materials.new('Explicit Lambert '+name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    diffuse = nodes.new('ShaderNodeBsdfDiffuse')
    diffuse.inputs['Color'].default_value = (*COLORS[name], 1.)
    diffuse.inputs['Roughness'].default_value = 0.
    m.node_tree.links.new(diffuse.outputs[0], out.inputs['Surface'])
    return m


def masters(directory, resolution):
    arrays, catalog, sources, geometry = [], {'schema': 1, 'stride': 80, 'masters': {}}, {}, {}
    for name, size in SIZES.items():
        if name == 'opening_wall':
            pts, faces, zones, cells = [], [], [], []
            for x0, x1, y0, y1 in building.split_rect((-.3,.3,-.17,.17),(-.07,.07,-.06,.06)):
                if x1>x0 and y1>y0:
                    building.base.append_box(pts,faces,zones,cells,((x0+x1)/2,(y0+y1)/2,0),(x1-x0,y1-y0,.008),3)
            obj = building.base.mesh_object(name,pts,faces,zones,cells)
        else: obj = building.box(name, size, 3)
        if name == 'brick':
            building.bevel(obj)  # EXACT existing LIE-28 recipe, 1.5 mm / 2 segments.
        obj.data.materials.clear()
        obj.data.materials.append(material(name))
        for face in obj.data.polygons:
            face.material_index = 0
            obj.data.attributes['lie_cell'].data[face.index].value = face.index
        # Capture helper reads source UVs even for a uniform authored material.
        uv = obj.data.uv_layers.new(name='Uniform authored material')
        for item in uv.data:
            item.uv = (.5, .5)
        building.material_at = lambda zone, uv, p, rgb=COLORS[name]: (rgb, 1.)
        fine, coarse, meta = building.capture(obj, resolution, directory)
        points, faces, zones, cells, center, dimensions = building.base.geometry(obj)
        tri = [np.array([points[k] for k in f], float) for f in faces]
        # Contiguous, source-authored coplanar groups; never cross owner boundaries.
        groups = {}
        for triangle_index, t in enumerate(tri):
            n = np.cross(t[1]-t[0], t[2]-t[0]); n /= np.linalg.norm(n)
            polygon = obj.data.loop_triangles[triangle_index].polygon_index
            key = (polygon,)
            for child in split_triangle(t, maximum_edge=.075, minimum_area=.0025):
                groups.setdefault(key, []).append((child.mean(0), n, triangle_area(child)))
        nodes = []
        for key in sorted(groups):
            first, count = len(nodes), len(groups[key])
            for p, n, area in groups[key]:
                nodes.append({'position': p.tolist(), 'normal': n.tolist(), 'area': area,
                              'group': [first, count], 'material': name, 'source_polygon':key[0]})
        positions = np.array([n['position'] for n in nodes]); normals = np.array([n['normal'] for n in nodes])
        meta['levels'] = []
        for level in (fine, coarse):
            a = np.array(level, dtype='<f4')
            for s in a:
                distance = ((positions-s[:3])**2).sum(1)
                distance[normals@s[4:7] < .9999] = np.inf
                distance[np.array([n['source_polygon'] for n in nodes])!=int(s[9])] = np.inf
                if not np.isfinite(distance).any():
                    raise ValueError('Capture lacks a compatible source plane')
                s[9] = int(np.argmin(distance))  # local immutable node ID, not material variation.
            meta['levels'].append({'start': sum(len(x) for x in arrays), 'count': len(a)})
            arrays.append(a)
        meta['light_nodes'] = nodes
        catalog['masters'][name] = meta
        sources[name] = obj
        geometry[name] = {'vertices': [list(p) for p in points], 'triangles': faces,
                          'triangle_polygons':[t.polygon_index for t in obj.data.loop_triangles]}
        print('BRICK REFERENCE CAPTURE', name, len(fine), 'nodes', len(nodes), flush=True)
    raw = np.concatenate(arrays).tobytes()
    catalog.update(sample_count=len(raw)//80, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                   source='Authored LIE-28 brick recipe + explicit uniform Lambert controls',
                   source_mesh_drawn=False, capture_resolution=resolution,
                   asset_frame={'semantic_frame_verified': True, 'units': 'meters', 'up': 'Y', 'front': '+Z'})
    (directory/'library.bin').write_bytes(raw)
    dump(directory/'catalog.json', catalog)
    dump(directory/'asset-contract.json', inspect_bank(raw, catalog))
    dump(directory/'source-surfaces.json', geometry)
    return catalog, sources, geometry


def cases():
    base = [{'master': 'floor', 'position': [0., -.004, 0.]},
            {'master': 'wall', 'position': [0., .17, -.17]},
            {'master': 'brick', 'position': [0., .035, 0.]}]
    point = {'position': [-.22, .43, .25], 'power': 2., 'kind': 'point'}
    result = []
    for name in ['calibration_plane', 'matte_point', 'grazing_point', 'two_bricks', 'blocker_left', 'blocker_right', 'area_panel', 'wall_opening']:
        instances = json.loads(json.dumps(base)); light = dict(point)
        if name == 'calibration_plane': instances = instances[:1]
        if name == 'grazing_point': light['position'] = [-.30, .105, .17]
        if name == 'two_bricks':
            instances[-1]['position'] = [-.065, .035, .045]
            instances.append({'master': 'brick', 'position': [.075, .106, -.025]})
        if name.startswith('blocker_'):
            instances.append({'master': 'blocker', 'position': [-.10 if name.endswith('left') else .10, .07, .095]})
        if name == 'area_panel':
            light.update(kind='area', position=[-.10, .33, .22], size=[.12, .08], target=TARGET)
        if name == 'wall_opening':
            instances[1]['master'] = 'opening_wall'; light['position'] = [0., .17, -.34]
        result.append({'name': name, 'instances': instances, 'light': light})
    return result


def field_inputs(case, catalog, geometry, directory):
    patches, triangles, groups, triangle_owners = [], [], [], []
    for owner, inst in enumerate(case['instances']):
        offset = np.array(inst['position']); meta = catalog['masters'][inst['master']]
        inst['node_offset'] = len(patches)
        for n in meta['light_nodes']:
            patches.append({'position': (np.array(n['position'])+offset).tolist(), 'normal': n['normal'],
                            'area': n['area'], 'gray_mean': 1., 'material': n['material']})
            groups.append([n['group'][0]+inst['node_offset'], n['group'][1], owner, 0])
        g = geometry[inst['master']]; verts = np.array(g['vertices'])+offset
        triangles.extend(verts[np.array(g['triangles'])].tolist())
        triangle_owners.extend([owner]*len(g['triangles']))
    if len(patches) > 1024: raise ValueError('Common field capacity exceeded')
    flat = np.array(triangles).reshape(-1, 3)
    bvh = BVHTree.FromPolygons([Vector(v) for v in flat], [tuple(range(i, i+3)) for i in range(0, len(flat), 3)], all_triangles=True)
    p = np.array([n['position'] for n in patches]); n = np.array([v['normal'] for v in patches]); a = np.array([v['area'] for v in patches])
    delta = p[None, :, :]-p[:, None, :]; d2 = np.sum(delta*delta, 2)
    direction = delta/np.maximum(np.sqrt(d2)[:, :, None], 1e-30)
    cosine = np.maximum(np.einsum('ijk,ik->ij', direction, n), 0.)
    matrix = a[None, :]*cosine*cosine.T/(math.pi*np.maximum(d2, 1e-30))
    np.fill_diagonal(matrix, 0.)
    for i, j in zip(*np.where(np.triu(matrix > 0, 1))):
        d = math.sqrt(d2[i, j]); eps = max(d*.001, 1e-6)
        hit = bvh.ray_cast(Vector(p[i]+direction[i, j]*eps), Vector(direction[i, j]), max(d-2*eps, 0.))[0]
        if hit is not None: matrix[i, j] = matrix[j, i] = 0.
    # Shared symmetric-local passive normalization, reported explicitly.
    row = np.maximum(matrix.sum(1), 1.)
    pair = np.maximum(row[:, None], row[None, :]); matrix /= pair
    np.save(directory/(case['name']+'-factors.npy'), matrix)
    emitter = case['light']; lights = []; descriptors = np.zeros((8, 4), dtype='<f4')
    if emitter['kind'] == 'point': positions = [(np.array(emitter['position']), 1.)]
    else:
        right, up, forward = camera_frame(emitter['position'], emitter['target'])
        positions = [(np.array(emitter['position'])+right*x*emitter['size'][0]/(2*math.sqrt(3))+up*y*emitter['size'][1]/(2*math.sqrt(3)), .25) for x in [-1, 1] for y in [-1, 1]]
    for i, (position, weight) in enumerate(positions):
        lights.append({'position': position.tolist(), 'power_rgb': [emitter['power']*weight]*3, 'radius': 100.})
        if emitter['kind'] == 'area': descriptors[i] = [*forward, 1.]
    model = {'schema': 1, 'patches': patches, 'triangles': triangles, 'blockers': [], 'lights': lights, 'bounces': 3,
             'materials': {k: {'absorption_code': 0, 'tint_linear': [1., 1., 1.], 'albedo': rgb,
                              'roughness': 1., 'metallic': 0., 'ior': 1.} for k, rgb in COLORS.items()}}
    dump(directory/(case['name']+'-model.json'), model)
    case.update(groups=groups, emission_hex=descriptors.tobytes().hex(), field_nodes=len(patches),
                factor_normalization={'policy': 'symmetric_local', 'max_pre_normalization_row_sum': float(row.max())})
    print('BRICK REFERENCE FIELD', case['name'], len(patches), 'edges', np.count_nonzero(matrix), flush=True)
    return bvh, np.asarray(triangle_owners)


def save_linear(path, scene):
    scene.render.image_settings.file_format = 'OPEN_EXR'
    scene.render.image_settings.color_mode = 'RGBA'; scene.render.image_settings.color_depth = '32'
    scene.render.filepath = str(path.with_suffix('.exr'))
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(scene.render.filepath, check_existing=False)
    pixels = np.empty(len(image.pixels), dtype=np.float32); image.pixels.foreach_get(pixels)
    rgba = pixels.reshape(image.size[1], image.size[0], 4)[::-1].copy()
    np.save(path, rgba)
    bpy.data.images.remove(image)


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resolution', type=int, default=128); parser.add_argument('--samples', type=int, default=128)
    parser.add_argument('--capture-resolution', type=int, default=96)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:]); root = args.output.resolve(); root.mkdir(parents=True, exist_ok=True)
    if args.resolution not in (128,256,512) or not 32<=args.samples<=4096 or not 64<=args.capture_resolution<=192:
        raise ValueError('Resolution, sampling or capture budget outside the declared laboratory range')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    catalog, objects, geometry = masters(root, args.capture_resolution)
    # A camera whose vertical FOV exactly matches the LIE square projection.
    right, up, forward = camera_frame(EYE, TARGET)
    camera = bpy.data.objects.new('Shared camera', bpy.data.cameras.new('Shared camera')); bpy.context.collection.objects.link(camera)
    camera.location = EYE; camera.rotation_euler = Matrix((Vector(right), Vector(up), Vector(-forward))).transposed().to_euler()
    camera.data.type = 'PERSP'; camera.data.sensor_fit = 'VERTICAL'; camera.data.angle_y = math.radians(42); camera.data.clip_start = .001
    scene = bpy.context.scene; scene.camera = camera; scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
    scene.render.resolution_x = scene.render.resolution_y = args.resolution; scene.render.resolution_percentage = 100
    scene.render.film_transparent = True; scene.render.filter_size = .01
    scene.world = bpy.data.worlds.new('Black world'); scene.world.use_nodes = True; scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.
    scene.cycles.use_denoising = False; scene.cycles.use_adaptive_sampling = False
    scene.cycles.sample_clamp_direct = 0.; scene.cycles.sample_clamp_indirect = 0.
    scene.view_settings.view_transform = 'Standard'; scene.view_settings.look = 'None'; scene.view_settings.exposure = 0.; scene.view_settings.gamma = 1.
    original = list(objects.values())
    for obj in original: obj.hide_render = True
    output_cases = cases()
    for case in output_cases:
        bvh, owners = field_inputs(case, catalog, geometry, root)
        gbuffer = np.zeros((args.resolution,args.resolution,8), dtype='<f4'); gbuffer[:,:,7] = -1
        tangent = math.tan(math.radians(21))
        for y in range(args.resolution):
            for x in range(args.resolution):
                ray = forward+right*((2*(x+.5)/args.resolution-1)*tangent)+up*((1-2*(y+.5)/args.resolution)*tangent)
                hit, normal, index, distance = bvh.ray_cast(Vector(EYE),Vector(ray).normalized())
                if hit is not None: gbuffer[y,x] = [*hit,*normal,distance,owners[index]]
        np.save(root/(case['name']+'-source-gbuffer.npy'),gbuffer)
        created = []
        for instance in case['instances']:
            obj = objects[instance['master']].copy(); obj.hide_render = False; obj.location = instance['position']; bpy.context.collection.objects.link(obj); created.append(obj)
        emitter = case['light']; lamp = bpy.data.lights.new(case['name'], 'POINT' if emitter['kind'] == 'point' else 'AREA')
        lamp.energy = emitter['power']; lamp.color = (1., 1., 1.); lamp.use_shadow = True
        if emitter['kind'] == 'point': lamp.shadow_soft_size = 0.
        else: lamp.shape = 'RECTANGLE'; lamp.size, lamp.size_y = emitter['size']
        light_obj = bpy.data.objects.new(case['name']+' emitter', lamp); bpy.context.collection.objects.link(light_obj); light_obj.location = emitter['position']
        if emitter['kind'] == 'area': light_obj.rotation_euler = (Vector(emitter['target'])-light_obj.location).to_track_quat('-Z', 'Y').to_euler()
        created.append(light_obj)
        for pass_name, bounces, seed in [('direct', 0, 71), ('direct-repeat',0,193), ('full', 3, 71), ('repeat', 3, 193)]:
            scene.cycles.samples = args.samples; scene.cycles.seed = seed; scene.cycles.max_bounces = bounces; scene.cycles.diffuse_bounces = bounces
            save_linear(root/(case['name']+'-cycles-'+pass_name+'.npy'), scene)
        for obj in created: bpy.data.objects.remove(obj, do_unlink=True)
    # Editable source includes exactly the authored masters, not a fake photo.
    for obj in original: obj.hide_render = obj.name != 'brick'
    bpy.ops.wm.save_as_mainfile(filepath=str(root/'brick-reference-masters.blend'))
    # GLB preserves the master geometry; the explicit Lambert benchmark policy
    # is recorded in the manifest because glTF exports a PBR material instead.
    brick = objects['brick']; previous = list(brick.data.materials)
    pbr = bpy.data.materials.new('Authored brick PBR export'); pbr.use_nodes=True
    bsdf=pbr.node_tree.nodes['Principled BSDF'];bsdf.inputs['Base Color'].default_value=(*COLORS['brick'],1.);bsdf.inputs['Roughness'].default_value=1.;bsdf.inputs['Metallic'].default_value=0.
    brick.data.materials.clear();brick.data.materials.append(pbr)
    bpy.ops.object.select_all(action='DESELECT');brick.select_set(True);bpy.context.view_layer.objects.active=brick
    bpy.ops.export_scene.gltf(filepath=str(root/'brick.glb'),use_selection=True,export_format='GLB',export_yup=False)
    brick.data.materials.clear()
    for m in previous:brick.data.materials.append(m)
    manifest = {'schema': 'lie-brick-reference/1', 'resolution': args.resolution, 'source_recipe': 'lie28_prepare_blender.box/bevel',
                'brick_size_m': list(building.BRICK), 'bevel_m': .0015,
                'quadrature': {'maximum_edge_m': .075, 'minimum_triangle_area_m2': .0025, 'thin_triangles_may_exceed_target_edge': True},
                'camera': {'eye': EYE, 'target': TARGET, 'vertical_fov_degrees': 42.},
                'reference': {'engine': 'Cycles CPU', 'blender': bpy.app.version_string, 'samples': args.samples, 'seeds': [71, 193],
                              'full_bounces': 3, 'direct_bounces': 0, 'denoising': False, 'world': 'black', 'display_transform_in_metrics': False},
                'materials': COLORS, 'cases': output_cases, 'bank_sha256': catalog['sha256'],
                'limits': ['Uniform authored Lambert controls; no downloaded photographic textures or displacement.',
                           'Editable Blend has the exact Lambert controls; GLB exports the same geometry with a declared PBR material.',
                           'LIE passive scatter includes its existing Schlick/gloss approximation; Cycles uses explicit Lambert.',
                           'Indirect candidate visibility is compiled offline from the exact source. Runtime camera/shadow reconstruction uses captured records.',
                           'Common field direct visibility retains the source triangles as an explicit benchmark control; no source mesh is drawn. This does not certify capture-only field visibility.',
                           'Area reference is a continuous rectangle; LIE uses its existing four point quadrature.'],
                'files': {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in root.iterdir() if p.is_file() and p.name!='manifest.json'}}
    dump(root/'manifest.json', manifest)
    print('BRICK REFERENCE SOURCE PASS', catalog['sha256'], flush=True)


if __name__ == '__main__': main()
