"""Audit EVERY marked Vulkan result, plus uniform pixels outside the mask.

Uses analytic sheet enumeration independent of the legacy DDA. Does not turn
a mask census or a seeded sample into a full-frame/source-mesh guarantee.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from lie_cell_sheet_reference import CellSheetReference
from lie_real_vulkan_triplet import camera_rays
from lie_stream_candidate_metrics import load_risk, N, W
from lie_stream_first_hit_compare import scores, validate_packet


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inspect(captures, bank, pose=0, uniform_samples=10000, seed=1729):
    captures, bank = Path(captures), Path(bank)
    flags = load_risk(captures/f'{pose}-native-candidate-risk.bin').any(axis=0)
    original = np.fromfile(captures/f'{pose}-native-world.bin', '<f4').reshape(N, 4)
    packet = np.fromfile(captures/f'{pose}-native-first-hit.bin', '<f4').reshape(N, 16)
    status = validate_packet(packet, flags)
    rng = np.random.default_rng(seed)
    uniform = rng.choice(N, min(uniform_samples, N), replace=False)
    ids = np.unique(np.r_[np.flatnonzero(flags), uniform])
    reference = CellSheetReference(bank)
    depth = np.full(len(ids), np.inf)
    owner = np.zeros(len(ids), dtype=np.int64)
    for first in range(0, len(ids), 2048):
        chunk = ids[first:first+2048]
        eye, dirs, proxies, view, proxy_path = camera_rays(captures, pose, chunk, W)
        d, o, _ = reference.trace(eye, dirs, proxies)
        depth[first:first+len(chunk)], owner[first:first+len(chunk)] = d, o
    selected = flags[ids]
    base_bad, base = scores(None, original, ids[selected], eye, depth[selected], owner[selected])
    new_bad, new = scores(packet, original, ids[selected], eye, depth[selected], owner[selected])
    outside_bad, outside = scores(None, original, ids[~selected], eye, depth[~selected], owner[~selected])
    bad_ids = ids[selected][new_bad]
    witness_records = []
    for pixel in bad_ids[:120]:
        e, rays, p, _, _ = camera_rays(captures, pose, np.array([pixel]), W)
        _, _, witnesses = reference.trace(e, rays, p, details=True)
        record = packet[pixel]
        witness_records.append({'pixel_id': int(pixel), 'pixel': [int(pixel%W), int(pixel//W)],
            'gpu_owner': int(record[3]), 'gpu_status': int(record[13]),
            'gpu_distance_m': float(np.linalg.norm(record[:3].astype(float)-e)) if record[13] == 1 else None,
            'analytic_candidates': witnesses[0][:4]})
    passed = bool(not new_bad.any() and not outside_bad.any() and status['overflow_status'] == 0)
    return {'schema': 'lie-analytic-mask-census/1', 'pose': pose,
        'scope': 'ALL flagged pixels plus seeded uniform frame sample; NOT full framebuffer or original mesh',
        'reference': 'analytic finite-cell sheet enumeration; no DDA, no regions truth, no GPU result feedback',
        'samples': len(ids), 'seed': seed, 'uniform_frame_draws': len(uniform),
        'flagged_census': len(ids[selected]), 'unflagged_uniform_samples': len(ids[~selected]),
        'depth_tolerance_m': 2e-5, 'readback_status': status,
        'baseline_flagged': base, 'compute_flagged': new,
        'repaired_flagged': int((base_bad & ~new_bad).sum()),
        'regressed_flagged': int((~base_bad & new_bad).sum()),
        'unflagged_baseline': outside, 'strict_gate_passed': passed,
        'remaining_witnesses': witness_records,
        'provenance': {name: digest(path) for name, path in {
            'depth_sha256': bank/'direct/depth.bin', 'normal_sha256': bank/'direct/normal.bin',
            'surface_sha256': bank/'direct/surface.json', 'view_sha256': view, 'proxies_sha256': proxy_path,
            'compute_sha256': captures/f'{pose}-native-first-hit.bin',
            'baseline_world_sha256': captures/f'{pose}-native-world.bin',
            'risk_sha256': captures/f'{pose}-native-candidate-risk.bin'}.items()},
        'limitations': ['CPU float64 is not exact rational arithmetic for pathological ties',
            'Mask cannot flag candidates that never rasterize; uniform sample is not an exhaustive coverage proof',
            'No original mesh, material/normal comparison, final G-buffer publication or mobile performance claim']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures', required=True, type=Path)
    p.add_argument('--bank', required=True, type=Path)
    p.add_argument('--pose', type=int, default=0)
    p.add_argument('--uniform-samples', type=int, default=10000)
    p.add_argument('--seed', type=int, default=1729)
    p.add_argument('--require-pass', action='store_true')
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    if a.uniform_samples < 0:
        p.error('uniform-samples cannot be negative')
    result = inspect(a.captures, a.bank, a.pose, a.uniform_samples, a.seed)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('remaining_witnesses', 'provenance')}, indent=2))
    if a.require_pass and not result['strict_gate_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
