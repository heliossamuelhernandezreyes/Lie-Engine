"""Measure captured native coverage and shadow-toggle differences at the phone pose.

Input: untimed outputs of diagnose_lie_direct_views_case.gd. These are differences
against regions, not ground-truth reconstruction error or physical GPU timings.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

MODES = ('regions', 'views', 'views_fast')

def load(captures, label):
    metadata = json.loads((captures / (label + '.json')).read_text())
    size = metadata['internal_size']
    if size != metadata['output_size']:
        raise ValueError('Coverage diagnostic requires equal internal/output grids')
    if metadata['metrics']['effective_backend'] != metadata['mode']:
        raise ValueError('Fallback is not evidence for the requested mode')
    result = {'metadata': metadata}
    for key, suffix, dtype in [('rgba', '-rgba.f32', '<f4'), ('world', '-world.f32', '<f4')]:
        data = np.fromfile(captures / (label + suffix), dtype)
        result[key] = data.reshape(size, size, 4)
        if not np.isfinite(data).all():
            raise ValueError('Nonfinite readback: ' + label + key)
    return result

def analyze(captures):
    pairs = {mode: {shadow: load(captures, mode + '-' + shadow)
                   for shadow in ('shadows', 'no-shadows')} for mode in MODES}
    baseline = pairs['regions']['shadows']['world']
    mask = baseline[..., 3] > .5
    interior = mask.copy()
    for y in range(-2, 3):
        for x in range(-2, 3):
            shifted = np.zeros_like(mask)
            shifted[2:-2, 2:-2] = mask[2+y:mask.shape[0]-2+y, 2+x:mask.shape[1]-2+x]
            interior &= shifted
    rows = {}
    # This grouping is the existing WALL06 adapter: 96 bricks x nine nodes,
    # followed by the mortar group. It is not a general asset identity decoder.
    baseline_node = np.rint(baseline[..., 3]).astype(np.int64) - 1
    baseline_group = np.where(baseline_node >= 864, 96, baseline_node // 9)
    for mode, pair in pairs.items():
        on, off = pair['shadows'], pair['no-shadows']
        world, rgba = on['world'], on['rgba']
        if not np.array_equal(world, off['world']):
            raise ValueError('Geometry changed with shadow toggle: ' + mode)
        hit = world[..., 3] > .5
        overlap = mask & hit
        delta = np.linalg.norm(world[..., :3] - baseline[..., :3], axis=-1)
        node = np.rint(world[..., 3]).astype(np.int64) - 1
        group = np.where(node >= 864, 96, node // 9)
        same_instance = overlap & (group == baseline_group)
        dark = hit & (rgba[..., :3].max(-1) < .025)
        rows[mode] = {
            'hits': int(hit.sum()),
            'baseline_coverage_iou': float(overlap.sum() / (mask | hit).sum()),
            'baseline_hits_missing': int((mask & ~hit).sum()),
            'baseline_interior_hits_missing': int((interior & ~hit).sum()),
            'extra_hits': int((hit & ~mask).sum()),
            'overlap_different_instance': int((overlap & ~same_instance).sum()),
            'same_instance_world_delta_mm_p50_p95': np.percentile(delta[same_instance] * 1000, [50, 95]).tolist(),
            'dark_valid_hits': int(dark.sum()),
            'dark_valid_hits_lit_when_shadows_off': int((dark & (off['rgba'][..., :3].max(-1) >= .025)).sum()),
            'same_world_shadow_toggle': True,
            'finite_world': True,
        }
    evidence = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in captures.iterdir() if p.suffix in ('.png', '.f16', '.f32') and not p.name.endswith('-unlit.png')}
    return {
        'schema': 'lie25-phone-pose-diagnosis/1',
        'production_runtime_commit': '2836e6b941ae638f4788fe6c28755e7b8bfdc581',
        'device': pairs['views']['shadows']['metadata']['device'],
        'state': pairs['views']['shadows']['metadata']['state'],
        'rows': rows,
        'evidence': evidence,
        'scope': 'Untimed software Vulkan reproduction; differences against regions, not source ground truth. A shadow toggle proves a lighting contribution, not that every dark pixel is shadow acne. Different-instance depth differences are not local surface error. Screenshot-time mode is not recorded on the phone screenshots.',
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = analyze(args.captures)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['rows'], indent=2))
