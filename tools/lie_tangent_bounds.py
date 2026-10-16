"""Refit an existing source BVH around captured tangent disks.

Only AABBs change. Node indices, escape links, leaf lists, source IDs, disk
tests and instance transforms remain byte-identical. Sphere bounds are kept
as an outer clamp; an outward float32 guard protects thin disk extents.
"""
import json
from pathlib import Path
import numpy as np
from lie_asset_surface import EMPTY, require_bank, sha

ROOT = Path(__file__).resolve().parents[1]

def disk_bounds(samples):
    a = require_bank(samples)
    p, r, n = a[:, :3].astype(float), a[:, 3, None].astype(float), a[:, 4:7].astype(float)
    # Projection of a radius-r circle in the plane perpendicular to n.
    extent = r * np.sqrt(np.maximum(0., 1. - n*n / np.sum(n*n, axis=1)[:, None]))
    guard = 32 * np.finfo(np.float32).eps * (1. + abs(p) + r)
    low = np.nextafter((p - extent - guard).astype('<f4'), np.float32(-np.inf))
    high = np.nextafter((p + extent + guard).astype('<f4'), np.float32(np.inf))
    return low, high

def refit(samples, node_bytes, leaf_bytes):
    a = require_bank(samples)
    if not node_bytes or len(node_bytes) % 32 or not leaf_bytes or len(leaf_bytes) % 4:
        raise ValueError('refit packet ABI')
    original = np.frombuffer(node_bytes, dtype='<f4').reshape(-1, 8)
    words = np.frombuffer(node_bytes, dtype='<u4').reshape(-1, 8)
    refs = np.frombuffer(leaf_bytes, dtype='<u4')
    bounds = original[:, [0, 1, 2, 4, 5, 6]]
    if not np.isfinite(bounds).all() or (original[:, :3] > original[:, 4:7]).any():
        raise ValueError('refit finite bounds')
    low, high = disk_bounds(a)
    result = original.copy()
    for i in range(len(result)-1, -1, -1):
        escape, leaf = int(words[i, 3]), int(words[i, 7])
        if not i < escape <= len(result):
            raise ValueError('refit escape')
        if leaf == EMPTY:
            left = i + 1
            if left >= escape:
                raise ValueError('refit left child')
            right = int(words[left, 3])
            if not left < right < escape or int(words[right, 3]) != escape:
                raise ValueError('refit binary children')
            lo = np.minimum(result[left, :3], result[right, :3])
            hi = np.maximum(result[left, 4:7], result[right, 4:7])
        else:
            if leaf >= len(refs) or not 1 <= int(refs[leaf]) <= 8 or leaf + 1 + int(refs[leaf]) > len(refs):
                raise ValueError('refit leaf')
            ids = refs[leaf+1:leaf+1+int(refs[leaf])]
            if int(ids.max()) >= len(a):
                raise ValueError('refit source ID')
            lo, hi = low[ids].min(0), high[ids].max(0)
        result[i, :3] = np.maximum(original[i, :3], lo)
        result[i, 4:7] = np.minimum(original[i, 4:7], hi)
    if (result[:, :3] > result[:, 4:7]).any():
        raise ValueError('refit empty bounds')
    # Avoid float conversion of metadata NaNs (EMPTY is a NaN bit pattern).
    result.view('<u4')[:, [3, 7]] = words[:, [3, 7]]
    return result.tobytes()

def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root = Path(root)
    cat = json.loads((root/'catalog.json').read_text())
    source = json.loads((root/'surface-source.json').read_text())
    raw = (root/'library.bin').read_bytes()
    if sha(raw) != cat['sha256'] or source['source_bank_sha256'] != cat['sha256']:
        raise ValueError('refit source bank identity')
    packets = {}
    for key in ['nodes', 'leaves', 'scene']:
        meta = source['packets'][key]
        data = (root/meta['file']).read_bytes()
        if len(data) != meta['bytes'] or sha(data) != meta['sha256']:
            raise ValueError('refit original packet identity')
        packets[key] = data
    data = refit(np.frombuffer(raw, dtype='<f4').reshape(-1, 20), packets['nodes'], packets['leaves'])
    (root/'tangent-bounds.bin').write_bytes(data)
    proof = {'schema': 'lie-tangent-bounds/1', 'file': 'tangent-bounds.bin',
             'source_bank_sha256': cat['sha256'], 'original_nodes_sha256': sha(packets['nodes']),
             'original_leaves_sha256': sha(packets['leaves']), 'original_scene_sha256': sha(packets['scene']),
             'bytes': len(data), 'sha256': sha(data), 'nodes': len(data)//32,
             'guard': '32 * float32_epsilon * (1 + abs(source_position) + radius), outward rounded',
             'scope': 'refitted original topology; same leaves, source IDs, primitive equations and TLAS; numerical image equivalence still requires Vulkan acceptance'}
    (root/'tangent-bounds.json').write_text(json.dumps(proof, indent=2)+'\n')
    return proof

def prepare_reference():
    from lie_persistent_reference import prepare as persistent_reference
    cases = persistent_reference()
    for case in cases:
        bank = np.frombuffer(bytes.fromhex(case['bank_hex']), dtype='<f4').reshape(-1, 20)
        case['nodes_hex'] = refit(bank, bytes.fromhex(case['nodes_hex']), bytes.fromhex(case['leaves_hex'])).hex()
    path = ROOT/'gpu_compute/fixtures/tangent-visibility-reference.json'
    path.write_text(json.dumps({'schema': 'lie-tangent-reference/1',
        'oracle': 'unchanged independent exhaustive float64 disk oracle; only GPU node AABBs refitted',
        'cases': cases}, separators=(',', ':'))+'\n')
    return path

if __name__ == '__main__':
    print(json.dumps(prepare(), indent=2))
