#!/usr/bin/env python3
"""Export editable original robot geometry from the native LIE pose packets.

This is an offline authoring export, not a runtime rendering or control path.
Blender --background --python tools/lie_robot_export_blender.py -- --session DIR
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1] / 'gpu_compute'


def matrix(part):
    columns = part['basis']
    return Matrix([[columns[c][r] for c in range(3)] + [part['origin'][r]]
                   for r in range(3)] + [[0, 0, 0, 1]])


def curve_positions(vertices, packet, curve, radius):
    """Vectorized independent implementation of the documented Hermite packet."""
    knots = np.asarray(packet, dtype=np.float64).reshape(-1, 16, 12)[curve]
    t = np.clip(vertices[:, 1] * 2 + .5, 0, 1) * 15
    k = np.minimum(t.astype(int), 14)
    f = (t - k)[:, None]
    a, b = knots[k], knots[k + 1]
    f2, f3 = f * f, f * f * f
    step = a[:, 11:12] / 15
    center = (a[:, :3] * (2*f3 - 3*f2 + 1) + a[:, 8:11] * step * (f3 - 2*f2 + f)
              + b[:, :3] * (-2*f3 + 3*f2) + b[:, 8:11] * step * (f3 - f2))
    tangent = a[:, 8:11]*(1-f) + b[:, 8:11]*f
    tangent /= np.linalg.norm(tangent, axis=1)[:, None]
    normal = a[:, 4:7]*(1-f) + b[:, 4:7]*f
    normal -= tangent * np.sum(normal*tangent, axis=1)[:, None]
    normal /= np.linalg.norm(normal, axis=1)[:, None]
    return center + normal*vertices[:, 0:1]*radius + np.cross(normal, tangent)*vertices[:, 2:3]*radius


def set_keyframe(obj, part, frame):
    obj.matrix_world = matrix(part)
    obj.rotation_mode = 'QUATERNION'
    for prop in ('location', 'rotation_quaternion', 'scale'):
        obj.keyframe_insert(prop, frame=frame, group='Native LIE walk')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', required=True, type=Path)
    parser.add_argument('--name', default='R1-Robot', help='Output asset basename; R2-Robot for the refined assembly')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if Path(args.name).name != args.name or '/' in args.name or '\\' in args.name: raise ValueError('Use an asset basename')
    rest = json.loads((args.session/'r1-assembly.json').read_text())
    walk = json.loads((args.session/'r1-walk-assembly.json').read_text())
    assert len(walk) == 16 and all(len(s['assembly']) == len(rest['assembly']) for s in walk)
    assets = ROOT/'assets/robot_modular'
    bpy.ops.wm.open_mainfile(filepath=str(assets/'robot-masterkit.blend'))
    originals = {name: bpy.data.objects[name] for name in rest['control_contract']['masters']}
    collection = bpy.data.collections.new('R1 assembled robot · original source geometry')
    bpy.context.scene.collection.children.link(collection)
    objects = []
    max_error = 0.0
    for index, part in enumerate(rest['assembly']):
        if part['master'] == 'ground':
            continue
        source = originals[part['master']]
        obj = source.copy()
        obj.name = f"R1-{index:02d}-{part['master']}"
        collection.objects.link(obj)
        obj.hide_set(False); obj.hide_render = False
        obj['lie_master'] = part['master']; obj['lie_bone_index'] = part['bone']
        obj['lie_coordinate_system'] = 'metres; Y up; source GLBs exported without axis conversion'
        vertices = np.asarray([v.co[:] for v in source.data.vertices], dtype=np.float64)
        if part['curve'] >= 0:
            obj.data = source.data.copy()
            expected = curve_positions(vertices, rest['curve_frames'], part['curve'], part['radius_scale'])
            obj.data.vertices.foreach_set('co', expected.ravel()); obj.data.update()
            obj.matrix_world = Matrix.Identity(4)
        else:
            obj.matrix_world = matrix(part)
            expected = vertices @ np.asarray(part['basis']).reshape(3, 3) + np.asarray(part['origin'])
        actual = np.asarray([(obj.matrix_world @ v.co)[:] for v in obj.data.vertices])
        max_error = max(max_error, float(np.max(np.linalg.norm(actual-expected, axis=1))))
        objects.append((index, obj, vertices))
    assert max_error < .000001
    bpy.ops.object.select_all(action='DESELECT')
    for _, obj, _ in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0][1]
    bpy.ops.export_scene.gltf(filepath=str(assets/(args.name+'.glb')), use_selection=True,
                             export_format='GLB', export_yup=False, export_animations=False)
    # Editable walk is baked from the same native rig evaluations; no new solver.
    sequence = [rest] + walk + [walk[0]]
    for index, obj, vertices in objects:
        part = rest['assembly'][index]
        if part['curve'] < 0:
            for frame, state in enumerate(sequence): set_keyframe(obj, state['assembly'][index], frame)
        else:
            obj.shape_key_add(name='Rest source')
            keys = []
            for phase, state in enumerate(walk):
                p = state['assembly'][index]
                key = obj.shape_key_add(name=f'Native phase {phase:02d}')
                key.data.foreach_set('co', curve_positions(vertices, state['curve_frames'], p['curve'], p['radius_scale']).ravel())
                keys.append(key)
            for frame in range(len(sequence)):
                active = (frame-1) % 16 if frame else -1
                for phase, key in enumerate(keys):
                    key.value = float(phase == active); key.keyframe_insert('value', frame=frame)
    for action in bpy.data.actions:
        for fc in action.fcurves:
            for key in fc.keyframe_points: key.interpolation = 'LINEAR'
    for source in originals.values(): source.hide_set(True); source.hide_render = True
    scene = bpy.context.scene
    scene.render.fps = 16; scene.frame_start = 1; scene.frame_end = 17; scene.frame_set(0)
    scene['README'] = 'Frame 0: saved native rest pose. Frames 1–17: baked native walk. Original masters remain separate and hidden. Runtime evidence comes from LIE, not this source mesh export.'
    for _, obj, _ in objects: obj.select_set(False)
    objects[0][1].select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(assets/(args.name+'.blend')))
    report = dict(parts=len(objects), cables=sum(rest['assembly'][i]['curve']>=0 for i,_,_ in objects),
                  max_native_pose_vertex_error_m=max_error, baked_walk_phases=16,
                  native_snapshot_sha256=hashlib.sha256((args.session/'r1-assembly.json').read_bytes()).hexdigest(),
                  note='Original editable geometry export; not an engine rendering or performance result.')
    (ROOT/'robot-source-export-verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print('ROBOT SOURCE EXPORT', json.dumps(report), flush=True)


if __name__ == '__main__': main()
