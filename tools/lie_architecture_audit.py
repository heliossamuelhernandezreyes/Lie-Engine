"""Reproduce the immutable input and verify a Godot/native kernel control.

This tool never interprets software Vulkan timings as Android performance.
It compares complete depth/owner/material buffers, rather than screenshots.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import zipfile

ARTIFACT_SHA256 = '66c95efcf9653ad4f89b72c30d12e6d7dc4b81529cb0fbb1a691835d8593e55b'
APK_SHA256 = '0bdd8f5e4ac13423203f2f9bda526205cad71edbc3ded74c78c834afd6ac5ba7'


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def restore(artifact, output):
    if sha(artifact) != ARTIFACT_SHA256:
        raise ValueError('immutable_ci_archive_hash')
    if output.exists():
        raise ValueError('restore_requires_fresh_directory')
    with zipfile.ZipFile(artifact) as archive:
        names = [n for n in archive.namelist() if n.endswith('/LIE-Construccion-v6.3.0.apk')]
        if len(names) != 1:
            raise ValueError('one_immutable_apk_required')
        apk = output.with_suffix('.apk')
        with archive.open(names[0]) as source, apk.open('wb') as target:
            shutil.copyfileobj(source, target)
    if sha(apk) != APK_SHA256:
        raise ValueError('immutable_apk_hash')
    with zipfile.ZipFile(apk) as archive:
        proof = json.loads(archive.read('assets/build-source.json'))
        assert len(proof['source_files_sha256']) == 90 and not proof['source_resampling']
        for name, digest in proof['source_files_sha256'].items():
            relative = Path(name).relative_to('captures/hq_construction')
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('asset_path')
            data = archive.read('assets/' + name)
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('immutable_asset_hash:' + name)
            path = output / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    return {'verified_files': 90, 'runtime_commit': proof['code_commit'],
            'apk_sha256': APK_SHA256, 'capture_bank_bindings': proof['immutable_v5_capture_bank_bindings']}


def stats(values):
    if not values:
        raise ValueError('missing_timing_samples')
    return {'samples': len(values), 'median_ms': statistics.median(values),
            'min_ms': min(values), 'max_ms': max(values)}


def compare(stage, destination):
    cases = []
    for name in ['whole', 'close']:
        root = stage / 'architecture-fixtures' / name
        fixture = json.loads((root / 'fixture.json').read_text())
        native = json.loads((root / 'native-replay.json').read_text())
        if fixture['device'] != native['device']:
            raise ValueError('comparison_requires_same_device')
        for filename, expected in fixture['inputs'].items():
            file = root / filename
            if file.stat().st_size != expected['bytes'] or sha(file) != expected['sha256']:
                raise ValueError('replay_input_integrity:' + filename)
        exact = {}
        for binding in [4, 5, 7]:
            actual = root / f'native-{binding}.bin'
            expected = fixture['reference'][str(binding)]
            exact[str(binding)] = actual.stat().st_size == expected['bytes'] and sha(actual) == expected['sha256']
        if not all(exact.values()):
            raise ValueError('native_depth_owner_material_mismatch:' + name + ':' + str(exact))
        godot = fixture['godot_profiles']
        native_rows = [r for r in native['rows'] if not r['warm_up']]
        if len(godot) != 5 or len(native_rows) != 5:
            raise ValueError('five_hot_samples_required')
        # Add the paired intervals within EACH frame before taking a median.
        godot_paired = [(r['passes_ns']['projection_depth'] + r['passes_ns']['material_accumulation']) / 1e6 for r in godot]
        native_paired = [r['projection_depth_ms'] + r['material_accumulation_ms'] for r in native_rows]
        godot_record = [sum(s['record_elapsed_ms'] for s in r['stages'] if s['stage'] in [2, 3]) for r in fixture['godot_cpu_samples']]
        candidates = []
        for variant in ['hoist', 'cache']:
            candidate_path = root / f'candidate-{variant}-replay.json'
            if not candidate_path.exists():
                continue
            candidate = json.loads(candidate_path.read_text())
            candidate_rows = [r for r in candidate['rows'] if not r['warm_up']]
            candidate_exact = {}
            for binding in [4, 5, 7]:
                actual = root / f'candidate-{variant}-{binding}.bin'
                expected = fixture['reference'][str(binding)]
                candidate_exact[str(binding)] = actual.stat().st_size == expected['bytes'] and sha(actual) == expected['sha256']
            candidates.append({'variant': variant, 'exact_buffers': candidate_exact,
                               'exact': all(candidate_exact.values()),
                               'paired_gpu': stats([r['projection_depth_ms'] + r['material_accumulation_ms'] for r in candidate_rows]),
                               'raw_rows': candidate_rows,
                               'adopted': False,
                               'scope': 'Exploratory shader rewrite. Even exact buffers and a software timing improvement do not qualify it for Android adoption.'})
        cases.append({'case': name, 'device': native['device'], 'logical_samples': fixture['samples'],
                      'camera_samples': fixture['camera_samples'], 'internal_size': fixture['internal_size'],
                      'exact_buffers': exact, 'godot_paired_gpu': stats(godot_paired),
                      'native_paired_gpu': stats(native_paired),
                      'godot_record_projection_material_cpu': stats(godot_record),
                      'native_record_clear_projection_material_cpu': stats([r['record_cpu_ms'] for r in native_rows]),
                      'godot_callback_cpu': stats([r['callback_elapsed_ms'] for r in fixture['godot_cpu_samples']]),
                      'capabilities': {k: native[k] for k in ['api_version', 'driver_version', 'timestamp_valid_bits', 'max_storage_buffer_range', 'max_storage_buffers_per_stage']},
                      'raw_godot_gpu_ns': [r['passes_ns'] for r in godot], 'raw_native_rows': native_rows,
                      'candidates': candidates})
    result = {'schema': 'lie-godot-native-kernel-control/1', 'failed': False, 'cases': cases,
              'physical_android_tested': False,
              'scope': 'Same host/device, exact Godot-compiled SPIR-V and input bytes. Buffer equality covers depth, winner ownership and material accumulation. GPU intervals are paired before aggregation. Five hot samples are diagnostic, not a sustained game benchmark. Godot samples alternate bank order at a fixed camera; native does the same. Native omits field, shadows, shading and presentation. CPU intervals have explicitly different scopes. Host-visible replay buffers are experimental and are not a production mobile memory design. Software Vulkan timings do not establish Mali performance.'}
    destination.write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--artifact', type=Path)
    p.add_argument('--restore', type=Path)
    p.add_argument('--compare', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    if args.restore and args.artifact:
        result = restore(args.artifact, args.restore)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    elif args.compare:
        result = compare(args.compare, args.output)
    else:
        p.error('provide --artifact/--restore or --compare')
    print(json.dumps({'output': str(args.output), 'failed': result.get('failed', False), 'cases': len(result.get('cases', []))}))
