"""Build conservative normal/position intervals without changing capture bytes.

Each record indexes samples within one original SHA-locked page. Normal bins
and Morton order group interleaved source faces without rewriting the bank.
The renderer may skip a record only when every geometric normal faces away
from the perspective eye. These intervals are not optical occlusion volumes.
"""
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

CLUSTER_SIZE = 64
STRIDE = 56


def normal_order(points, normals):
    axis = np.argmax(np.abs(normals), axis=1)
    dominant = np.maximum(np.max(np.abs(normals), axis=1), 1e-20)
    axes = np.array([[1, 2], [0, 2], [0, 1]])[axis]
    uv = np.take_along_axis(normals, axes, axis=1) / dominant[:, None]
    bins = np.clip(np.floor((uv + 1) * 2), 0, 3).astype(np.uint32)
    face = axis * 2 + (np.take_along_axis(normals, axis[:, None], axis=1)[:, 0] < 0)
    keys = face * 16 + bins[:, 0] * 4 + bins[:, 1]
    normalized = (points - points.min(0)) / np.maximum(np.ptp(points, axis=0), 1e-20)
    coords = np.clip(normalized * 1023, 0, 1023).astype(np.uint32)
    morton = np.zeros(len(points), dtype=np.uint32)
    for bit in range(10):
        for k in range(3):
            morton |= ((coords[:, k] >> bit) & 1) << (3 * bit + k)
    return np.lexsort((morton, keys)).astype('<u4'), keys


def build_bank(folder, contiguous_reference=False):
    folder = Path(folder)
    catalog = json.loads((folder / 'catalog.json').read_text())
    index = json.loads((folder / 'pages.json').read_text())
    raw = (folder / 'library.bin').read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if catalog['stride'] != 80 or digest != catalog['sha256'] or digest != index['bank_sha256']:
        raise ValueError('cluster_source_identity')
    samples = np.frombuffer(raw, dtype='<f4').reshape(-1, 20)
    records = bytearray()
    indices = bytearray()
    entries = {}
    for key, page in sorted(index['entries'].items(), key=lambda item: int(item[1]['start'])):
        start, count = int(page['start']), int(page['count'])
        if hashlib.sha256(raw[start * 80:(start + count) * 80]).hexdigest() != page['core_sha256']:
            raise ValueError('cluster_page_identity')
        first = len(records) // STRIDE
        index_first = len(indices) // 4
        page_samples = samples[start:start + count]
        if contiguous_reference:
            order, keys = np.arange(count, dtype='<u4'), np.zeros(count, dtype=np.uint32)
        else:
            order, keys = normal_order(page_samples[:, :3], page_samples[:, 4:7])
        boundaries = np.r_[0, np.flatnonzero(np.diff(keys[order])) + 1, count]
        groups = []
        for begin, end in zip(boundaries[:-1], boundaries[1:]):
            groups.extend((offset, min(offset + CLUSTER_SIZE, end)) for offset in range(int(begin), int(end), CLUSTER_SIZE))
        indices.extend(order.tobytes())
        for offset, end in groups:
            group = page_samples[order[offset:end]]
            p, n = group[:, :3], group[:, 4:7]
            if not np.isfinite(p).all() or not np.isfinite(n).all() or np.abs(n).max() > 1.001:
                raise ValueError('cluster_source_values')
            bounds = np.concatenate([np.nextafter(p.min(0), np.float32(-np.inf)),
                                     np.nextafter(p.max(0), np.float32(np.inf)),
                                     np.nextafter(n.min(0), np.float32(-np.inf)),
                                     np.nextafter(n.max(0), np.float32(np.inf))])
            records.extend(struct.pack('<II12f', offset, len(group), *bounds))
        entries[key] = {'first': first, 'clusters': len(records) // STRIDE - first,
                        'index_first': index_first, 'samples': count, 'core_sha256': page['core_sha256']}
    binary = folder / 'visibility-clusters.bin'
    binary.write_bytes(records)
    (folder / 'visibility-indices.bin').write_bytes(indices)
    metadata = {'schema': 'lie-visibility-clusters/2', 'bank_sha256': digest,
                'cluster_size': CLUSTER_SIZE, 'stride': STRIDE,
                'file': binary.name, 'bytes': len(records),
                'sha256': hashlib.sha256(records).hexdigest(), 'entries': entries,
                'indices_file': 'visibility-indices.bin', 'indices_bytes': len(indices),
                'indices_sha256': hashlib.sha256(indices).hexdigest(),
                'grouping': 'consecutive-reference' if contiguous_reference else 'normal-4x4-face-morton',
                'scope': 'Conservative geometric backface intervals; no resampling, no optical occlusion claim.'}
    (folder / 'visibility-clusters.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def build_scene(scene):
    manifest = json.loads((Path(scene) / 'manifest.json').read_text())
    return {name: build_bank(Path(scene) / 'banks' / name) for name in manifest['banks']}


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scene', type=Path, required=True)
    args = parser.parse_args()
    result = build_scene(args.scene)
    print(json.dumps({name: {'clusters': row['bytes'] // STRIDE, 'bytes': row['bytes'], 'source': row['bank_sha256']}
                      for name, row in result.items()}))
