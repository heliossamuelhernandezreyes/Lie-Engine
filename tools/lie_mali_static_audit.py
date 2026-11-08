"""Run an externally installed Mali Offline Compiler on the actual SPIR-V.

Compiler estimates are not frame times, device benchmarks or driver certification.
The proprietary compiler and capture banks are never copied into the repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def audit(compiler, spirv, destination):
    destination.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([str(compiler), '--version'], text=True).strip()
    rows = []
    for core in ['Mali-G720', 'Mali-G610', 'Mali-G57', 'Mali-G31']:
        for stage in [1, 2, 3, 4, 7, 8]:
            source = spirv / f'stage-{stage}.spv'
            raw = destination / f'{core}-stage-{stage}.json'
            command = [str(compiler), '--vulkan', '--spirv', '--compute', '--core', core,
                       '--format', 'json', str(source), '-o', str(raw)]
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
            report = json.loads(raw.read_text())
            shader = report['shaders'][0]
            variant = shader['variants'][0]
            properties = {p['name']: p['value'] for p in variant['properties']}
            perf = variant['performance']
            rows.append({'core': core, 'stage': stage, 'driver_model': shader['driver'],
                         'spirv_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                         'spirv_bytes': source.stat().st_size,
                         'properties': properties, 'performance': perf,
                         'warnings': shader.get('warnings', []), 'notes': shader.get('notes', [])})
    result = {'schema': 'lie-mali-static-shader-audit/1', 'compiler': version,
              'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'physical_android_tested': False, 'rows': rows,
              'scope': 'Static compilation of the original Godot-produced SPIR-V for four Arm core/compiler models. Loop trip counts, actual memory contention, driver version, thermal limits and frame times are not measured. Successful compilation is not device compatibility certification.'}
    (destination / 'mali-static-summary.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--spirv', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    report = audit(args.compiler.resolve(), args.spirv.resolve(), args.output.resolve())
    print(json.dumps({'compiled_shaders': len(report['rows']), 'output': str(args.output)}))
