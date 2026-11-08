"""Native Vulkan output comparison; never extrapolate llvmpipe speed to Android."""
import argparse
import json
from pathlib import Path
import numpy as np


def compare(baseline, candidate, output):
    before = json.loads((baseline / 'construction-reconstruction-native.json').read_text())
    after = json.loads((candidate / 'construction-reconstruction-native.json').read_text())
    assert not before['failed'] and not after['failed']
    assert len(before['cases']) == len(after['cases']) == 10
    rows = []
    for a, b in zip(before['cases'], after['cases']):
        assert a['case'] == b['case'] and a['state'] == b['state'] and a['samples'] == b['samples']
        index = a['case']
        ac = np.fromfile(baseline / f'reconstruction-case{index}-color.f32', '<f4').reshape(-1, 4)
        bc = np.fromfile(candidate / f'reconstruction-case{index}-color.f32', '<f4').reshape(-1, 4)
        ad = np.fromfile(baseline / f'reconstruction-case{index}-depth.f32', '<f4')
        bd = np.fromfile(candidate / f'reconstruction-case{index}-depth.f32', '<f4')
        assert ac.shape == bc.shape and np.isfinite(ac).all() and np.isfinite(bc).all()
        peak = float(np.max(np.abs(ac - bc)))
        depth_equal = np.array_equal(ad.view('<u4'), bd.view('<u4'))
        alpha_equal = np.array_equal(ac[:, 3], bc[:, 3])
        row = {'case': index, 'depth_bit_exact': depth_equal, 'alpha_bit_exact': alpha_equal,
               'peak_rgba_error': peak, 'baseline_command_ms': a['command_ms'], 'candidate_command_ms': b['command_ms'],
               'baseline_last_profile': a['profile'][-1] if a['profile'] else {},
               'candidate_last_profile': b['profile'][-1] if b['profile'] else {}}
        rows.append(row)
        assert depth_equal and alpha_equal and peak <= 1e-6, row
    report = {'schema': 'lie-construction-reconstruction-comparison/1', 'cases': rows,
              'physical_android_tested': False, 'same_source_samples_and_lod': True,
              'scope': 'Same attributed capture banks, controls, 960 output / 1920 internal. Software Vulkan correctness and host observations only.'}
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('RECONSTRUCTION COMPARISON PASS', len(rows), 'max RGBA', max(x['peak_rgba_error'] for x in rows))
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    for name in ['baseline', 'candidate', 'output']:p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args();compare(a.baseline, a.candidate, a.output)
