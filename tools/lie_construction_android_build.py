"""Stage/export the v6 construction consumer with immutable high-quality data."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
import lie_hq_construction_stage as construction
import lie_runtime_android_build as android

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'org.lieengine.construction.v6'
VERSION = '6.0.0-construction-field'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def stage(data, destination, require_probe=False):
    manifest = json.loads((data / 'manifest.json').read_text())
    for bank, binding in manifest['bank_bindings'].items():
        folder = data / 'banks' / bank
        assert sha(folder / 'library.bin') == binding['sha256']
        if binding.get('optical'):
            assert sha(folder / 'optical-normals.bin') == binding['optical']
        assert (folder / 'pages.json').is_file()
    assert json.loads((data / 'fields/materials.json').read_text())['scene_identity'] == manifest['scene_identity']
    construction.stage(data, destination)
    # Desktop staging deliberately hides immutable data from editor import.
    # Android export must enumerate it: .gdignore also suppresses explicit
    # include-filter paths. Remove only this staging marker, never source data.
    (destination / 'captures/hq_construction/.gdignore').unlink()
    pending = ['lie_construction_mobile_lab.tscn', 'test_lie_construction_mobile.gd',
               'test_lie_construction_mobile_metrics.gd', 'test_lie_hardware_probe.gd']
    copied = set()
    pattern = re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name = pending.pop()
        if name in copied:
            continue
        source = ROOT / 'gpu_compute' / name
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        copied.add(name)
        if source.suffix in ('.gd', '.tscn', '.tres'):
            pending.extend(pattern.findall(source.read_text()))
    probe = ROOT / 'gpu_compute/addons/lie_gpu_probe'
    if (probe / 'lie_gpu_probe.gdextension').is_file():
        shutil.copytree(probe, destination / 'addons/lie_gpu_probe')
    elif require_probe:
        raise ValueError('Build the actual native telemetry module before exporting')
    project = android.PROJECT.replace('LIE Pared', 'LIE Construccion 6').replace('0.1.0', '6.0.0').replace('lie_runtime_android_lab.tscn', 'lie_construction_mobile_lab.tscn')
    project = project.replace('pointing/emulate_mouse_from_touch=true', 'pointing/emulate_mouse_from_touch=false')
    project += '\n[editor]\nimport/use_multiple_threads=false\n'
    (destination / 'project.godot').write_text(project)
    (destination / 'icon.svg').write_text(android.ICON)
    assets = {p.relative_to(destination).as_posix(): sha(p)
              for p in sorted((destination / 'captures/hq_construction').rglob('*'))
              if p.is_file() and p.suffix in ('.bin', '.json')}
    proof = {'schema': 'lie-construction-android-source/1', 'version': VERSION,
             'package': PACKAGE, 'scene_identity': manifest['scene_identity'],
             'code_commit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
             'source_files_sha256': assets, 'immutable_v5_capture_bank_bindings': manifest['bank_bindings'],
             'default_output': 960, 'default_internal': 1920, 'source_resampling': False,
             'physical_android_tested': False}
    (destination / 'build-source.json').write_text(json.dumps(proof, indent=2) + '\n')
    filters = list(assets) + ['build-source.json', 'ATTRIBUTION.txt', 'addons/lie_gpu_probe/licenses/*.txt', 'addons/lie_gpu_probe/bin/*/build.json']
    preset = re.sub(r'^include_filter=.*$', 'include_filter=' + json.dumps(','.join(filters)), android.PRESET, flags=re.M)
    preset = preset.replace('version/code=1\n', 'version/code=600\n').replace('0.1.0-runtime-lighting', VERSION).replace('org.lieengine.wallruntime', PACKAGE).replace('LIE Pared', 'LIE Construccion 6')
    preset = preset.replace('exclude_filter="test_*,*.log,*.apk"', 'exclude_filter="test_*,workshop/test_*,fixtures/*,*.log,*.apk,addons/lie_gpu_probe/bin/linux.x86_64/*"')
    (destination / 'export_presets.cfg').write_text(preset)
    (destination / 'ATTRIBUTION.txt').write_text(
        'LIE Construccion 6.0.0, experimental capture reconstruction. Powered by Poly Haven.\n'
        'Stratford New Place Brick Ver 2 by Centre-of-Archaeology, CC BY 4.0.\n'
        'https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a\n'
        'https://creativecommons.org/licenses/by/4.0/\n'
        'Modifications: authored frame, captured samples, cut halves, LOD, instance placement and coded lighting.\n'
        'Mortar: Brick Wall 04 by Dimitrios Savva / Dario Barresi / Rico Cilliers, Poly Haven, CC0.\n'
        'https://polyhaven.com/a/brick_wall_04\n'
        'Concrete Layers by Amal Kumar, Poly Haven, CC0. https://polyhaven.com/a/concrete_layers\n'
        'Wood Table Worn by Dimitrios Savva / Rico Cilliers, Poly Haven, CC0. https://polyhaven.com/a/wood_table_worn\n'
        'Construction profiles, UV mapping, layout and derived captures authored by LIE.\n'
        'No new whole-object scans. Original capture banks and source attribution retained.\n'
        'Godot 4.7.2, MIT: https://godotengine.org/license/\n\n'
        + (ROOT / 'tools/licenses/GODOT_LICENSE.txt').read_text())
    return proof


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--stage', type=Path, required=True)
    for name in ['godot', 'sdk', 'keystore', 'output']:
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    proof = stage(args.data.resolve(), args.stage.resolve(), require_probe=bool(args.output))
    if args.output:
        if not all([args.godot, args.sdk, args.keystore]):
            raise ValueError('Export requires Godot, SDK and debug keystore')
        result = android.export(args.stage.resolve(), args.godot.resolve(), args.sdk.resolve(), args.keystore.resolve(), args.output.resolve())
        result.update(package=PACKAGE, version=VERSION, scene_identity=proof['scene_identity'], code_commit=proof['code_commit'])
        (args.output.parent / 'android-build.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))
    else:
        print(json.dumps({'scene_identity': proof['scene_identity'], 'data_files': len(proof['source_files_sha256'])}))
