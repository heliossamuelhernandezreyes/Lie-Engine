"""Independent exhaustive check of samples omitted by the native planner.

Uses original immutable bank samples and the scene packets exported from the
actual GDExtension. The GPU tests separately require exact final buffers.
"""
import argparse
import json
from pathlib import Path

import numpy as np


def validate(stage):
    report = json.loads((stage / 'native-visibility-planning.json').read_text())
    if report['failed'] or len(report['cases']) != 3:
        raise ValueError('native_planning_cases')
    banks = {i: np.memmap(stage / 'captures/hq_construction/banks' / name / 'library.bin', dtype='<f4', mode='r').reshape(-1, 20)
             for i, name in enumerate(report['bank_names'])}
    summaries = []
    for case in report['cases']:
        packets = case['packets']
        instances = np.fromfile(stage / packets['instances'], dtype='<f4').reshape(-1, 24)
        jobs = np.fromfile(stage / packets['jobs'], dtype='<u4').reshape(-1, 4)
        parameters = np.fromfile(stage / packets['parameters'], dtype='<f4')
        work = sum(int(j[1]) for j in jobs)
        selected = np.zeros(work, dtype=bool)
        for bank in case['banks']:
            packed = np.fromfile(stage / bank['file'], dtype='<u4')
            rows = packed[:bank['jobs']*4].reshape(-1, 4)
            if len(rows) != bank['jobs'] or not len(rows) or rows[0, 0] != 0:
                raise ValueError('dispatch_rows')
            for k, (prefix, first, job, unused) in enumerate(rows):
                amount = int(rows[k + 1, 0] if k + 1 < len(rows) else bank['work']) - int(prefix)
                start, count, instance, global_first = map(int, jobs[job])
                ids = packed[first:first+amount] if unused == 1 else np.arange(first,first+amount,dtype='<u4')
                if unused not in (0,1) or len(ids)!=amount or len(np.unique(ids))!=amount or amount < 1 or np.any(ids<global_first) or np.any(ids>=global_first+count) or int(instances[instance, 17]) != bank['bank'] or selected[ids].any():
                    raise ValueError('dispatch_address_or_overlap')
                selected[ids] = True
        omitted = 0
        maximum = -1.
        for start, count, instance, first in jobs:
            omitted_mask = ~selected[first:first + count]
            if not omitted_mask.any():
                continue
            inst = instances[instance]
            basis = np.column_stack([inst[:3], inst[4:7], inst[8:11]]).astype(np.float32)
            source = banks[int(inst[17])][start:start + count][omitted_mask]
            world = source[:, :3] @ basis.T + inst[12:15]
            normal = source[:, 4:7] @ np.linalg.inv(basis)
            normal /= np.maximum(np.linalg.norm(normal, axis=1)[:, None], 1e-30)
            sight = parameters[:3] - world
            sight /= np.maximum(np.linalg.norm(sight, axis=1)[:, None], 1e-30)
            front = np.einsum('ij,ij->i', normal, sight)
            if not np.isfinite(front).all() or np.any(front > .015):
                raise ValueError('native_dropped_front_facing_sample')
            omitted += len(source)
            maximum = max(maximum, float(front.max()))
        if int(selected.sum()) != case['result']['selected_samples'] or omitted != case['result']['backface_skipped_samples']:
            raise ValueError('planner_count_reconciliation')
        summaries.append({'state': case['state'], 'logical_samples': work, 'selected_samples': int(selected.sum()),
                          'exhaustively_checked_omissions': omitted, 'maximum_omitted_front_cosine': maximum,
                          'native_planning_cpu_usec': case['result']['cpu_usec']})
    if not any(row['exhaustively_checked_omissions'] for row in summaries):
        raise ValueError('no_real_work_eliminated')
    result = {'schema': 'lie-native-backface-validation/1', 'cases': summaries, 'failed': False,
              'scope': 'Every omitted original source sample checked with independent NumPy float32 geometry. Not GPU timing; exact Vulkan buffer checks are separate.'}
    (stage / 'native-visibility-validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    validate(parser.parse_args().stage)
