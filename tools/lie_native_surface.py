"""Exact finite cell sheets derived from the attributed four-layer captures.

Only bit-identical adjacent depths are merged. No fitted planes, source mesh,
hole filling, or interpolation of depth/ownership across cells is introduced.
These auxiliary raster triangles are additional to the invisible box proxies.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def cell_rectangles(depth, face, layer):
    """Disjoint rectangles covering exactly equal-depth occupied cells."""
    depth = np.asarray(depth, dtype='<f4')
    if not np.isfinite(depth).all():
        raise ValueError('Nonfinite captured depth')
    packets = []
    active = {}

    def emit(key, span):
        x0, x1, bits = key
        y0, y1 = span
        d = np.array([bits], dtype='<u4').view('<f4')[0]
        packets.append(struct.pack('<8f4I', x0, y0, x1, y1,
                                   d, d, d, d, face, layer, 0, 0))

    for y, row in enumerate(depth):
        bits = row.view('<u4')
        edges = np.r_[0, np.flatnonzero(bits[1:] != bits[:-1]) + 1, len(row)]
        current = {}
        for x0, x1 in zip(edges[:-1], edges[1:]):
            if row[x0] < 0:
                continue
            key = (int(x0), int(x1), int(bits[x0]))
            current[key] = (active[key][0], y + 1) if key in active else (y, y + 1)
        for key in sorted(active.keys() - current.keys()):
            emit(key, active[key])
        active = current
    for key in sorted(active):
        emit(key, active[key])
    return b''.join(packets)


def compile_native(root=None):
    root = Path(root or ROOT / 'gpu_compute/captures/liewall06/direct')
    proof = json.loads((root / 'surface.json').read_text())
    for name, meta in proof['packets'].items():
        data = (root / name).read_bytes()
        if len(data) != meta['bytes'] or hashlib.sha256(data).hexdigest() != meta['sha256']:
            raise ValueError('Captured packet identity: ' + name)
    depth = np.fromfile(root / 'depth.bin', '<f4').reshape(
        proof['height'], proof['width'], proof['layers'])
    groups, chunks, count = [], [], 0
    for master, box in enumerate(proof['boxes']):
        first = count
        for face in range(box['first_face'], box['first_face'] + 6):
            rect = proof['faces'][face]
            x, y, w, h = (rect[k] for k in ['x', 'y', 'width', 'height'])
            for layer in range(proof['layers']):
                packet = cell_rectangles(depth[y:y+h, x:x+w, layer], face, layer)
                chunks.append(packet)
                count += len(packet) // 48
        groups.append({'first_quad': first, 'quads': count-first,
                       'triangles': (count-first)*2})
    data = b''.join(chunks)
    meta = {'schema': 'lie-native-cell-sheets/1',
            'source_bank_sha256': proof['source_bank_sha256'],
            'source_packets': proof['packets'], 'quad_stride': 48,
            'groups': groups, 'layers': proof['layers'],
            'packets': {'native.bin': {'bytes': len(data),
                        'sha256': hashlib.sha256(data).hexdigest()}},
            'scope': 'exact finite constant-depth cell sheets; original material/owner lookup; '
                     'entry-face selection matches regions; auxiliary raster triangles; '
                     'reverse-Z primary and regions shadows; no original mesh; no speed claim'}
    (root / 'native.bin').write_bytes(data)
    (root / 'native.json').write_text(json.dumps(meta, indent=2)+'\n')
    return meta


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path)
    print(json.dumps(compile_native(p.parse_args().root), indent=2))
