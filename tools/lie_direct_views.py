"""Compile view-visible depth + provenance from the accepted attributed field.

All cell projection and nearest-surface reduction happens OFFLINE. Runtime
uses at most three angular references and fixed reprojection/refinement counts.
This is an approximate relightable impostor, not an exact ray accelerator.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
GRID = 8
SIZES = (192, 512)
VERSION = 'lie-captured-views/1'

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def oct_decode(uv):
    p = np.asarray(uv, dtype=np.float64) * 2 - 1
    v = np.array([p[0], p[1], 1 - abs(p[0]) - abs(p[1])])
    if v[2] < 0:
        v[:2] = (1 - np.abs(v[1::-1])) * np.where(v[:2] >= 0, 1, -1)
    return v / np.linalg.norm(v)

def oct_select(direction, grid=GRID):
    v = np.asarray(direction, dtype=np.float64)
    v = v / np.abs(v).sum()
    uv = v[:2].copy()
    if v[2] < 0:
        uv = (1 - np.abs(uv[::-1])) * np.where(uv >= 0, 1, -1)
    q = np.clip((uv * .5 + .5) * (grid - 1), 0, grid - 1)
    base = np.minimum(np.floor(q).astype(int), grid - 2)
    f = q - base
    if f.sum() <= 1:
        cells = [base, base + [1, 0], base + [0, 1]]
        weights = [1 - f.sum(), f[0], f[1]]
    else:
        cells = [base + [1, 1], base + [0, 1], base + [1, 0]]
        weights = [f.sum() - 1, 1 - f[0], 1 - f[1]]
    return [(int(c[1] * grid + c[0]), float(w)) for c, w in zip(cells, weights)]

def pack_code(x, y, face, layer):
    return (np.asarray(x, dtype=np.uint32) | (np.asarray(y, dtype=np.uint32) << 10)
            | (np.uint32(face) << 21) | (np.asarray(layer, dtype=np.uint32) << 25)) + np.uint32(1)

def unpack_code(code):
    q = np.asarray(code, dtype=np.uint32) - np.uint32(1)
    return q & 1023, (q >> 10) & 2047, (q >> 21) & 15, (q >> 25) & 3

def camera(lo, hi, direction, longest):
    center = (lo + hi) * .5
    helper = np.array([0., 1., 0.]) if abs(direction[1]) < .95 else np.array([0., 0., 1.])
    right = np.cross(helper, direction); right /= np.linalg.norm(right)
    up = np.cross(direction, right)
    radius = (hi - lo) * .5
    # One texel guard on both sides of the projected bounding box.
    extent = np.array([np.abs(right) @ radius, np.abs(up) @ radius])
    extent *= 1 + 4 / longest
    wh = np.clip(np.ceil(longest * extent / extent.max()).astype(int), 8, longest)
    return center, right, up, extent, wh

def source_cells(field, proof, master):
    lo = np.array(proof['boxes'][master]['lo'])
    hi = np.array(proof['boxes'][master]['hi'])
    cells = []
    first = proof['boxes'][master]['first_face']
    for face in range(first, first + 6):
        r = proof['faces'][face]
        d = field[r['y']:r['y'] + r['height'], r['x']:r['x'] + r['width']]
        y, x, layer = np.nonzero(d >= 0)
        axis = (face % 6) // 2; axes = [k for k in range(3) if k != axis]
        step = (hi[axes] - lo[axes]) / [r['width'], r['height']]
        xyz = np.empty((len(x), 3), dtype=np.float64)
        xyz[:, axes] = lo[axes] + (np.column_stack([x, y]) + .5) * step
        xyz[:, axis] = hi[axis] - d[y, x, layer] if face % 2 == 0 else lo[axis] + d[y, x, layer]
        cells.append((face, axis, axes, step, xyz, pack_code(x + r['x'], y + r['y'], face, layer)))
    return cells

def bake_view(cells, lo, hi, direction, longest):
    center, right, up, extent, wh = camera(lo, hi, direction, longest)
    w, h = map(int, wh)
    depth = np.full(w * h, -np.inf, dtype=np.float32)
    codes = np.zeros(w * h, dtype=np.uint32)
    code_depth = np.full(w * h, -np.inf, dtype=np.float32)
    # Render the finite original cell squares. No hole filling and no inferred
    # geometry bridges are introduced. Ties have a deterministic provenance ID.
    for face, axis, axes, step, xyz, ids in cells:
        if direction[axis] * (1 if face % 2 == 0 else -1) < .02 or not len(xyz):
            continue
        relative = xyz - center
        xy = np.column_stack([relative @ right, relative @ up])
        pixels = (xy / extent * .5 + .5) * wh - .5
        nearest = np.floor(pixels + .5).astype(int)
        half = np.array([np.abs(right[axes]) @ (step * .5), np.abs(up[axes]) @ (step * .5)])
        reach = np.ceil(half / (2 * extent) * wh + .5).astype(int)
        for dy in range(-int(reach[1]), int(reach[1]) + 1):
            for dx in range(-int(reach[0]), int(reach[0]) + 1):
                ix = nearest[:, 0] + dx; iy = nearest[:, 1] + dy
                mask = (ix >= 0) & (ix < w) & (iy >= 0) & (iy < h)
                selected = np.flatnonzero(mask)
                if not len(selected): continue
                px = ((ix[selected] + .5) / w * 2 - 1) * extent[0]
                py = ((iy[selected] + .5) / h * 2 - 1) * extent[1]
                base = center + px[:, None] * right + py[:, None] * up
                z = (xyz[selected, axis] - base[:, axis]) / direction[axis]
                point = base[:, axes] + z[:, None] * direction[axes]
                valid = np.all(np.abs(point - xyz[selected][:, axes]) <= step * .50001, axis=1)
                selected = selected[valid]; z = z[valid].astype(np.float32)
                target = iy[selected] * w + ix[selected]
                if not len(target): continue
                np.maximum.at(depth, target, z)
                wins = z == depth[target]
                # minimum.at also resolves collisions within this vector batch.
                target = target[wins]; candidate = ids[selected[wins]]
                # Existing IDs from an earlier (farther) plane must be replaced.
                # Resolve the current batch first, then compare against the old
                # ID only when its recorded depth equals the new nearest depth.
                unique, inverse = np.unique(target, return_inverse=True)
                values = np.full(len(unique), np.iinfo(np.uint32).max, np.uint32)
                np.minimum.at(values, inverse, candidate)
                tied = (code_depth[unique] == depth[unique]) & (codes[unique] != 0)
                values[tied] = np.minimum(values[tied], codes[unique[tied]])
                codes[unique] = values
                code_depth[unique] = depth[unique]
    raw = np.zeros((h, w, 2), np.uint32)
    raw[..., 0] = depth.reshape(h, w).view(np.uint32)
    raw[..., 1] = codes.reshape(h, w)
    raw[..., 0][raw[..., 1] == 0] = 0
    return raw, (center, right, up, direction, extent)

def compile_views(root=None, destination=None):
    root = Path(root or ROOT / 'gpu_compute/captures/liewall06/direct')
    destination = Path(destination or root)
    proof = json.loads((root / 'surface.json').read_text())
    if proof['width'] > 1024 or proof['height'] > 2048 or len(proof['faces']) > 16 or proof['layers'] != 4 or len(proof['boxes']) != 2:
        raise ValueError('Captured-view provenance packet capacity; unsupported field must not wrap IDs')
    spec = {'grid': GRID, 'sizes': list(SIZES), 'source_packets': proof['packets'], 'compiler': digest(Path(__file__).read_bytes())}
    old = destination / 'views.json'
    if old.exists():
        saved = json.loads(old.read_text())
        if saved.get('spec') == spec and all((destination / n).is_file() and digest((destination / n).read_bytes()) == e['sha256'] for n, e in saved['packets'].items()):
            return saved
    for name, entry in proof['packets'].items():
        if digest((root / name).read_bytes()) != entry['sha256']: raise ValueError('Source field identity: ' + name)
    field = np.fromfile(root / 'depth.bin', '<f4').reshape(proof['height'], proof['width'], 4)
    metadata = bytearray(); packets = {}; masters = []
    for master, longest in enumerate(SIZES):
        lo = np.array(proof['boxes'][master]['lo']); hi = np.array(proof['boxes'][master]['hi'])
        cells = source_cells(field, proof, master)
        atlas_width = 2048 if master == 0 else 4096
        tiles = []; x = y = row = 0
        for index in range(GRID * GRID):
            direction = oct_decode([index % GRID / (GRID - 1), index // GRID / (GRID - 1)])
            image, values = bake_view(cells, lo, hi, direction, longest)
            h, w = image.shape[:2]
            if x + w > atlas_width: x = 0; y += row; row = 0
            tiles.append((x, y, image))
            center, right, up, direction, extent = values
            floats = np.array([*right, extent[0], *up, extent[1], *direction, 0., *center, 0.], '<f4')
            metadata.extend(floats.tobytes()); metadata.extend(np.array([x, y, w, h], '<i4').tobytes())
            x += w; row = max(row, h)
            if index % 8 == 7: print('VIEW BAKE', master, index + 1, '/', GRID * GRID, flush=True)
        atlas = np.zeros((y + row, atlas_width, 2), '<u4')
        for x, y, image in tiles: atlas[y:y + image.shape[0], x:x + image.shape[1]] = image
        name = 'views-' + str(master) + '.bin'; raw = atlas.tobytes(); (destination / name).write_bytes(raw)
        packets[name] = {'bytes': len(raw), 'sha256': digest(raw)}
        masters.append({'width': atlas.shape[1], 'height': atlas.shape[0], 'views': GRID * GRID, 'max_capture_size': longest, 'valid_pixels': int(np.count_nonzero(atlas[..., 1]))})
    raw = bytes(metadata); (destination / 'views-meta.bin').write_bytes(raw)
    packets['views-meta.bin'] = {'bytes': len(raw), 'sha256': digest(raw)}
    result = {'schema': VERSION, 'spec': spec, 'source_bank_sha256': proof['source_bank_sha256'], 'packets': packets, 'masters': masters, 'metadata_stride': 80,
              'runtime': {'angular_candidates': 3, 'view_depth_steps': 3, 'source_refinements': 2, 'source_cell_walk': False, 'shadow_backend': 'regions'},
              'scope': 'offline orthographic visibility of accepted four-layer directional cell fields; no original source mesh; finite angular/resolution approximation; no hole filling; original full-resolution material provenance; fixed runtime queries; shadows independently use regions'}
    old.write_text(json.dumps(result, indent=2) + '\n')
    return result

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--root', type=Path); p.add_argument('--destination', type=Path)
    a = p.parse_args(); print(json.dumps(compile_views(a.root, a.destination), indent=2))
