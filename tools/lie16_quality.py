"""Conservative, deterministic capture mipmaps; no source geometry at runtime.

Only complete, coplanar cells with consistent normals/material are reduced.
Capture boundaries, holes, creases and thin details keep their original samples.
This module uses the standard library so all older CI gates can import it.
"""
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def normalize(v):
    length = math.sqrt(dot(v, v))
    if length < 1e-10:
        raise ValueError('Degenerate normal')
    return [x / length for x in v]


def lie(v):
    return [v[0], v[2], -v[1]]


def merge_cell(points, step):
    """Return one footprint only when its entire source cell is represented."""
    if len(points) != step * step:
        return None
    if len({int(p[7]) for p in points}) != 1:
        return None
    normal = normalize([sum(p[k] for p in points) for k in range(4, 7)])
    if any(dot(normal, p[4:7]) < .995 for p in points):
        return None
    if max(p[3] for p in points) - min(p[3] for p in points) > .025:
        return None
    center = [sum(p[k] for p in points) / len(points) for k in range(3)]
    if any(abs(dot(normal, [p[k] - center[k] for k in range(3)])) > .002 for p in points):
        return None
    return center + [sum(p[3] for p in points) / len(points)] + normal + [points[0][7]]


def view_mip(points, right, up, origin, pixel_size, resolution, step):
    cells = defaultdict(list)
    coords = set()
    for p in points:
        delta = [p[k] - origin[k] for k in range(3)]
        x = math.floor(dot(delta, right) / pixel_size + resolution / 2)
        y = math.floor(resolution / 2 - dot(delta, up) / pixel_size)
        if (x, y) in coords:
            raise ValueError('Capture has duplicate pixel coordinates')
        coords.add((x, y))
        cells[(x // step, y // step)].append(p)
    result, widths = [], []
    for key in sorted(cells):
        group = cells[key]
        merged = merge_cell(group, step)
        if merged is None:
            if step > 2:
                finer, finer_widths = view_mip(group, right, up, origin, pixel_size, resolution, 2)
                result.extend(finer)
                widths.extend(finer_widths)
            else:
                result.extend(group)
                widths.extend([pixel_size] * len(group))
        else:
            result.append(merged)
            widths.append(pixel_size * step)
    return result, widths


def lod_weights(spacing):
    """Fine sample footprint in pixels -> continuous 1x/2x/4x levels."""
    if not math.isfinite(spacing) or spacing <= 0:
        raise ValueError('Invalid screen spacing')
    if spacing <= .30:
        return [(2, 1.)]
    if spacing < .35:
        t = (spacing - .30) / .05
        t = t * t * (3 - 2 * t)
        return [(2, 1 - t), (1, t)]
    if spacing <= .60:
        return [(1, 1.)]
    if spacing < .70:
        t = (spacing - .60) / .10
        t = t * t * (3 - 2 * t)
        return [(1, 1 - t), (0, t)]
    return [(0, 1.)]


def prepare(root):
    master = json.loads((root / 'master.json').read_text())
    manifest = json.loads((root / 'manifest.json').read_text())
    source = (root / 'master-samples.bin').read_bytes()
    if hashlib.sha256(source).hexdigest() != master['sample_sha256']:
        raise ValueError('Source master digest mismatch')
    fine = list(struct.iter_unpack('<8f', source))
    resolution = manifest['resolution'][0]
    pixel_size = manifest['orthographic_scale'] / resolution
    samples = [list(p) for p in fine]
    footprints = [pixel_size] * len(samples)
    levels = [[], [], []]
    for index, view in enumerate(master['views']):
        capture = manifest['views'][index]
        matrix = capture['camera_matrix_blender']
        right = lie([matrix[k][0] for k in range(3)])
        up = lie([matrix[k][1] for k in range(3)])
        forward = lie([-matrix[k][2] for k in range(3)])
        origin = lie([matrix[k][3] - manifest['center_blender'][k] for k in range(3)])
        base = {**view, 'right': right, 'up': up, 'forward': forward}
        levels[0].append(base)
        points = fine[view['start']:view['start'] + view['count']]
        for level, step in [(1, 2), (2, 4)]:
            mip, widths = view_mip(points, right, up, origin, pixel_size, resolution, step)
            levels[level].append({**base, 'start': len(samples), 'count': len(mip)})
            samples.extend(mip)
            footprints.extend(widths)
    data = b''.join(struct.pack('<8f', *p) for p in samples)
    footprint_data = struct.pack('<%df' % len(footprints), *footprints)
    (root / 'quality-samples.bin').write_bytes(data)
    (root / 'quality-footprints.bin').write_bytes(footprint_data)
    result = {**master, 'quality_schema': 1, 'source_sample_sha256': master['sample_sha256'],
              'sample_count': len(samples), 'sample_sha256': hashlib.sha256(data).hexdigest(),
              'footprint_sha256': hashlib.sha256(footprint_data).hexdigest(),
              'pixel_size_local': pixel_size, 'levels': levels,
              'level_sample_counts': [sum(v['count'] for v in views) for views in levels]}
    (root / 'quality-master.json').write_text(json.dumps(result, indent=2) + '\n')
    print('LIE16 CONSERVATIVE LEVELS', result['level_sample_counts'])
    return result


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
