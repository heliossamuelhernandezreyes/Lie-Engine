"""Capture interchangeable noses with exclusive ownership and a common seam.

The rigid face preserves captured XYZ and normals without a dense deformation
cage. Detailed cage vertices remain only where motion requires them: lids and
the neck. The authored scan is used for captures and native references only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lie20_prepare_blender import blender, capture, ROOT
from lie23_prepare_blender import build_face
from lie24_modules import nose_slot, nose_variants


def prepare(resolution=160):
    old_root = ROOT.parents[1]/'captures/face23'
    old = json.loads((old_root/'master.json').read_text())
    old_samples = list(struct.iter_unpack('<20f', (old_root/'samples.bin').read_bytes()))
    old_vertices = list(struct.iter_unpack('<24f', (old_root/'vertices.bin').read_bytes()))
    old_triangles = [t[:3] for t in struct.iter_unpack('<4I', (old_root/'triangles.bin').read_bytes())]
    face, rig, rest, weights, blink, arc, uvs, color, normal, spec, anchors, regions, removed = build_face()
    face.data.calc_loop_triangles()
    triangles = [tuple(t.vertices) for t in face.data.loop_triangles]
    if triangles != old_triangles or len(rest) != len(old_vertices):
        raise ValueError('LIE-23 source identity changed; regenerate its packets')
    selected, boundary, indices = nose_slot(rest, triangles, regions)
    variants, collar = nose_variants(rest, triangles, selected, boundary, indices)
    selected = set(selected)
    from lie24_blank_blender import blank_nose
    blank=blank_nose(rest,triangles,selected,uvs,color)
    root = ROOT.parents[1]/'captures/face24'; root.mkdir(parents=True, exist_ok=True)
    # Remove the old nose entirely from the shared base. A filler and every
    # replacement own the exact same region; they never overlap at runtime.
    skin = []; rigid_count = 0; required = set(); probes = []
    lid_probe_count = 0
    for source_index, source in enumerate(old_samples[:old['face_sample_count']]):
        s = list(source); ti = int(s[3]); ids = triangles[ti]
        if ti in selected:
            continue
        rigid = all(weights[k] >= 1-1e-7 and regions[k] == 0 and blink[k].length == 0 and arc[k].length == 0 for k in ids)
        if rigid:
            p = sum((rest[k]*w for k, w in zip(ids, s[:3])), Vector())
            a, b, c = (rest[k] for k in ids)
            s[:4] = [*p, -2.]
            s[16:20] = [*(b-a).cross(c-a).normalized(), 1.]
            rigid_count += 1
        else:
            required.add(ti)
        if source_index % 7000 == 0 or (any(regions[k]>0 for k in ids) and lid_probe_count<24):
            probes.append({'sample':len(skin),'triangle':list(ids),'bary':list(source[:3]),'group':0})
            if any(regions[k]>0 for k in ids):lid_probe_count+=1
        skin.append(s)
    # Keep complete detailed patches, including shared lid boundaries.
    required.update(i for i, tri in enumerate(triangles) if any(regions[k] > 0 or weights[k] < 1-1e-7 for k in tri))
    vertex_ids = sorted({k for i in required for k in triangles[i]} | set(boundary))
    vertex_map = {k: i for i, k in enumerate(vertex_ids)}
    vertices = [old_vertices[k] for k in vertex_ids]
    triangle_ids = sorted(required); triangle_map = {k: i for i, k in enumerate(triangle_ids)}
    packed_triangles = [(*[vertex_map[k] for k in triangles[i]], 0) for i in triangle_ids]
    for s in skin:
        if s[3] >= 0:
            s[3] = float(triangle_map[int(s[3])])
    modules = []; native_objects = []
    face.hide_render = True; face.hide_set(True)
    for variant, name in enumerate(['base', 'classic', 'short', 'wide']):
        own_indices=blank['source_ids'] if variant==0 else indices
        coords={k:tuple(p) for k,p in zip(own_indices,blank['points'])} if variant==0 else variants[variant]
        local_map = {k: i for i, k in enumerate(own_indices)}
        local_points = [Vector(coords[k]) for k in own_indices]
        local_triangles = blank['triangles'] if variant==0 else [tuple(local_map[k] for k in triangles[i]) for i in sorted(selected)]
        source_triangles = [] if variant==0 else [face.data.loop_triangles[i] for i in sorted(selected)]
        mesh = bpy.data.meshes.new('LieNose_'+name)
        mesh.from_pydata([blender(p) for p in local_points], [], local_triangles); mesh.update()
        layer = mesh.uv_layers.new(name='CaptureUV')
        source_uvs = face.data.uv_layers['CaptureUV']
        for poly in mesh.polygons:
            poly.use_smooth = True
            if variant==0:
                for loop in poly.loop_indices:
                    p=local_points[mesh.loops[loop].vertex_index];layer.data[loop].uv=(p.x,p.y)
            else:
                source=source_triangles[poly.index]
                for loop, old_loop in zip(poly.loop_indices, source.loops):layer.data[loop].uv=source_uvs.data[old_loop].uv
        for mat in face.data.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new('Nose_'+name, mesh); bpy.context.collection.objects.link(obj)
        # Native weighted normal vectors use the complete assembled surface,
        # avoiding a shading discontinuity from an independently averaged rim.
        complete = [p.copy() for p in blank['full_points']] if variant==0 else [p.copy() for p in rest]
        for k, p in coords.items(): complete[k] = Vector(p)
        reference = bpy.data.meshes.new('Assembled_'+name)
        reference.from_pydata([blender(p) for p in complete], [], blank['full_triangles'] if variant==0 else triangles); reference.update()
        global_ids = []
        for k, p in zip(own_indices, local_points):
            if k in boundary:
                global_ids.append(vertex_map[k])
            else:
                n = reference.vertices[k].normal
                from lie20_prepare_blender import lie
                global_ids.append(len(vertices)); vertices.append((*p, 1., 0., 0., 0., 3., 0., 0., 0., 0., *lie(n).normalized(), 0., 0., 0., 0., 0., 0., 0., 0., 0.))
        offset = len(packed_triangles)
        packed_triangles.extend((*[global_ids[k] for k in t], variant+1) for t in local_triangles)
        folder = root/name; folder.mkdir(exist_ok=True)
        captured, samples, views = capture(obj, local_points, [], blank['color'] if variant==0 else color, normal, blank['spec'] if variant==0 else spec, folder, resolution,
            native_tangents=True, capture_center=(0, .273, .095), capture_scale=.10,
            smooth_regions=[1]*len(local_points))
        if captured != local_triangles: raise ValueError('Unstable module triangle binding')
        start = len(skin)
        for sample_index, s in enumerate(samples):
            if sample_index % max(1,len(samples)//24) == 0:
                ids=tuple(own_indices[k] for k in local_triangles[int(s[3])])
                probes.append({'sample':len(skin),'triangle':list(ids),'bary':list(s[:3]),'group':variant+1})
            s[3] += offset; s[15] = 0.; s[16:19] = [1., 0., 1.]
            skin.append(s)
        obj.hide_render = variant != 1; obj.hide_set(variant != 1)
        native_objects.append(obj)
        modules.append({'id':variant, 'name':name, 'family':'lee-face-v1', 'slot':'nose',
            'triangle_group':variant+1, 'triangle_offset':offset, 'triangle_count':len(local_triangles),
            'sample_offset':start, 'sample_count':len(samples), 'capture_views':views,
            'boundary_vertex_ids':[vertex_map[k] for k in blank['boundary']], 'source_vertex_ids':own_indices,
            'source_triangles':[list(tuple(own_indices[k] for k in tri)) for tri in local_triangles],
            'collar_source_vertices':blank['boundary'] if variant==0 else collar,
            'capture_resolution':resolution,
            'global_vertex_ids':global_ids, 'coordinates':[list(coords[k]) for k in own_indices]})
        bpy.data.meshes.remove(reference)
    eye_samples = old_samples[old['face_sample_count']:]
    packets = {'vertices.bin':b''.join(struct.pack('<24f', *v) for v in vertices),
        'triangles.bin':b''.join(struct.pack('<4I', *t) for t in packed_triangles),
        'samples.bin':b''.join(struct.pack('<20f', *s) for s in skin+list(eye_samples))}
    for name, data in packets.items(): (root/name).write_bytes(data)
    manifest = dict(old)
    manifest.update({'master_id':'lie-modular-face24', 'rigid_sample_encoding':'local-xyz-head-v1',
        'sample_count':len(skin)+len(eye_samples), 'face_sample_count':len(skin),
        'invocation_count':len(skin)+2*len(eye_samples), 'vertex_count':len(vertices),
        'triangle_count':len(packed_triangles), 'rigid_face_sample_count':rigid_count,
        'deforming_base_triangle_count':len(triangle_ids), 'original_vertex_count':old['vertex_count'],
        'original_triangle_count':old['triangle_count'], 'facial_modules':modules,
        'buffers':{n:{'bytes':len(d), 'sha256':hashlib.sha256(d).hexdigest()} for n,d in packets.items()},
        'modifications':old['modifications']+' Nose region removed from base; smooth skin cap without nostril colors; shared-boundary filler and three captured variants; rigid facial samples preserve XYZ without a dense deformation cage.',
        'limits':old['limits']+['Only the nose slot is interchangeable; lips, cheeks and brows remain from the attributed scan.','Variants share one identity/proportion family; this is not a general anatomical character generator.']})
    if manifest['invocation_count'] > 1000000: raise ValueError('Module library exceeds runtime budget')
    (root/'master.json').write_text(json.dumps(manifest, indent=2)+'\n')
    # Connectivity evidence is evaluated per assembled choice, never against
    # all overlapping alternatives simultaneously.
    seam = {'source_boundary':blank['boundary'], 'runtime_boundary':[vertex_map[k] for k in blank['boundary']],
        'collar_source_vertices':collar, 'source_slot_triangles':sorted(selected),
        'source_base_triangles':[list(t) for i,t in enumerate(triangles) if i not in selected],
        'source_points':[list(p) for p in blank['full_points']], 'variant_source_triangles':[list(triangles[i]) for i in sorted(selected)]}
    (root/'seam.json').write_text(json.dumps(seam)+'\n')
    # Build actual native assembled objects for independent silhouette/albedo
    # references. Their triangles are used only by Blender, never by Lie.
    from lie24_reference_blender import render_references
    render_references(face, rig, rest, triangles, variants, selected, modules, root, anchors, probes, blank)
    assets = ROOT.parent/'lie24'; assets.mkdir(exist_ok=True)
    for image in bpy.data.images:
        if image.source == 'FILE' and not image.packed_file: image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(assets/'modular-face.blend'), compress=True)
    print('LIE24 MASTER', json.dumps({k:manifest[k] for k in ['sample_count','invocation_count','vertex_count','triangle_count','rigid_face_sample_count']}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--resolution', type=int, default=160)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not 128 <= args.resolution <= 192: raise ValueError('Module resolution outside budget')
    prepare(args.resolution)
